package auth

import "context"

// IssueSessionForTest 直接为已存在的用户签发 session，绕开验证码流程。
//
// 仅供测试使用：跨租户测试关心的是「拿到 token 之后能碰到谁的数据」，
// 走一遍完整登录只会引入无关的失败点。放在非 _test.go 文件里是因为
// 它需要被 internal/api 的测试跨包调用。
func (s *Service) IssueSessionForTest(ctx context.Context, userID string) (string, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	token, err := s.createSession(ctx, tx, userID)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return token, nil
}
