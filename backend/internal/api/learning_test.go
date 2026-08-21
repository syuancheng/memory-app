package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/open-spaced-repetition/go-fsrs/v3"
)

// setNewCardsPerDay 通过 PATCH /learning/preferences 把每日新卡上限改成 n，
// 复用真实接口而不是直连 DB，顺带验证 updateLearningPreferences 本身没坏。
func setNewCardsPerDay(t *testing.T, handler http.Handler, u testUser, n int) {
	t.Helper()
	rec := call(t, handler, http.MethodPatch, "/api/learning/preferences", u.Token, map[string]any{
		"new_cards_per_day": n,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("PATCH /learning/preferences new_cards_per_day=%d: status %d body %s", n, rec.Code, rec.Body.String())
	}
}

func fetchLearnSession(t *testing.T, handler http.Handler, u testUser) reviewSessionResponse {
	t.Helper()
	rec := call(t, handler, http.MethodGet,
		fmt.Sprintf("/api/review/session?mode=learn&subject_id=%s&set_ids=%s", u.SubjectID, u.SetID),
		u.Token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /review/session?mode=learn: status %d body %s", rec.Code, rec.Body.String())
	}
	var session reviewSessionResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &session); err != nil {
		t.Fatalf("decode learn session: %v body=%s", err, rec.Body.String())
	}
	return session
}

func submitRating(t *testing.T, handler http.Handler, u testUser, cardID string, rating string) {
	t.Helper()
	rec := call(t, handler, http.MethodPost, "/api/review/result", u.Token, map[string]any{
		"card_id": cardID,
		"mode":    "learn",
		"rating":  rating,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("submit %s %s: status %d body %s", cardID, rating, rec.Code, rec.Body.String())
	}
}

func cardIDsOf(session reviewSessionResponse) map[string]bool {
	ids := make(map[string]bool, len(session.Cards))
	for _, card := range session.Cards {
		ids[card.ID] = true
	}
	return ids
}

// TestLearnSessionCapsNewCardsPerDay 是这次改动的核心回归测试：连续对同一批新卡
// 点 Again 既不会让第 6 张新卡混进来，也不会让已经在学的卡因为 FSRS 给的短期
// due_at 还没到就从队列里消失——直到它们全部毕业，队列才应该清空。
func TestLearnSessionCapsNewCardsPerDay(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)
	setNewCardsPerDay(t, handler, user, 2)

	now := time.Now().UTC()
	past := now.Add(-time.Hour)
	var cardIDs []string
	for i := 0; i < 5; i++ {
		cardIDs = append(cardIDs, seedCardWithState(t, ctx, pool, user, fsrs.New, past, nil, nil))
	}

	first := fetchLearnSession(t, handler, user)
	if len(first.Cards) != 2 {
		t.Fatalf("initial learn session has %d cards, want 2 (capped by new_cards_per_day)", len(first.Cards))
	}
	introduced := cardIDsOf(first)
	var cardA, cardB string
	for _, id := range cardIDs {
		if introduced[id] && cardA == "" {
			cardA = id
		} else if introduced[id] {
			cardB = id
		}
	}
	if cardA == "" || cardB == "" {
		t.Fatalf("could not identify the two introduced cards from %v", first.Cards)
	}

	// 对 cardA 连续 Again 三次：每次之后队列必须还是同样这两张卡，不多不少——
	// 既不会因为 FSRS 把 due_at 推到几分钟后就把 cardA 挤出队列（进而误判"稍后
	// 再来"），也不会趁机塞进第 3 张全新卡。
	for i := 0; i < 3; i++ {
		submitRating(t, handler, user, cardA, "again")
		session := fetchLearnSession(t, handler, user)
		if len(session.Cards) != 2 {
			t.Fatalf("after again #%d: learn session has %d cards, want 2. cards=%v", i+1, len(session.Cards), session.Cards)
		}
		ids := cardIDsOf(session)
		if !ids[cardA] || !ids[cardB] {
			t.Fatalf("after again #%d: learn session = %v, want exactly {cardA, cardB}", i+1, session.Cards)
		}
		if session.NextAvailableAt != nil {
			t.Fatalf("after again #%d: next_available_at = %v, want nil (cardA should be immediately available, not waiting on FSRS due_at)", i+1, session.NextAvailableAt)
		}
	}

	// cardB 毕业：不该腾出名额去拉第 3 张新卡，队列应该只剩 cardA。
	submitRating(t, handler, user, cardB, "easy")
	afterGraduate := fetchLearnSession(t, handler, user)
	if len(afterGraduate.Cards) != 1 {
		t.Fatalf("after cardB graduates: learn session has %d cards, want 1 (cardA only). cards=%v", len(afterGraduate.Cards), afterGraduate.Cards)
	}
	if !cardIDsOf(afterGraduate)[cardA] {
		t.Fatalf("after cardB graduates: learn session = %v, want {cardA}", afterGraduate.Cards)
	}

	// cardA 也毕业：今天的配额已经用完，即使 deck 里还有 3 张没碰过的新卡，
	// 队列应该清空且不提示"稍后再来"。
	submitRating(t, handler, user, cardA, "easy")
	final := fetchLearnSession(t, handler, user)
	if len(final.Cards) != 0 {
		t.Fatalf("after all introduced cards graduate: learn session has %d cards, want 0. cards=%v", len(final.Cards), final.Cards)
	}
	if final.NextAvailableAt != nil {
		t.Fatalf("after all introduced cards graduate: next_available_at = %v, want nil even though untouched backlog cards remain", final.NextAvailableAt)
	}
}

// TestLearnSessionQuotaIgnoresPriorDayIntroductions 验证"今天引入了几张新卡"的
// 判定只看 review_events 里每张卡第一次评分的时间：一张昨天就开始学、今天还没
// 毕业的 Learning 卡不该占用今天的新卡配额。
func TestLearnSessionQuotaIgnoresPriorDayIntroductions(t *testing.T) {
	ctx := context.Background()
	handler, pool, svc := newTestEnv(t)
	user := seedUser(t, ctx, pool, svc)
	setNewCardsPerDay(t, handler, user, 1)

	now := time.Now().UTC()
	leftoverCardID := seedCardWithState(t, ctx, pool, user, fsrs.Learning, now.Add(-time.Minute), nil, nil)
	if _, err := pool.Exec(ctx, `
		INSERT INTO review_events (id, card_id, user_id, mode, rating, created_at)
		VALUES ($1, $2, $3, 'learn', 'again', $4)
	`, uuid.NewString(), leftoverCardID, user.ID, now.Add(-30*time.Hour)); err != nil {
		t.Fatalf("seed yesterday's review_event: %v", err)
	}

	freshCardID := seedCardWithState(t, ctx, pool, user, fsrs.New, now.Add(-time.Hour), nil, nil)

	session := fetchLearnSession(t, handler, user)
	ids := cardIDsOf(session)
	if !ids[leftoverCardID] {
		t.Errorf("learn session = %v, want it to include yesterday's unfinished card %s", session.Cards, leftoverCardID)
	}
	if !ids[freshCardID] {
		t.Errorf("learn session = %v, want it to still include today's 1 fresh card %s (leftover card must not eat the quota)", session.Cards, freshCardID)
	}
	if len(session.Cards) != 2 {
		t.Errorf("learn session has %d cards, want 2 (1 leftover + 1 fresh)", len(session.Cards))
	}
}
