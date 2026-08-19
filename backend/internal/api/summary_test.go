package api

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// seedCardWithStatus 直接建一张卡 + 对应的 review_state，绕开调度器，
// 这样可以精确控制 status/due_at 组合来验证 /me/summary 的计数口径。
func seedCardWithStatus(t *testing.T, ctx context.Context, pool *pgxpool.Pool, u testUser, status string, dueAt time.Time) string {
	t.Helper()
	cardID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO cards (id, user_id, subject_id, set_id, front_text, answer_text)
		VALUES ($1, $2, $3, $4, 'front', 'answer')
	`, cardID, u.ID, u.SubjectID, u.SetID); err != nil {
		t.Fatalf("seed card: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO review_states (card_id, status, due_at)
		VALUES ($1, $2, $3)
	`, cardID, status, dueAt); err != nil {
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
	seedCardWithStatus(t, ctx, pool, user, "new", now)
	seedCardWithStatus(t, ctx, pool, user, "new", now.Add(24*time.Hour))

	// 应计入 review_due_count：learning/review 且已到期。
	seedCardWithStatus(t, ctx, pool, user, "learning", now.Add(-time.Minute))
	seedCardWithStatus(t, ctx, pool, user, "review", now.Add(-24*time.Hour))
	seedCardWithStatus(t, ctx, pool, user, "review", now.Add(-time.Hour))

	// 不应计入 review_due_count：review 但还没到期。
	seedCardWithStatus(t, ctx, pool, user, "review", now.Add(24*time.Hour))

	// 不应计入任何 due/new 桶，但应计入 total_cards 和 mastered_count。
	seedCardWithStatus(t, ctx, pool, user, "mastered", now.Add(-time.Hour))

	// 软删除的卡不应计入 total_cards。
	deletedCardID := seedCardWithStatus(t, ctx, pool, user, "new", now)
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

	if summary.NewCount != 2 {
		t.Errorf("new_count = %d, want 2", summary.NewCount)
	}
	if summary.ReviewDueCount != 3 {
		t.Errorf("review_due_count = %d, want 3", summary.ReviewDueCount)
	}
	// due_count 是历史上的「new+review 合并口径」，且它对 new 卡也看 due_at——
	// 这点和 new_count 不同（new_count 不管 due_at，任何时候都该能学）。
	// 上面特意种了一张 due_at 在未来的 new 卡，due_count 应该漏掉它，
	// 只数：new-未来 之外的 1 张 new + 3 张 review_due = 4。
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
