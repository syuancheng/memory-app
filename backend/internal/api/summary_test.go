package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// seedCardWithStatus 直接建一张卡 + 对应的 review_state，绕开调度器，
// 这样可以精确控制 status/due_at/has_graduated 组合来验证 /me/summary 和候选池查询的计数口径。
func seedCardWithStatus(t *testing.T, ctx context.Context, pool *pgxpool.Pool, u testUser, status string, dueAt time.Time, hasGraduated bool) string {
	t.Helper()
	cardID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO cards (id, user_id, subject_id, set_id, front_text, answer_text)
		VALUES ($1, $2, $3, $4, 'front', 'answer')
	`, cardID, u.ID, u.SubjectID, u.SetID); err != nil {
		t.Fatalf("seed card: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO review_states (card_id, status, due_at, has_graduated)
		VALUES ($1, $2, $3, $4)
	`, cardID, status, dueAt, hasGraduated); err != nil {
		t.Fatalf("seed review_state: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM review_states WHERE card_id = $1`, cardID)
		_, _ = pool.Exec(ctx, `DELETE FROM cards WHERE id = $1`, cardID)
	})
	return cardID
}

func TestMeSummarySplitsNewAndReviewDueCounts(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	// seedUser 自带一张卡但没建 review_state（LEFT JOIN 出来是 NULL），
	// 不落入任何一个分桶，不影响下面的断言。
	now := time.Now().UTC()

	// 应计入 new_count：两张 new 卡，一张 due_at 在未来也一样算（new 不看 due_at）。
	seedCardWithStatus(t, ctx, pool, user, "new", now, false)
	seedCardWithStatus(t, ctx, pool, user, "new", now.Add(24*time.Hour), false)

	// 也应计入 new_count（不是 review_due_count！）：一张从没毕业过、被 Again/Hard
	// 打回 learning 状态、冷却时间已过的卡——这正是这次要修的那个 bug 场景。
	seedCardWithStatus(t, ctx, pool, user, "learning", now.Add(-time.Minute), false)

	// 应计入 review_due_count：真正毕业过（has_graduated=true）且已到期，
	// 不管当前是 review 状态还是 lapse 回了 learning。
	seedCardWithStatus(t, ctx, pool, user, "review", now.Add(-24*time.Hour), true)
	seedCardWithStatus(t, ctx, pool, user, "learning", now.Add(-time.Hour), true)

	// 不应计入 review_due_count：毕业过，但还没到期。
	seedCardWithStatus(t, ctx, pool, user, "review", now.Add(24*time.Hour), true)

	// 不应计入任何 due/new 桶，但应计入 total_cards 和 mastered_count。
	seedCardWithStatus(t, ctx, pool, user, "mastered", now.Add(-time.Hour), true)

	// 软删除的卡不应计入 total_cards。
	deletedCardID := seedCardWithStatus(t, ctx, pool, user, "new", now, false)
	if _, err := pool.Exec(ctx, `UPDATE cards SET deleted_at = now() WHERE id = $1`, deletedCardID); err != nil {
		t.Fatalf("soft-delete card: %v", err)
	}

	rec := call(t, handler, http.MethodGet, "/api/me/summary", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /me/summary: status %d body %s", rec.Code, rec.Body.String())
	}

	var summary meSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}

	// 2 张纯 new + 1 张从没毕业过但已到期的 learning。
	if summary.NewCount != 3 {
		t.Errorf("new_count = %d, want 3", summary.NewCount)
	}
	// 2 张毕业过且到期的（1 review + 1 lapse 回 learning）。
	if summary.ReviewDueCount != 2 {
		t.Errorf("review_due_count = %d, want 2", summary.ReviewDueCount)
	}
	// due_count 是历史上的「new+review 合并口径」，不看 has_graduated，且对 new 卡
	// 也看 due_at（这点跟 new_count 不同）。上面种了一张 due_at 在未来的 new 卡和
	// 一张 due_at 在未来的 review 卡，due_count 都应该漏掉：
	// 2 张 new-已到期 之外的 1 张 + 1 张从没毕业的 learning-到期 + 1 张 review-到期
	// + 1 张 lapse-learning-到期 = 4。
	if summary.DueCount != 4 {
		t.Errorf("due_count = %d, want 4", summary.DueCount)
	}
	if summary.MasteredCount != 1 {
		t.Errorf("mastered_count = %d, want 1", summary.MasteredCount)
	}
	// seedUser 的卡(1，无 review_state) + 本测试新建 8 张 - 1 张软删 = 8
	if summary.TotalCards != 8 {
		t.Errorf("total_cards = %d, want 8", summary.TotalCards)
	}
}

// TestUngraduatedCardStaysInLearnNotReview 是这次 bug 的核心回归测试：一张新卡被
// Again 打回 learning、冷却时间一过，应该继续出现在 Learn 的候选池里，绝不能出现在
// Review 的候选池里——即使它的 status/due_at 组合乍看跟"到期的复习卡"一模一样。
func TestUngraduatedCardStaysInLearnNotReview(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	// 冷却时间设在过去，模拟"已经过了 Again 的 1 分钟冷却"。
	cardID := seedCardWithStatus(t, ctx, pool, user, "learning", time.Now().UTC().Add(-time.Minute), false)

	reviewRec := call(t, handler, http.MethodGet,
		fmt.Sprintf("/api/review/session?mode=review&subject_id=%s&set_ids=%s", user.SubjectID, user.SetID),
		user.Token, nil)
	if reviewRec.Code != http.StatusOK {
		t.Fatalf("GET /review/session?mode=review: status %d body %s", reviewRec.Code, reviewRec.Body.String())
	}
	var reviewSession reviewSessionResponse
	if err := json.Unmarshal(reviewRec.Body.Bytes(), &reviewSession); err != nil {
		t.Fatalf("decode review session: %v body=%s", err, reviewRec.Body.String())
	}
	for _, card := range reviewSession.Cards {
		if card.ID == cardID {
			t.Fatalf("ungraduated card %s must not appear in a Review session", cardID)
		}
	}

	learnRec := call(t, handler, http.MethodGet,
		fmt.Sprintf("/api/review/session?mode=learn&subject_id=%s&set_ids=%s", user.SubjectID, user.SetID),
		user.Token, nil)
	if learnRec.Code != http.StatusOK {
		t.Fatalf("GET /review/session?mode=learn: status %d body %s", learnRec.Code, learnRec.Body.String())
	}
	var learnSession reviewSessionResponse
	if err := json.Unmarshal(learnRec.Body.Bytes(), &learnSession); err != nil {
		t.Fatalf("decode learn session: %v body=%s", err, learnRec.Body.String())
	}
	found := false
	for _, card := range learnSession.Cards {
		if card.ID == cardID {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("ungraduated card %s should still show up in a Learn session", cardID)
	}
}

// TestNewLearnedTodayCountsOnlyGraduatedCards 验证 new_learned_today 的口径：
// 一张新卡连续 3 次 Again 会被判 leech（今天先放一放），不算学完；
// 另一张卡 Good 两次真正毕业（status 变成 review）才算 +1。
func TestNewLearnedTodayCountsOnlyGraduatedCards(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	now := time.Now().UTC()
	leechCardID := seedCardWithStatus(t, ctx, pool, user, "new", now, false)
	graduateCardID := seedCardWithStatus(t, ctx, pool, user, "new", now, false)

	sessionRec := call(t, handler, http.MethodGet,
		fmt.Sprintf("/api/review/session?mode=learn&subject_id=%s&set_ids=%s", user.SubjectID, user.SetID),
		user.Token, nil)
	if sessionRec.Code != http.StatusOK {
		t.Fatalf("GET /review/session: status %d body %s", sessionRec.Code, sessionRec.Body.String())
	}
	var session reviewSessionResponse
	if err := json.Unmarshal(sessionRec.Body.Bytes(), &session); err != nil {
		t.Fatalf("decode session: %v body=%s", err, sessionRec.Body.String())
	}

	submit := func(cardID string, rating string) {
		t.Helper()
		rec := call(t, handler, http.MethodPost, "/api/review/result", user.Token, map[string]any{
			"card_id":    cardID,
			"session_id": session.ID,
			"mode":       "learn",
			"rating":     rating,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("submit %s %s: status %d body %s", cardID, rating, rec.Code, rec.Body.String())
		}
	}

	submit(leechCardID, "again")
	submit(leechCardID, "again")
	submit(leechCardID, "again")

	submit(graduateCardID, "good")
	submit(graduateCardID, "good")

	rec := call(t, handler, http.MethodGet, "/api/me/summary", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /me/summary: status %d body %s", rec.Code, rec.Body.String())
	}
	var summary meSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}
	if summary.NewLearnedToday != 1 {
		t.Errorf("new_learned_today = %d, want 1 (leeched card must not count)", summary.NewLearnedToday)
	}
}
