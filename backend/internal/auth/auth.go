package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"math/big"
	"net/http"
	"net/mail"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	PurposeLogin         = "login"
	PurposeDeleteAccount = "delete_account"
	PurposePasswordReset = "password_reset"

	CodeTTL       = 10 * time.Minute
	SessionTTL    = 30 * 24 * time.Hour
	SendCooldown  = 60 * time.Second
	MaxCodeTries  = 5
	sessionPrefix = "cdly_"
)

type Config struct {
	TokenSecret string
	DevCodeLog  bool
	Resend      ResendConfig
	SMTP        SMTPConfig
	Apple       AppleConfig
}

type ResendConfig struct {
	APIKey string
	// From 形如 "Cardly <noreply@example.com>"，域名须在 Resend 验证过。
	From string
}

type SMTPConfig struct {
	Host string
	Port string
	User string
	Pass string
	From string
}

type AppleConfig struct {
	TeamID        string
	KeyID         string
	PrivateKey    string
	IOSBundleID   string
	WebServicesID string
	RedirectURI   string
}

type Service struct {
	pool         *pgxpool.Pool
	cfg          Config
	now          func() time.Time
	httpClient   *http.Client
	appleJWKSURL string
	sender       CodeSender
	appleKeysMu  sync.Mutex
	appleKeys    appleKeySet
	appleKeysAt  time.Time
}

type User struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	Name     string `json:"name"`
	Provider string `json:"provider,omitempty"`
}

func NewService(pool *pgxpool.Pool, cfg Config) (*Service, error) {
	if strings.TrimSpace(cfg.TokenSecret) == "" {
		return nil, errors.New("auth token secret is required")
	}
	if cfg.SMTP.Port == "" {
		cfg.SMTP.Port = "587"
	}
	svc := &Service{
		pool:         pool,
		cfg:          cfg,
		now:          time.Now,
		httpClient:   &http.Client{Timeout: 8 * time.Second},
		appleJWKSURL: "https://appleid.apple.com/auth/keys",
	}
	svc.sender = newCodeSender(cfg, svc.httpClient)
	return svc, nil
}

// RequestCode 生成并投递验证码。
//
// identifierType 决定投递通道（邮箱走邮件、将来手机号走短信）；
// (identifierType, identifier, purpose) 三元组共同定位一条码，
// 避免不同类型的同名标识符互相消费。
func (s *Service) RequestCode(ctx context.Context, identifierType, identifier, purpose string) error {
	identifier, err := s.normalizeIdentifier(identifierType, identifier)
	if err != nil {
		return err
	}
	if !validPurpose(purpose) {
		return errors.New("invalid verification purpose")
	}
	if purpose == PurposeDeleteAccount || purpose == PurposePasswordReset {
		userID, err := s.UserIDByIdentity(ctx, identifierType, identifier)
		if err != nil {
			return err
		}
		if userID == "" {
			// 重置密码不暴露账号是否存在：静默成功，不发信也不落库。
			if purpose == PurposePasswordReset {
				return nil
			}
			return errors.New("user not found")
		}
	}

	var lastCreatedAt *time.Time
	err = s.pool.QueryRow(ctx, `
		SELECT created_at
		FROM auth_verification_codes
		WHERE identifier_type = $1 AND identifier = $2 AND purpose = $3 AND consumed_at IS NULL
		ORDER BY created_at DESC
		LIMIT 1
	`, identifierType, identifier, purpose).Scan(&lastCreatedAt)
	if err != nil && err != pgx.ErrNoRows {
		return err
	}
	if lastCreatedAt != nil && s.now().Before(lastCreatedAt.Add(SendCooldown)) {
		return errors.New("please wait before requesting another code")
	}

	code, err := randomDigits(6)
	if err != nil {
		return err
	}

	// 先投递再落库。反过来的话，投递失败时用户既看到报错、又因为库里已有
	// 一条未消费的码而被冷却 60 秒。
	if err := s.sender.SendCode(ctx, identifierType, identifier, code, purpose); err != nil {
		return err
	}

	codeHash := s.hashValue(identifierType + ":" + identifier + ":" + purpose + ":" + code)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO auth_verification_codes (
			id, identifier_type, identifier, purpose, code_hash, expires_at
		) VALUES ($1, $2, $3, $4, $5, $6)
	`, uuid.NewString(), identifierType, identifier, purpose, codeHash, s.now().Add(CodeTTL))
	return err
}

// RequestEmailCode 保留为邮箱通道的便捷入口。
func (s *Service) RequestEmailCode(ctx context.Context, email string, purpose string) error {
	return s.RequestCode(ctx, IdentityEmail, email, purpose)
}

func (s *Service) normalizeIdentifier(identifierType, identifier string) (string, error) {
	switch identifierType {
	case IdentityEmail:
		return NormalizeEmail(identifier)
	case IdentityPhone:
		// 手机号尚未启用；这里先占位，接入时补 E.164 归一化。
		return "", errors.New("phone identifiers are not supported yet")
	default:
		return "", errors.New("unsupported identifier type")
	}
}

func (s *Service) VerifyLoginCode(ctx context.Context, email string, code string) (User, string, bool, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, "", false, err
	}
	if err := s.consumeCode(ctx, IdentityEmail, email, PurposeLogin, code); err != nil {
		return User{}, "", false, err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, "", false, err
	}
	defer tx.Rollback(ctx)

	user, isNew, err := s.FindOrCreateUser(ctx, tx, IdentityRef{
		Type:     IdentityEmail,
		Value:    email,
		Email:    email,
		Verified: true,
	})
	if err != nil {
		return User{}, "", false, err
	}

	token, err := s.createSession(ctx, tx, user.ID)
	if err != nil {
		return User{}, "", false, err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, "", false, err
	}
	return user, token, isNew, nil
}

func (s *Service) VerifyEmailCodeForUser(ctx context.Context, email string, purpose string, code string) (User, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	if !validPurpose(purpose) {
		return User{}, errors.New("invalid verification purpose")
	}
	if err := s.consumeCode(ctx, IdentityEmail, email, purpose, code); err != nil {
		return User{}, err
	}
	return s.FindUserByEmail(ctx, email)
}

func (s *Service) FindUserByEmail(ctx context.Context, email string) (User, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	var user User
	err = s.pool.QueryRow(ctx, `
		SELECT id::text, COALESCE(primary_email, email), COALESCE(display_name, name, ''), 'email'
		FROM users
		WHERE lower(email) = lower($1) AND deleted_at IS NULL AND status = 'active'
	`, email).Scan(&user.ID, &user.Email, &user.Name, &user.Provider)
	return user, err
}

func (s *Service) ValidateSession(ctx context.Context, token string) (User, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return User{}, errors.New("missing session token")
	}
	tokenHash := s.hashValue(token)
	var user User
	err := s.pool.QueryRow(ctx, `
		SELECT u.id::text, COALESCE(u.primary_email, u.email), COALESCE(u.display_name, u.name, ''), COALESCE(ac.provider, 'email')
		FROM auth_sessions sess
		JOIN users u ON u.id = sess.user_id
		LEFT JOIN account_connections ac ON ac.user_id = u.id AND ac.provider = 'apple'
		WHERE sess.token_hash = $1
		  AND sess.revoked_at IS NULL
		  AND sess.expires_at > now()
		  AND u.deleted_at IS NULL
		  AND u.status = 'active'
	`, tokenHash).Scan(&user.ID, &user.Email, &user.Name, &user.Provider)
	if err == pgx.ErrNoRows {
		return User{}, errors.New("invalid session token")
	}
	return user, err
}

func (s *Service) Logout(ctx context.Context, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return nil
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE auth_sessions
		SET revoked_at = now()
		WHERE token_hash = $1 AND revoked_at IS NULL
	`, s.hashValue(token))
	return err
}

func (s *Service) DeleteAccount(ctx context.Context, userID string, code string) error {
	user, err := s.FindUserByID(ctx, userID)
	if err != nil {
		return err
	}
	if user.Provider != AppleProvider {
		if err := s.consumeCode(ctx, IdentityEmail, user.Email, PurposeDeleteAccount, code); err != nil {
			return err
		}
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err = tx.Exec(ctx, `UPDATE subjects SET deleted_at = now(), updated_at = now() WHERE user_id = $1 AND deleted_at IS NULL`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE tags SET deleted_at = now(), updated_at = now() WHERE user_id = $1 AND deleted_at IS NULL`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE cards SET deleted_at = now(), updated_at = now() WHERE user_id = $1 AND deleted_at IS NULL`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `
		UPDATE review_states
		SET status = 'deleted'
		WHERE card_id IN (SELECT id FROM cards WHERE user_id = $1)
	`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE auth_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE auth_provider_tokens SET revoked_at = now(), updated_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, userID); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, `UPDATE users SET deleted_at = now(), status = 'deleted', updated_at = now() WHERE id = $1 AND deleted_at IS NULL`, userID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) FindUserByID(ctx context.Context, userID string) (User, error) {
	var user User
	err := s.pool.QueryRow(ctx, `
		SELECT u.id::text, COALESCE(u.primary_email, u.email), COALESCE(u.display_name, u.name, ''), COALESCE(ac.provider, 'email')
		FROM users u
		LEFT JOIN account_connections ac ON ac.user_id = u.id AND ac.provider = 'apple'
		WHERE u.id = $1 AND u.deleted_at IS NULL AND u.status = 'active'
	`, userID).Scan(&user.ID, &user.Email, &user.Name, &user.Provider)
	return user, err
}

func (s *Service) UserActive(ctx context.Context, userID string) bool {
	var active bool
	err := s.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM users
			WHERE id = $1 AND deleted_at IS NULL AND status = 'active'
		)
	`, userID).Scan(&active)
	return err == nil && active
}

type txSessionWriter interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}

func (s *Service) createSession(ctx context.Context, tx txSessionWriter, userID string) (string, error) {
	token, tokenHash, err := s.newSessionToken()
	if err != nil {
		return "", err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO auth_sessions (id, user_id, token_hash, expires_at)
		VALUES ($1, $2, $3, $4)
	`, uuid.NewString(), userID, tokenHash, s.now().Add(SessionTTL))
	if err != nil {
		return "", err
	}
	return token, nil
}

func (s *Service) consumeCode(ctx context.Context, identifierType, identifier string, purpose string, code string) error {
	code = strings.TrimSpace(code)
	if code == "" {
		return errors.New("code is required")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var id string
	var expectedHash string
	var attempts int
	err = tx.QueryRow(ctx, `
		SELECT id::text, code_hash, attempts
		FROM auth_verification_codes
		WHERE identifier_type = $1
		  AND identifier = $2
		  AND purpose = $3
		  AND consumed_at IS NULL
		  AND expires_at > now()
		ORDER BY created_at DESC
		LIMIT 1
		FOR UPDATE
	`, identifierType, identifier, purpose).Scan(&id, &expectedHash, &attempts)
	if err == pgx.ErrNoRows {
		return errors.New("verification code is invalid or expired")
	}
	if err != nil {
		return err
	}
	if attempts >= MaxCodeTries {
		return errors.New("verification code attempts exceeded")
	}

	actualHash := s.hashValue(identifierType + ":" + identifier + ":" + purpose + ":" + code)
	if subtle.ConstantTimeCompare([]byte(actualHash), []byte(expectedHash)) != 1 {
		_, _ = tx.Exec(ctx, `UPDATE auth_verification_codes SET attempts = attempts + 1 WHERE id = $1`, id)
		if err := tx.Commit(ctx); err != nil {
			return err
		}
		return errors.New("verification code is invalid or expired")
	}

	if _, err = tx.Exec(ctx, `UPDATE auth_verification_codes SET consumed_at = now() WHERE id = $1`, id); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) newSessionToken() (string, string, error) {
	raw, err := randomURLToken(32)
	if err != nil {
		return "", "", err
	}
	token := sessionPrefix + raw
	return token, s.hashValue(token), nil
}

func (s *Service) hashValue(value string) string {
	mac := hmac.New(sha256.New, []byte(s.cfg.TokenSecret))
	mac.Write([]byte(value))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func NormalizeEmail(email string) (string, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return "", errors.New("email is required")
	}
	if _, err := mail.ParseAddress(email); err != nil {
		return "", errors.New("invalid email")
	}
	return email, nil
}

func ExtractBearer(header string) string {
	header = strings.TrimSpace(header)
	if !strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return ""
	}
	return strings.TrimSpace(header[len("Bearer "):])
}

func randomDigits(length int) (string, error) {
	var builder strings.Builder
	for builder.Len() < length {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		builder.WriteString(strconv.FormatInt(n.Int64(), 10))
	}
	return builder.String(), nil
}

func randomURLToken(bytesLen int) (string, error) {
	buffer := make([]byte, bytesLen)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buffer), nil
}

func defaultName(email string) string {
	local, _, ok := strings.Cut(email, "@")
	if !ok || local == "" {
		return "Cardly User"
	}
	return local
}

func validPurpose(purpose string) bool {
	switch purpose {
	case PurposeLogin, PurposeDeleteAccount, PurposePasswordReset:
		return true
	default:
		return false
	}
}
