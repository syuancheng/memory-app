package auth

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"memory-app/backend/internal/db"
)

// captureSender 记录最近一次投递的验证码，让测试拿到明文而不必读日志。
type captureSender struct {
	mu    sync.Mutex
	codes map[string]string // identifierType|identifier|purpose -> code
	fail  error
}

func newCaptureSender() *captureSender {
	return &captureSender{codes: map[string]string{}}
}

func (c *captureSender) SendCode(_ context.Context, identifierType, identifier, code, purpose string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.fail != nil {
		return c.fail
	}
	c.codes[identifierType+"|"+identifier+"|"+purpose] = code
	return nil
}

func (c *captureSender) code(identifierType, identifier, purpose string) string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.codes[identifierType+"|"+identifier+"|"+purpose]
}

func newTestService(t *testing.T, ctx context.Context) (*Service, *captureSender, *pgxpool.Pool) {
	t.Helper()

	pool, err := db.Open(ctx, "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable")
	if err != nil {
		t.Skipf("database unavailable: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := db.SetupTestSchema(ctx, pool); err != nil {
		t.Fatalf("setup test schema: %v", err)
	}

	sender := newCaptureSender()
	svc := &Service{
		pool:       pool,
		cfg:        Config{TokenSecret: "test-secret"},
		now:        time.Now,
		httpClient: &http.Client{Timeout: time.Second},
		sender:     sender,
	}
	return svc, sender, pool
}

// uniqueEmail 让每次运行都用新地址，避免测试之间互相污染 ——
// 这正是 mcpserver 那个测试此前只能跑一次的原因。
func uniqueEmail(t *testing.T) string {
	t.Helper()
	return "test-" + uuid.NewString()[:12] + "@example.com"
}

func cleanupEmail(t *testing.T, ctx context.Context, pool *pgxpool.Pool, email string) {
	t.Helper()
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM auth_verification_codes WHERE identifier = $1`, email)
		_, _ = pool.Exec(ctx, `
			DELETE FROM auth_sessions WHERE user_id IN (
				SELECT user_id FROM identities WHERE type = 'email' AND value = $1)`, email)
		_, _ = pool.Exec(ctx, `
			DELETE FROM users WHERE id IN (
				SELECT user_id FROM identities WHERE type = 'email' AND value = $1)`, email)
		_, _ = pool.Exec(ctx, `DELETE FROM identities WHERE type = 'email' AND value = $1`, email)
	})
}

func TestVerifyLoginCodeCreatesThenReusesAccount(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("RequestCode: %v", err)
	}
	user, token, isNew, err := svc.VerifyLoginCode(ctx, email, sender.code(IdentityEmail, email, PurposeLogin))
	if err != nil {
		t.Fatalf("VerifyLoginCode: %v", err)
	}
	if !isNew {
		t.Fatal("first sign-in with an unknown address must report a new account")
	}
	if token == "" || user.ID == "" {
		t.Fatal("expected a session token and user id")
	}

	// 第二次登录必须复用同一账号，且 identities 仍只有一行 —— 这就是邮箱去重。
	svc.now = func() time.Time { return time.Now().Add(2 * SendCooldown) }
	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("second RequestCode: %v", err)
	}
	user2, _, isNew2, err := svc.VerifyLoginCode(ctx, email, sender.code(IdentityEmail, email, PurposeLogin))
	if err != nil {
		t.Fatalf("second VerifyLoginCode: %v", err)
	}
	if isNew2 {
		t.Fatal("a known address must not report a new account")
	}
	if user2.ID != user.ID {
		t.Fatalf("same address produced two accounts: %s vs %s", user.ID, user2.ID)
	}

	var identityRows int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM identities WHERE type = 'email' AND value = $1`, email).Scan(&identityRows); err != nil {
		t.Fatalf("count identities: %v", err)
	}
	if identityRows != 1 {
		t.Fatalf("expected exactly one identity row, got %d", identityRows)
	}
}

// 验证码由 (identifier_type, identifier, purpose) 三元组定位。
// 少了 identifier_type，未来的手机号就可能消费掉同名邮箱的码。
func TestCodesAreScopedByPurpose(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	// 先建号，否则 password_reset 会因用户不存在而静默跳过
	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("RequestCode(login): %v", err)
	}
	loginCode := sender.code(IdentityEmail, email, PurposeLogin)
	if _, _, _, err := svc.VerifyLoginCode(ctx, email, loginCode); err != nil {
		t.Fatalf("VerifyLoginCode: %v", err)
	}

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposePasswordReset); err != nil {
		t.Fatalf("RequestCode(reset): %v", err)
	}
	resetCode := sender.code(IdentityEmail, email, PurposePasswordReset)

	// 重置码不能当登录码用。
	if err := svc.consumeCode(ctx, IdentityEmail, email, PurposeLogin, resetCode); err == nil {
		t.Fatal("a password-reset code must not satisfy a login challenge")
	}
	// 反向同理：登录码已被消费，且本来也不该用于重置。
	if err := svc.consumeCode(ctx, IdentityEmail, email, PurposePasswordReset, loginCode); err == nil {
		t.Fatal("a login code must not satisfy a password reset")
	}
	// 正确的组合仍然有效。
	if err := svc.consumeCode(ctx, IdentityEmail, email, PurposePasswordReset, resetCode); err != nil {
		t.Fatalf("matching type/purpose should consume: %v", err)
	}
}

// 投递失败时不应留下验证码行 —— 否则用户既看到报错，又被冷却挡住重试。
func TestFailedDeliveryLeavesNoCodeAndNoCooldown(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	sender.fail = errors.New("upstream down")
	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err == nil {
		t.Fatal("delivery failure must surface as an error")
	}

	var rows int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM auth_verification_codes WHERE identifier = $1`, email).Scan(&rows); err != nil {
		t.Fatalf("count codes: %v", err)
	}
	if rows != 0 {
		t.Fatalf("a failed send must not persist a code row, found %d", rows)
	}

	// 因此紧接着重试不会撞上冷却。
	sender.fail = nil
	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("retry after a failed send must not be rate limited: %v", err)
	}
}

func TestPasswordLoginAndLockout(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("RequestCode: %v", err)
	}
	user, _, _, err := svc.VerifyLoginCode(ctx, email, sender.code(IdentityEmail, email, PurposeLogin))
	if err != nil {
		t.Fatalf("VerifyLoginCode: %v", err)
	}

	// 未设密码时，密码登录必须与「账号不存在」返回同样的错误。
	_, _, errNoPassword := svc.LoginWithPassword(ctx, email, "whatever-123")
	_, _, errNoAccount := svc.LoginWithPassword(ctx, uniqueEmail(t), "whatever-123")
	if errNoPassword == nil || errNoAccount == nil {
		t.Fatal("both cases must fail")
	}
	if errNoPassword.Error() != errNoAccount.Error() {
		t.Fatalf("error messages must be identical to prevent account enumeration: %q vs %q",
			errNoPassword, errNoAccount)
	}

	if err := svc.SetPassword(ctx, user.ID, "short"); err == nil {
		t.Fatal("a short password must be rejected")
	}
	if err := svc.SetPassword(ctx, user.ID, "correct-horse-battery"); err != nil {
		t.Fatalf("SetPassword: %v", err)
	}

	loggedIn, token, err := svc.LoginWithPassword(ctx, email, "correct-horse-battery")
	if err != nil {
		t.Fatalf("LoginWithPassword: %v", err)
	}
	if loggedIn.ID != user.ID || token == "" {
		t.Fatal("password login must return the same user and a session")
	}

	for i := 0; i < MaxPasswordAttempts; i++ {
		_, _, _ = svc.LoginWithPassword(ctx, email, "wrong")
	}
	_, _, err = svc.LoginWithPassword(ctx, email, "correct-horse-battery")
	if err == nil || !strings.Contains(err.Error(), "too many failed attempts") {
		t.Fatalf("account should be locked after %d failures, got %v", MaxPasswordAttempts, err)
	}
}

// 重置密码后所有旧 session 必须失效 —— 重置通常发生在怀疑账号被盗时。
func TestResetPasswordRevokesSessions(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("RequestCode: %v", err)
	}
	_, token, _, err := svc.VerifyLoginCode(ctx, email, sender.code(IdentityEmail, email, PurposeLogin))
	if err != nil {
		t.Fatalf("VerifyLoginCode: %v", err)
	}
	if _, err := svc.ValidateSession(ctx, token); err != nil {
		t.Fatalf("session should be valid before the reset: %v", err)
	}

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposePasswordReset); err != nil {
		t.Fatalf("RequestCode(reset): %v", err)
	}
	if err := svc.ResetPassword(ctx, email, sender.code(IdentityEmail, email, PurposePasswordReset), "brand-new-secret"); err != nil {
		t.Fatalf("ResetPassword: %v", err)
	}

	if _, err := svc.ValidateSession(ctx, token); err == nil {
		t.Fatal("sessions issued before a password reset must stop working")
	}
	if _, _, err := svc.LoginWithPassword(ctx, email, "brand-new-secret"); err != nil {
		t.Fatalf("the new password must work: %v", err)
	}
}

// 未注册的地址请求重置码时静默成功：既不发信也不落库，且不暴露账号是否存在。
func TestResetCodeForUnknownAddressIsSilent(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposePasswordReset); err != nil {
		t.Fatalf("must not reveal that the address is unknown: %v", err)
	}
	if sender.code(IdentityEmail, email, PurposePasswordReset) != "" {
		t.Fatal("no email should have been sent")
	}
	var rows int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM auth_verification_codes WHERE identifier = $1`, email).Scan(&rows); err != nil {
		t.Fatalf("count codes: %v", err)
	}
	if rows != 0 {
		t.Fatalf("no code row should exist, found %d", rows)
	}
}

func TestDeleteAccountWorks(t *testing.T) {
	ctx := context.Background()
	svc, sender, pool := newTestService(t, ctx)
	email := uniqueEmail(t)
	cleanupEmail(t, ctx, pool, email)

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeLogin); err != nil {
		t.Fatalf("RequestCode: %v", err)
	}
	user, token, _, err := svc.VerifyLoginCode(ctx, email, sender.code(IdentityEmail, email, PurposeLogin))
	if err != nil {
		t.Fatalf("VerifyLoginCode: %v", err)
	}

	if err := svc.RequestCode(ctx, IdentityEmail, email, PurposeDeleteAccount); err != nil {
		t.Fatalf("RequestCode(delete): %v", err)
	}
	// FindUserByID 曾因 SQL 缺表别名而报 42P01，使这条路径对所有人恒定失败。
	if err := svc.DeleteAccount(ctx, user.ID, sender.code(IdentityEmail, email, PurposeDeleteAccount)); err != nil {
		t.Fatalf("DeleteAccount: %v", err)
	}
	if _, err := svc.ValidateSession(ctx, token); err == nil {
		t.Fatal("sessions must be revoked when the account is deleted")
	}
}
