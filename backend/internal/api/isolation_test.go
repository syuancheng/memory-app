package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"memory-app/backend/internal/auth"
	"memory-app/backend/internal/db"
)

// 跨租户回归。审计确认 REST 层当前是干净的；这些用例存在的意义是
// 防止以后新增或改写端点时悄悄丢掉 user_id 过滤。
//
// 判据统一为：拿别人的资源 ID 去调，必须拿不到数据、也改不动，
// 而不是「返回了空结果就算安全」—— 后者在 UPDATE/DELETE 上不成立。

type testUser struct {
	ID        string
	Token     string
	SubjectID string
	SetID     string
	CardID    string
}

func newTestEnv(t *testing.T) (http.Handler, *pgxpool.Pool, *auth.Service) {
	t.Helper()
	ctx := context.Background()

	pool, err := db.Open(ctx, "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable")
	if err != nil {
		t.Skipf("database unavailable: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := db.SetupTestSchema(ctx, pool); err != nil {
		t.Fatalf("setup test schema: %v", err)
	}

	authService, err := auth.NewService(pool, auth.Config{TokenSecret: "isolation-test-secret", DevCodeLog: true})
	if err != nil {
		t.Fatalf("auth service: %v", err)
	}
	return NewServer(pool, authService), pool, authService
}

// seedUser 直接建库记录，绕开验证码流程 —— 这里测的是隔离，不是登录。
func seedUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, svc *auth.Service) testUser {
	t.Helper()

	userID := uuid.NewString()
	email := "iso-" + uuid.NewString()[:12] + "@example.com"

	if _, err := pool.Exec(ctx, `
		INSERT INTO users (id, email, primary_email, name, display_name, status)
		VALUES ($1, $2, $2, $3, $3, 'active')`, userID, email, "Isolation Test"); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO identities (id, user_id, type, value, verified_at)
		VALUES ($1, $2, 'email', $3, now())`, uuid.NewString(), userID, email); err != nil {
		t.Fatalf("seed identity: %v", err)
	}

	subjectID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO subjects (id, user_id, name) VALUES ($1, $2, $3)`,
		subjectID, userID, "Iso "+subjectID[:8]); err != nil {
		t.Fatalf("seed subject: %v", err)
	}
	setID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO sets (id, user_id, subject_id, name) VALUES ($1, $2, $3, $4)`,
		setID, userID, subjectID, "Set "+setID[:8]); err != nil {
		t.Fatalf("seed set: %v", err)
	}
	cardID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO cards (id, user_id, subject_id, set_id, front_text, answer_text)
		VALUES ($1, $2, $3, $4, 'front', 'answer')`, cardID, userID, subjectID, setID); err != nil {
		t.Fatalf("seed card: %v", err)
	}

	token, err := svc.IssueSessionForTest(ctx, userID)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM daily_check_ins WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM review_events WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM review_states WHERE card_id = $1`, cardID)
		_, _ = pool.Exec(ctx, `DELETE FROM cards WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM sets WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM subjects WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM auth_sessions WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM identities WHERE user_id = $1`, userID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
	})

	return testUser{ID: userID, Token: token, SubjectID: subjectID, SetID: setID, CardID: cardID}
}

func call(t *testing.T, handler http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func TestCannotReachAnotherUsersCard(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	alice := seedUser(t, ctx, pool, svc)
	bob := seedUser(t, ctx, pool, svc)

	// 每一条都用 Bob 的 token 去碰 Alice 的卡片。
	cases := []struct {
		method string
		path   string
		body   any
	}{
		{http.MethodGet, "/api/cards/" + alice.CardID, nil},
		{http.MethodGet, "/api/cards/" + alice.CardID + "/review-preview", nil},
		{http.MethodDelete, "/api/cards/" + alice.CardID, nil},
		{http.MethodPost, "/api/cards/" + alice.CardID + "/master", nil},
		{http.MethodPut, "/api/cards/" + alice.CardID, map[string]any{
			"set_id":      bob.SetID,
			"front_text":  "hijacked",
			"answer_text": "hijacked",
		}},
		{http.MethodPost, "/api/review/result", map[string]any{
			"card_id": alice.CardID, "mode": "review", "rating": "good",
		}},
	}

	for _, tc := range cases {
		rec := call(t, handler, tc.method, tc.path, bob.Token, tc.body)
		if rec.Code == http.StatusOK || rec.Code == http.StatusCreated {
			t.Errorf("%s %s: Bob reached Alice's card (status %d, body %s)",
				tc.method, tc.path, rec.Code, rec.Body.String())
		}
	}

	// 卡片必须原封不动。
	var front string
	if err := pool.QueryRow(ctx,
		`SELECT front_text FROM cards WHERE id = $1 AND deleted_at IS NULL`, alice.CardID).Scan(&front); err != nil {
		t.Fatalf("Alice's card should still exist: %v", err)
	}
	if front != "front" {
		t.Fatalf("Alice's card was modified: %q", front)
	}
}

func TestReviewResultIsIdempotentWithClientReviewID(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)
	if _, err := pool.Exec(ctx, `
		INSERT INTO review_states (card_id)
		VALUES ($1)
	`, user.CardID); err != nil {
		t.Fatalf("seed review state: %v", err)
	}

	clientReviewID := uuid.NewString()
	body := map[string]any{
		"card_id":          user.CardID,
		"client_review_id": clientReviewID,
		"mode":             "review",
		"rating":           "good",
	}
	first := call(t, handler, http.MethodPost, "/api/review/result", user.Token, body)
	if first.Code != http.StatusOK {
		t.Fatalf("first review failed: status %d body %s", first.Code, first.Body.String())
	}
	second := call(t, handler, http.MethodPost, "/api/review/result", user.Token, body)
	if second.Code != http.StatusOK {
		t.Fatalf("idempotent retry failed: status %d body %s", second.Code, second.Body.String())
	}

	var reviewCount int
	if err := pool.QueryRow(ctx, `
		SELECT review_count
		FROM review_states
		WHERE card_id = $1
	`, user.CardID).Scan(&reviewCount); err != nil {
		t.Fatalf("load review count: %v", err)
	}
	if reviewCount != 1 {
		t.Fatalf("review_count = %d, want 1", reviewCount)
	}

	var eventCount int
	if err := pool.QueryRow(ctx, `
		SELECT count(*)
		FROM review_events
		WHERE user_id = $1 AND client_review_id = $2
	`, user.ID, clientReviewID).Scan(&eventCount); err != nil {
		t.Fatalf("count review events: %v", err)
	}
	if eventCount != 1 {
		t.Fatalf("review event count = %d, want 1", eventCount)
	}
}

func TestCannotAttachCardToAnotherUsersSubject(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	alice := seedUser(t, ctx, pool, svc)
	bob := seedUser(t, ctx, pool, svc)

	// Bob 试图把卡片挂到 Alice 的 set 下。
	for _, body := range []map[string]any{
		{"set_id": alice.SetID, "front_text": "x", "answer_text": "y"},
	} {
		rec := call(t, handler, http.MethodPost, "/api/cards", bob.Token, body)
		if rec.Code == http.StatusOK || rec.Code == http.StatusCreated {
			t.Errorf("card creation should have been rejected: %s", rec.Body.String())
		}
	}
}

func TestListEndpointsOnlyReturnOwnData(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	alice := seedUser(t, ctx, pool, svc)
	bob := seedUser(t, ctx, pool, svc)

	rec := call(t, handler, http.MethodGet, "/api/subjects", bob.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list subjects: %d", rec.Code)
	}
	var subjects []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &subjects); err != nil {
		t.Fatalf("decode: %v", err)
	}
	for _, s := range subjects {
		if s.ID == alice.SubjectID {
			t.Fatal("Bob can see Alice's subject")
		}
	}

	// 即便显式按 Alice 的 subject 过滤，也只能得到空结果。
	rec = call(t, handler, http.MethodGet,
		fmt.Sprintf("/api/cards?subject_id=%s", alice.SubjectID), bob.Token, nil)
	var cards []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &cards); err != nil {
		t.Fatalf("decode cards: %v", err)
	}
	if len(cards) != 0 {
		t.Fatalf("filtering by another user's subject leaked %d cards", len(cards))
	}

	// Alice 的 subject 下的 sets 同理。
	rec = call(t, handler, http.MethodGet,
		"/api/subjects/"+alice.SubjectID+"/sets", bob.Token, nil)
	var sets []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &sets); err != nil {
		t.Fatalf("decode sets: %v", err)
	}
	if len(sets) != 0 {
		t.Fatalf("leaked %d sets from another user's subject", len(sets))
	}
}

func TestCannotMutateAnotherUsersSubjectOrSet(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	alice := seedUser(t, ctx, pool, svc)
	bob := seedUser(t, ctx, pool, svc)

	cases := []struct {
		method string
		path   string
		body   any
	}{
		{http.MethodPut, "/api/subjects/" + alice.SubjectID, map[string]string{"name": "hijacked"}},
		{http.MethodDelete, "/api/subjects/" + alice.SubjectID, nil},
		{http.MethodPost, "/api/subjects/" + alice.SubjectID + "/sets", map[string]string{"name": "hijacked"}},
		{http.MethodPut, "/api/subjects/" + alice.SubjectID + "/sets/" + alice.SetID, map[string]string{"name": "hijacked"}},
		{http.MethodDelete, "/api/subjects/" + alice.SubjectID + "/sets/" + alice.SetID, nil},
	}
	for _, tc := range cases {
		rec := call(t, handler, tc.method, tc.path, bob.Token, tc.body)
		if rec.Code == http.StatusOK || rec.Code == http.StatusCreated {
			t.Errorf("%s %s succeeded for another user (body %s)", tc.method, tc.path, rec.Body.String())
		}
	}

	var name string
	if err := pool.QueryRow(ctx,
		`SELECT name FROM subjects WHERE id = $1 AND deleted_at IS NULL`, alice.SubjectID).Scan(&name); err != nil {
		t.Fatalf("Alice's subject should be untouched: %v", err)
	}
}

func TestCannotRevokeAnotherUsersMCPToken(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	alice := seedUser(t, ctx, pool, svc)
	bob := seedUser(t, ctx, pool, svc)

	_, meta, err := svc.CreateMCPToken(ctx, alice.ID, "alice client")
	if err != nil {
		t.Fatalf("create token: %v", err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(ctx, `DELETE FROM mcp_tokens WHERE user_id = $1`, alice.ID) })

	rec := call(t, handler, http.MethodDelete, "/api/mcp/tokens/"+meta.ID, bob.Token, nil)
	if rec.Code == http.StatusOK {
		t.Fatal("Bob revoked Alice's MCP token")
	}

	var revoked bool
	if err := pool.QueryRow(ctx,
		`SELECT revoked_at IS NOT NULL FROM mcp_tokens WHERE id = $1`, meta.ID).Scan(&revoked); err != nil {
		t.Fatalf("check token: %v", err)
	}
	if revoked {
		t.Fatal("Alice's token was revoked by another user")
	}
}

func TestUnauthenticatedRequestsAreRejected(t *testing.T) {
	handler, _, _ := newTestEnv(t)
	for _, path := range []string{"/api/subjects", "/api/cards", "/api/me/summary", "/api/mcp/tokens"} {
		rec := call(t, handler, http.MethodGet, path, "", nil)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s without a token returned %d, want 401", path, rec.Code)
		}
	}
}
