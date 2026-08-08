package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"net/mail"
	"net/smtp"
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

	CodeTTL       = 10 * time.Minute
	SessionTTL    = 30 * 24 * time.Hour
	SendCooldown  = 60 * time.Second
	MaxCodeTries  = 5
	sessionPrefix = "cdly_"
)

type Config struct {
	TokenSecret string
	DevCodeLog  bool
	SMTP        SMTPConfig
	Apple       AppleConfig
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
	return &Service{
		pool:         pool,
		cfg:          cfg,
		now:          time.Now,
		httpClient:   &http.Client{Timeout: 8 * time.Second},
		appleJWKSURL: "https://appleid.apple.com/auth/keys",
	}, nil
}

func (s *Service) RequestEmailCode(ctx context.Context, email string, purpose string) error {
	email, err := NormalizeEmail(email)
	if err != nil {
		return err
	}
	if !validPurpose(purpose) {
		return errors.New("invalid verification purpose")
	}
	if purpose == PurposeDeleteAccount {
		var exists bool
		if err := s.pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM users
				WHERE lower(email) = lower($1) AND deleted_at IS NULL
			)
		`, email).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return errors.New("user not found")
		}
	}

	var lastCreatedAt *time.Time
	err = s.pool.QueryRow(ctx, `
		SELECT created_at
		FROM auth_verification_codes
		WHERE identifier = $1 AND purpose = $2 AND consumed_at IS NULL
		ORDER BY created_at DESC
		LIMIT 1
	`, email, purpose).Scan(&lastCreatedAt)
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
	codeHash := s.hashValue(email + ":" + purpose + ":" + code)
	_, err = s.pool.Exec(ctx, `
		INSERT INTO auth_verification_codes (
			id, identifier_type, identifier, purpose, code_hash, expires_at
		) VALUES ($1, 'email', $2, $3, $4, $5)
	`, uuid.NewString(), email, purpose, codeHash, s.now().Add(CodeTTL))
	if err != nil {
		return err
	}

	return s.sendEmailCode(email, code, purpose)
}

func (s *Service) VerifyLoginCode(ctx context.Context, email string, code string) (User, string, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, "", err
	}
	if err := s.consumeCode(ctx, email, PurposeLogin, code); err != nil {
		return User{}, "", err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, "", err
	}
	defer tx.Rollback(ctx)

	var user User
	err = tx.QueryRow(ctx, `
		INSERT INTO users (id, email, primary_email, name, display_name, status, deleted_at, last_login_at)
		VALUES ($1, $2, $2, $3, $3, 'active', NULL, now())
		ON CONFLICT (email) DO UPDATE
		SET deleted_at = NULL,
		    status = 'active',
		    primary_email = EXCLUDED.primary_email,
		    last_login_at = now(),
		    updated_at = now()
		RETURNING id::text, COALESCE(primary_email, email), COALESCE(display_name, name, '')
	`, uuid.NewString(), email, defaultName(email)).Scan(&user.ID, &user.Email, &user.Name)
	if err != nil {
		return User{}, "", err
	}

	token, err := s.createSession(ctx, tx, user.ID)
	if err != nil {
		return User{}, "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, "", err
	}
	return user, token, nil
}

func (s *Service) VerifyEmailCodeForUser(ctx context.Context, email string, purpose string, code string) (User, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	if !validPurpose(purpose) {
		return User{}, errors.New("invalid verification purpose")
	}
	if err := s.consumeCode(ctx, email, purpose, code); err != nil {
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
		if err := s.consumeCode(ctx, user.Email, PurposeDeleteAccount, code); err != nil {
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
		FROM users
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

func (s *Service) consumeCode(ctx context.Context, email string, purpose string, code string) error {
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
		WHERE identifier = $1
		  AND purpose = $2
		  AND consumed_at IS NULL
		  AND expires_at > now()
		ORDER BY created_at DESC
		LIMIT 1
		FOR UPDATE
	`, email, purpose).Scan(&id, &expectedHash, &attempts)
	if err == pgx.ErrNoRows {
		return errors.New("verification code is invalid or expired")
	}
	if err != nil {
		return err
	}
	if attempts >= MaxCodeTries {
		return errors.New("verification code attempts exceeded")
	}

	actualHash := s.hashValue(email + ":" + purpose + ":" + code)
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

func (s *Service) sendEmailCode(email string, code string, purpose string) error {
	if s.cfg.DevCodeLog {
		log.Printf("auth verification code for %s (%s): %s", email, purpose, code)
		return nil
	}
	if s.cfg.SMTP.Host == "" || s.cfg.SMTP.From == "" {
		return errors.New("email delivery is not configured")
	}

	subject := "Your Cardly verification code"
	if purpose == PurposeDeleteAccount {
		subject = "Confirm your Cardly account deletion"
	}
	body := fmt.Sprintf("Your Cardly verification code is %s. It expires in 10 minutes.", code)
	message := strings.Join([]string{
		"From: " + s.cfg.SMTP.From,
		"To: " + email,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"",
		body,
	}, "\r\n")

	addr := s.cfg.SMTP.Host + ":" + s.cfg.SMTP.Port
	var smtpAuth smtp.Auth
	if s.cfg.SMTP.User != "" || s.cfg.SMTP.Pass != "" {
		smtpAuth = smtp.PlainAuth("", s.cfg.SMTP.User, s.cfg.SMTP.Pass, s.cfg.SMTP.Host)
	}
	return smtp.SendMail(addr, smtpAuth, s.cfg.SMTP.From, []string{email}, []byte(message))
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
	return purpose == PurposeLogin || purpose == PurposeDeleteAccount
}
