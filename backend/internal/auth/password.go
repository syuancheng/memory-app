package auth

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

const (
	MinPasswordLength = 8
	// bcrypt 的输入上限是 72 字节，超出部分会被静默丢弃 —— 显式拒绝，
	// 免得用户以为长密码更安全、实际只有前 72 字节生效。
	maxPasswordBytes = 72

	// 密码登录的失败上限，与验证码的 MaxCodeTries 相互独立。
	MaxPasswordAttempts = 10
	PasswordLockWindow  = 15 * time.Minute
)

// errInvalidCredentials 对「邮箱不存在」「密码错误」「从未设过密码」
// 一律返回同一句话，避免账号枚举。
var errInvalidCredentials = errors.New("invalid email or password")

func validatePassword(password string) error {
	if utf8.RuneCountInString(password) < MinPasswordLength {
		return errors.New("password must be at least 8 characters")
	}
	if len(password) > maxPasswordBytes {
		return errors.New("password is too long")
	}
	return nil
}

// SetPassword 设置或修改当前用户的密码。
//
// 密码是可选的快捷登录方式，验证码始终可用，因此这里不要求「先有旧密码」：
// 已登录本身就是足够的授权，且很多用户根本没有旧密码可填。
func (s *Service) SetPassword(ctx context.Context, userID, password string) error {
	if strings.TrimSpace(userID) == "" {
		return errors.New("authenticated user is required")
	}
	if err := validatePassword(password); err != nil {
		return err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `
		UPDATE users
		SET password_hash = $2,
		    password_set_at = now(),
		    failed_login_count = 0,
		    locked_until = NULL,
		    updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
	`, userID, string(hash))
	return err
}

// HasPassword 供客户端决定是否展示「用密码登录」入口。
func (s *Service) HasPassword(ctx context.Context, userID string) (bool, error) {
	var has bool
	err := s.pool.QueryRow(ctx, `
		SELECT password_hash IS NOT NULL FROM users WHERE id = $1 AND deleted_at IS NULL
	`, userID).Scan(&has)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return has, err
}

// LoginWithPassword 用邮箱 + 密码换取 session。
func (s *Service) LoginWithPassword(ctx context.Context, email, password string) (User, string, error) {
	email, err := NormalizeEmail(email)
	if err != nil {
		return User{}, "", errInvalidCredentials
	}

	userID, err := s.UserIDByIdentity(ctx, IdentityEmail, email)
	if err != nil {
		return User{}, "", err
	}
	if userID == "" {
		// 走一次假的哈希比对，让「邮箱不存在」与「密码错误」耗时相近，
		// 否则响应时间本身就是一个账号枚举信道。
		_ = bcrypt.CompareHashAndPassword(
			[]byte("$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"),
			[]byte(password))
		return User{}, "", errInvalidCredentials
	}

	var hash *string
	var failedCount int
	var lockedUntil *time.Time
	err = s.pool.QueryRow(ctx, `
		SELECT password_hash, failed_login_count, locked_until
		FROM users WHERE id = $1 AND deleted_at IS NULL AND status = 'active'
	`, userID).Scan(&hash, &failedCount, &lockedUntil)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, "", errInvalidCredentials
	}
	if err != nil {
		return User{}, "", err
	}

	if lockedUntil != nil && s.now().Before(*lockedUntil) {
		return User{}, "", errors.New("too many failed attempts, please try again later or sign in with a code")
	}
	if hash == nil {
		// 账号存在但从未设过密码。仍返回统一错误，客户端会提示改用验证码。
		return User{}, "", errInvalidCredentials
	}

	if err := bcrypt.CompareHashAndPassword([]byte(*hash), []byte(password)); err != nil {
		if err := s.recordFailedLogin(ctx, userID, failedCount+1); err != nil {
			return User{}, "", err
		}
		return User{}, "", errInvalidCredentials
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return User{}, "", err
	}
	defer tx.Rollback(ctx)

	var user User
	err = tx.QueryRow(ctx, `
		UPDATE users
		SET failed_login_count = 0, locked_until = NULL, last_login_at = now(), updated_at = now()
		WHERE id = $1
		RETURNING id::text, COALESCE(primary_email, email, ''), COALESCE(display_name, name, '')
	`, userID).Scan(&user.ID, &user.Email, &user.Name)
	if err != nil {
		return User{}, "", err
	}
	user.Provider = IdentityEmail

	token, err := s.createSession(ctx, tx, user.ID)
	if err != nil {
		return User{}, "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return User{}, "", err
	}
	return user, token, nil
}

func (s *Service) recordFailedLogin(ctx context.Context, userID string, attempts int) error {
	var lockedUntil any
	if attempts >= MaxPasswordAttempts {
		lockedUntil = s.now().Add(PasswordLockWindow)
	}
	_, err := s.pool.Exec(ctx, `
		UPDATE users SET failed_login_count = $2, locked_until = $3, updated_at = now()
		WHERE id = $1
	`, userID, attempts, lockedUntil)
	return err
}

// ResetPassword 用邮箱验证码重置密码，并撤销该用户所有现存 session ——
// 重置密码通常发生在「怀疑账号被盗」时，留着旧 session 就失去了意义。
func (s *Service) ResetPassword(ctx context.Context, email, code, password string) error {
	email, err := NormalizeEmail(email)
	if err != nil {
		return err
	}
	if err := validatePassword(password); err != nil {
		return err
	}
	if err := s.consumeCode(ctx, IdentityEmail, email, PurposePasswordReset, code); err != nil {
		return err
	}

	userID, err := s.UserIDByIdentity(ctx, IdentityEmail, email)
	if err != nil {
		return err
	}
	if userID == "" {
		return errors.New("user not found")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		UPDATE users
		SET password_hash = $2, password_set_at = now(),
		    failed_login_count = 0, locked_until = NULL, updated_at = now()
		WHERE id = $1
	`, userID, string(hash)); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE auth_sessions SET revoked_at = now()
		WHERE user_id = $1 AND revoked_at IS NULL
	`, userID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// UpdateDisplayName 改用户名。用户名纯展示，不唯一、不参与登录。
func (s *Service) UpdateDisplayName(ctx context.Context, userID, name string) (User, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return User{}, errors.New("name is required")
	}
	if utf8.RuneCountInString(name) > 60 {
		return User{}, errors.New("name is too long")
	}
	var user User
	err := s.pool.QueryRow(ctx, `
		UPDATE users SET display_name = $2, updated_at = now()
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING id::text, COALESCE(primary_email, email, ''), COALESCE(display_name, name, '')
	`, userID, name).Scan(&user.ID, &user.Email, &user.Name)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, errors.New("user not found")
	}
	user.Provider = IdentityEmail
	return user, err
}
