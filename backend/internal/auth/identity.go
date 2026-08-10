package auth

import (
	"context"
	"errors"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// 身份类型。分两类：
//
//	可验证的联系方式 —— 能收验证码，能独立作为登录入口
//	第三方身份       —— value 存 provider 的 sub / openid，需跳转授权
//
// 加手机号时只需在这里加一个常量、在 CodeSender 里加一个短信实现，
// 表结构与下面的 find-or-create 都不用动。
const (
	IdentityEmail = "email"
	IdentityPhone = "phone"
)

// IdentityRef 描述一次登录所携带的身份。所有 provider 都收敛到这一个结构，
// 各自只负责「验证凭据 → 产出 IdentityRef」，落库逻辑共用。
type IdentityRef struct {
	Type  string
	Value string // 已归一化：邮箱小写、手机号 E.164、第三方为 sub
	// Email 用于填充 users.email（展示用主邮箱）。第三方身份可能拿不到，留空即可。
	Email       string
	DisplayName string
	Verified    bool
}

// FindOrCreateUser 按 (type, value) 查身份；命中则更新登录时间，
// 未命中则新建 user + identity。必须在调用方的事务内执行，
// 以便与 createSession 一起提交。
//
// 第二个返回值表示本次是否新建了账号 —— 客户端据此决定引导「设置密码」
// 还是直接进入。这也是判断「邮箱是否已注册」的唯一途径：必须先通过
// 验证码，因此不构成账号枚举。
func (s *Service) FindOrCreateUser(ctx context.Context, tx pgx.Tx, ref IdentityRef) (User, bool, error) {
	ref.Type = strings.TrimSpace(ref.Type)
	ref.Value = strings.TrimSpace(ref.Value)
	if ref.Type == "" || ref.Value == "" {
		return User{}, false, errors.New("identity type and value are required")
	}

	var userID string
	err := tx.QueryRow(ctx, `
		SELECT user_id::text FROM identities WHERE type = $1 AND value = $2
	`, ref.Type, ref.Value).Scan(&userID)

	switch {
	case err == nil:
		// 已有身份：复活软删除的账号并刷新登录时间。
		user, err := s.touchExistingUser(ctx, tx, userID, ref)
		return user, false, err
	case errors.Is(err, pgx.ErrNoRows):
		user, err := s.createUserWithIdentity(ctx, tx, ref)
		return user, true, err
	default:
		return User{}, false, err
	}
}

func (s *Service) touchExistingUser(ctx context.Context, tx pgx.Tx, userID string, ref IdentityRef) (User, error) {
	var user User
	err := tx.QueryRow(ctx, `
		UPDATE users
		SET deleted_at = NULL,
		    status = 'active',
		    primary_email = COALESCE(NULLIF($2, ''), primary_email),
		    last_login_at = now(),
		    updated_at = now()
		WHERE id = $1
		RETURNING id::text, COALESCE(primary_email, email, ''), COALESCE(display_name, name, '')
	`, userID, ref.Email).Scan(&user.ID, &user.Email, &user.Name)
	if err != nil {
		return User{}, err
	}
	user.Provider = ref.Type

	if ref.Verified {
		if _, err := tx.Exec(ctx, `
			UPDATE identities SET verified_at = COALESCE(verified_at, now()), updated_at = now()
			WHERE type = $1 AND value = $2
		`, ref.Type, ref.Value); err != nil {
			return User{}, err
		}
	}
	return user, nil
}

func (s *Service) createUserWithIdentity(ctx context.Context, tx pgx.Tx, ref IdentityRef) (User, error) {
	displayName := strings.TrimSpace(ref.DisplayName)
	if displayName == "" && ref.Email != "" {
		displayName = defaultName(ref.Email)
	}
	if displayName == "" {
		displayName = defaultName(ref.Value)
	}

	// email 可为 NULL —— 微信/手机号身份不再需要伪造占位地址。
	var email *string
	if ref.Email != "" {
		email = &ref.Email
	}

	var user User
	err := tx.QueryRow(ctx, `
		INSERT INTO users (id, email, primary_email, name, display_name, status, last_login_at)
		VALUES ($1, $2, $2, $3, $3, 'active', now())
		RETURNING id::text, COALESCE(primary_email, email, ''), COALESCE(display_name, name, '')
	`, uuid.NewString(), email, displayName).Scan(&user.ID, &user.Email, &user.Name)
	if err != nil {
		return User{}, err
	}
	user.Provider = ref.Type

	var verifiedAt any
	if ref.Verified {
		verifiedAt = s.now()
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO identities (id, user_id, type, value, verified_at)
		VALUES ($1, $2, $3, $4, $5)
	`, uuid.NewString(), user.ID, ref.Type, ref.Value, verifiedAt); err != nil {
		return User{}, err
	}
	return user, nil
}

// UserIDByIdentity 查身份对应的用户；不存在返回空字符串而非错误，
// 供密码登录这类「不该暴露邮箱是否注册」的路径使用。
func (s *Service) UserIDByIdentity(ctx context.Context, identityType, value string) (string, error) {
	var userID string
	err := s.pool.QueryRow(ctx, `
		SELECT i.user_id::text
		FROM identities i
		JOIN users u ON u.id = i.user_id
		WHERE i.type = $1 AND i.value = $2
		  AND u.deleted_at IS NULL AND u.status = 'active'
	`, identityType, value).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return userID, nil
}
