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
	"github.com/open-spaced-repetition/go-fsrs/v3"

	"memory-app/backend/internal/model"
)

// seedCardWithState 直接建一张卡 + 对应的 review_state，绕开调度器，
// 这样可以精确控制 state/due_at/graduated_at/mastered_at 组合来验证
// /me/summary 和候选池查询的计数口径。
func seedCardWithState(t *testing.T, ctx context.Context, pool *pgxpool.Pool, u testUser, state fsrs.State, dueAt time.Time, graduatedAt *time.Time, masteredAt *time.Time) string {
	t.Helper()
	cardID := uuid.NewString()
	if _, err := pool.Exec(ctx, `
		INSERT INTO cards (id, user_id, subject_id, set_id, front_text, answer_text)
		VALUES ($1, $2, $3, $4, 'front', 'answer')
	`, cardID, u.ID, u.SubjectID, u.SetID); err != nil {
		t.Fatalf("seed card: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO review_states (card_id, state, due_at, graduated_at, mastered_at)
		VALUES ($1, $2, $3, $4, $5)
	`, cardID, int16(state), dueAt, graduatedAt, masteredAt); err != nil {
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
	past := now.Add(-time.Hour)
	future := now.Add(24 * time.Hour)

	// 应计入 new_count 和 due_count：两张 New/Learning 状态、已到期的卡。
	seedCardWithState(t, ctx, pool, user, fsrs.New, past, nil, nil)
	seedCardWithState(t, ctx, pool, user, fsrs.Learning, past, nil, nil)

	// 不应计入 new_count（未到期）。
	seedCardWithState(t, ctx, pool, user, fsrs.New, future, nil, nil)

	// 应计入 review_due_count 和 due_count：Review/Relearning 状态、已到期，
	// 不管有没有真的 graduated_at（这两个是正交概念，due_count 只看 state+due_at）。
	graduatedAt := now.Add(-24 * time.Hour)
	seedCardWithState(t, ctx, pool, user, fsrs.Review, past, &graduatedAt, nil)
	seedCardWithState(t, ctx, pool, user, fsrs.Relearning, past, &graduatedAt, nil)

	// 不应计入 review_due_count（未到期）。
	seedCardWithState(t, ctx, pool, user, fsrs.Review, future, &graduatedAt, nil)

	// 不应计入任何 due/new 桶，但应计入 total_cards 和 mastered_count。
	masteredAt := now.Add(-time.Hour)
	seedCardWithState(t, ctx, pool, user, fsrs.Review, past, &graduatedAt, &masteredAt)

	// 软删除的卡不应计入 total_cards。
	deletedCardID := seedCardWithState(t, ctx, pool, user, fsrs.New, past, nil, nil)
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

	// 1 张 New-到期 + 1 张 Learning-到期。
	if summary.NewCount != 2 {
		t.Errorf("new_count = %d, want 2", summary.NewCount)
	}
	// 1 张 Review-到期 + 1 张 Relearning-到期（都没被 mastered）。
	if summary.ReviewDueCount != 2 {
		t.Errorf("review_due_count = %d, want 2", summary.ReviewDueCount)
	}
	// due_count = new_count + review_due_count（未 mastered 且已到期，不分 state）。
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

// TestUngraduatedCardStaysInLearnNotReview 是这次改动的核心回归测试：一张还没
// 毕业过的卡（state=Learning）不管 graduated_at 是什么，只要 state 落在
// New/Learning 里，就必须只出现在 Learn 的候选池里，绝不能出现在 Review 的候选池里。
func TestUngraduatedCardStaysInLearnNotReview(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	// 冷却时间设在过去，模拟"已经过了 Again 的 1 分钟冷却"。
	cardID := seedCardWithState(t, ctx, pool, user, fsrs.Learning, time.Now().UTC().Add(-time.Minute), nil, nil)

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
			t.Fatalf("state=Learning card %s must not appear in a Review session", cardID)
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
		t.Fatalf("state=Learning card %s should still show up in a Learn session", cardID)
	}
}

// TestSubjectAndSetDueCountsOnlyCountReviewingCards 校验 /api/subjects、/api/sets
// 的 due_count 只统计 state IN (Review, Relearning) 的到期卡（这是 Review 入口的
// 角标数字，不是 Learn+Review 合并口径），Learning 状态的到期卡不该算进去。
func TestSubjectAndSetDueCountsOnlyCountReviewingCards(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	now := time.Now().UTC()
	// 还在 Learning 阶段、冷却已过——不该算进 due_count（这是 Review 角标，只看
	// state IN (Review, Relearning)）。
	seedCardWithState(t, ctx, pool, user, fsrs.Learning, now.Add(-time.Minute), nil, nil)
	// 真正进了 Review 阶段且已到期的——应该算进 due_count。
	graduatedAt := now.Add(-time.Hour)
	seedCardWithState(t, ctx, pool, user, fsrs.Review, now.Add(-time.Minute), &graduatedAt, nil)

	assertDueCount := func(path string) {
		t.Helper()
		rec := call(t, handler, http.MethodGet, path, user.Token, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s: status %d body %s", path, rec.Code, rec.Body.String())
		}
		var subjects []model.Subject
		if err := json.Unmarshal(rec.Body.Bytes(), &subjects); err != nil {
			t.Fatalf("decode %s: %v body=%s", path, err, rec.Body.String())
		}
		for _, subject := range subjects {
			if subject.ID == user.SubjectID && subject.DueCount != 1 {
				t.Errorf("%s: subject due_count = %d, want 1 (only the Review-state card)", path, subject.DueCount)
			}
		}
	}
	assertDueCount("/api/subjects")

	setsRec := call(t, handler, http.MethodGet, "/api/sets", user.Token, nil)
	if setsRec.Code != http.StatusOK {
		t.Fatalf("GET /api/sets: status %d body %s", setsRec.Code, setsRec.Body.String())
	}
	var sets []model.Set
	if err := json.Unmarshal(setsRec.Body.Bytes(), &sets); err != nil {
		t.Fatalf("decode /api/sets: %v body=%s", err, setsRec.Body.String())
	}
	for _, set := range sets {
		if set.ID == user.SetID && set.DueCount != 1 {
			t.Errorf("/api/sets: set due_count = %d, want 1 (only the Review-state card)", set.DueCount)
		}
	}
}

// TestNewLearnedTodayCountsOnlyGraduatedCards 验证 new_learned_today 的口径：
// 只统计今天真正第一次进入 Review/Relearning（graduated_at 落在今天）的卡，
// 反复 Again 但还没毕业的卡不算。
func TestNewLearnedTodayCountsOnlyGraduatedCards(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	now := time.Now().UTC()
	strugglingCardID := seedCardWithState(t, ctx, pool, user, fsrs.New, now, nil, nil)
	graduateCardID := seedCardWithState(t, ctx, pool, user, fsrs.New, now, nil, nil)

	submit := func(cardID string, rating string) {
		t.Helper()
		rec := call(t, handler, http.MethodPost, "/api/review/result", user.Token, map[string]any{
			"card_id": cardID,
			"mode":    "learn",
			"rating":  rating,
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("submit %s %s: status %d body %s", cardID, rating, rec.Code, rec.Body.String())
		}
	}

	// 一直 Again，FSRS 短期步进下始终停在 Learning，不毕业。
	submit(strugglingCardID, "again")
	submit(strugglingCardID, "again")

	// Easy 直接毕业进入 Review。
	submit(graduateCardID, "easy")

	rec := call(t, handler, http.MethodGet, "/api/me/summary", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /me/summary: status %d body %s", rec.Code, rec.Body.String())
	}
	var summary meSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}
	if summary.NewLearnedToday != 1 {
		t.Errorf("new_learned_today = %d, want 1 (the still-struggling card must not count)", summary.NewLearnedToday)
	}
}

// TestCheckInFailsWhenGoalNotComplete 校验打卡接口不信任客户端——只要还有到期的
// 新卡/复习没做完，服务端重算 remaining 时会发现没完成，直接拒绝打卡。
func TestCheckInFailsWhenGoalNotComplete(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	seedCardWithState(t, ctx, pool, user, fsrs.New, time.Now().UTC().Add(-time.Hour), nil, nil)

	rec := call(t, handler, http.MethodPost, "/api/check-in", user.Token, nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("POST /check-in with an unlearned due card: status %d, want 400. body=%s", rec.Code, rec.Body.String())
	}
}

// TestCheckInSucceedsAndIsIdempotent 校验目标达成后打卡成功、写入 checked_in_today，
// 且连续打卡天数从 0 变成 1；同一天重复打卡不应该把 streak 推到 2（幂等）。
func TestCheckInSucceedsAndIsIdempotent(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)
	// seedUser 自带的卡没有 review_state（LEFT JOIN 为 NULL），不计入 new_count/
	// review_due_count，所以这个新账号今天的目标本来就是「零任务」——天然满足打卡条件。
	rec := call(t, handler, http.MethodPost, "/api/check-in", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /check-in: status %d body %s", rec.Code, rec.Body.String())
	}
	var summary meSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}
	if !summary.CheckedInToday {
		t.Errorf("checked_in_today = false, want true after checking in")
	}
	if summary.CurrentStreak != 1 {
		t.Errorf("current_streak = %d, want 1 after the first check-in", summary.CurrentStreak)
	}

	rec = call(t, handler, http.MethodPost, "/api/check-in", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("second POST /check-in: status %d body %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}
	if summary.CurrentStreak != 1 {
		t.Errorf("current_streak = %d, want 1 (checking in twice the same day must be idempotent)", summary.CurrentStreak)
	}
}

// TestCurrentStreakCountsConsecutiveCheckInsBackFromToday 校验 streak 是从「本地
// 今天」往回数连续打卡天数，中间断一天就必须停，不能跳过断档继续往回数。
func TestCurrentStreakCountsConsecutiveCheckInsBackFromToday(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)

	// 跟 localDayRange 默认时区（tz_offset_minutes 缺省时是 UTC+8）算「本地今天」
	// 的口径保持一致，直接在 SQL 里用同样的偏移量算出第 N 天前的本地日期。
	insertCheckIn := func(daysAgo int) {
		t.Helper()
		if _, err := pool.Exec(ctx, `
			INSERT INTO daily_check_ins (id, user_id, check_in_date)
			VALUES ($1, $2, ((now() AT TIME ZONE 'UTC' + interval '8 hours')::date - $3::int))
		`, uuid.NewString(), user.ID, daysAgo); err != nil {
			t.Fatalf("seed check-in (days_ago=%d): %v", daysAgo, err)
		}
	}

	// 昨天、前天连续打卡，今天还没打——streak 应该从昨天数起 = 2。
	insertCheckIn(1)
	insertCheckIn(2)
	// 4 天前有一条，但 3 天前断了——不该被并进当前这段连续里。
	insertCheckIn(4)

	rec := call(t, handler, http.MethodGet, "/api/me/summary", user.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /me/summary: status %d body %s", rec.Code, rec.Body.String())
	}
	var summary meSummaryResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &summary); err != nil {
		t.Fatalf("decode summary: %v body=%s", err, rec.Body.String())
	}
	if summary.CheckedInToday {
		t.Errorf("checked_in_today = true, want false (no check-in row seeded for today)")
	}
	if summary.CurrentStreak != 2 {
		t.Errorf("current_streak = %d, want 2 (yesterday + the day before, stopped by the gap at 3 days ago)", summary.CurrentStreak)
	}
}
