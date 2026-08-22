package api

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"memory-app/backend/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	learningModeNewPlusReview = "new_plus_review"
	learningModeFixedTotal    = "fixed_total"
	sessionModeReview         = "review"
	sessionModeLearn          = "learn"
	// Learn/Review 每次都是现查 review_states，不再有"今天的队列快照"，这里只是
	// 一个技术上限（避免一次拉回几千张卡），不是每日学习目标那个数字。
	sessionCandidateLimit = 200
)

type learningPreferencesResponse struct {
	LimitMode            string `json:"limit_mode"`
	NewCardsPerDay       int    `json:"new_cards_per_day"`
	TotalCardsPerDay     int    `json:"total_cards_per_day"`
	DailyReminderEnabled bool   `json:"daily_reminder_enabled"`
	DailyReminderTime    string `json:"daily_reminder_time"`
	DefaultReviewMode    string `json:"default_review_mode"`
	DefaultCardDirection string `json:"default_card_direction"`
}

type learningPreferencesRequest struct {
	LimitMode            string `json:"limit_mode"`
	NewCardsPerDay       int    `json:"new_cards_per_day"`
	TotalCardsPerDay     int    `json:"total_cards_per_day"`
	DailyReminderEnabled bool   `json:"daily_reminder_enabled"`
	DailyReminderTime    string `json:"daily_reminder_time"`
}

type reviewSessionResponse struct {
	Cards           []model.Card `json:"cards"`
	RemainingCount  int          `json:"remaining_count"`
	NextAvailableAt *time.Time   `json:"next_available_at,omitempty"`
}

func (s *Server) getLearningPreferences(w http.ResponseWriter, r *http.Request) {
	prefs, err := s.loadLearningPreferences(r.Context(), currentUserID(r))
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, prefs)
}

func (s *Server) updateLearningPreferences(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	current, err := s.loadLearningPreferences(r.Context(), userID)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}

	var req learningPreferencesRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, 400, "invalid json")
		return
	}
	prefs := normalizeLearningPreferences(learningPreferencesResponse{
		LimitMode:            firstNonEmpty(req.LimitMode, current.LimitMode),
		NewCardsPerDay:       firstPositive(req.NewCardsPerDay, current.NewCardsPerDay),
		TotalCardsPerDay:     firstPositive(req.TotalCardsPerDay, current.TotalCardsPerDay),
		DailyReminderEnabled: req.DailyReminderEnabled,
		DailyReminderTime:    firstNonEmpty(req.DailyReminderTime, current.DailyReminderTime),
		DefaultReviewMode:    "Review",
		DefaultCardDirection: "Chinese -> English",
	})

	_, err = s.db.Exec(r.Context(), `
		INSERT INTO learning_preferences (
			user_id, limit_mode, new_cards_per_day, total_cards_per_day,
			daily_reminder_enabled, daily_reminder_time
		) VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id) DO UPDATE
		SET limit_mode = EXCLUDED.limit_mode,
		    new_cards_per_day = EXCLUDED.new_cards_per_day,
		    total_cards_per_day = EXCLUDED.total_cards_per_day,
		    daily_reminder_enabled = EXCLUDED.daily_reminder_enabled,
		    daily_reminder_time = EXCLUDED.daily_reminder_time,
		    updated_at = now()
	`, userID, prefs.LimitMode, prefs.NewCardsPerDay, prefs.TotalCardsPerDay, prefs.DailyReminderEnabled, prefs.DailyReminderTime)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, prefs)
}

func (s *Server) loadLearningPreferences(ctx context.Context, userID string) (learningPreferencesResponse, error) {
	prefs := defaultLearningPreferences()
	err := s.db.QueryRow(ctx, `
		SELECT limit_mode, new_cards_per_day, total_cards_per_day,
		       daily_reminder_enabled, daily_reminder_time
		FROM learning_preferences
		WHERE user_id = $1
	`, userID).Scan(
		&prefs.LimitMode,
		&prefs.NewCardsPerDay,
		&prefs.TotalCardsPerDay,
		&prefs.DailyReminderEnabled,
		&prefs.DailyReminderTime,
	)
	if err == pgx.ErrNoRows {
		return prefs, nil
	}
	if err != nil {
		return learningPreferencesResponse{}, err
	}
	return normalizeLearningPreferences(prefs), nil
}

// getReviewSession 现查 review_states，不再有"今天的队列快照"：Review 拿
// state IN (Review, Relearning) 里 due_at 到期的候选。Learn 拿 state IN (New,
// Learning) 的候选，但 New 卡受 NewCardsPerDay 每日上限约束（按今天已经引入了
// 几张不同的卡来算，见 queryLearnCandidateIDs），已经在学的 Learning 卡则不再
// 卡 due_at，只要是今天这批里的就能立刻再出现——不用等 FSRS 给的短期间隔。
func (s *Server) getReviewSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := currentUserID(r)
	subjectID := r.URL.Query().Get("subject_id")
	setIDs := splitCSV(r.URL.Query().Get("set_ids"))
	sessionMode := normalizeSessionMode(r.URL.Query().Get("mode"))
	tzOffsetMinutes := timezoneOffsetMinutes(r.URL.Query().Get("tz_offset_minutes"))
	now := time.Now().UTC()

	var newCardsPerDay int
	if sessionMode == sessionModeLearn {
		prefs, err := s.loadLearningPreferences(ctx, userID)
		if err != nil {
			writeError(w, 500, err.Error())
			return
		}
		newCardsPerDay = prefs.NewCardsPerDay
	}
	dayStart, dayEnd := localDayRange(now, tzOffsetMinutes)

	ids, nextAvailableAt, err := queryReviewCandidateIDs(ctx, s.db, reviewCandidateQuery{
		UserID:         userID,
		SubjectID:      subjectID,
		SetIDs:         setIDs,
		SessionMode:    sessionMode,
		Now:            now,
		Limit:          sessionCandidateLimit,
		NewCardsPerDay: newCardsPerDay,
		DayStart:       dayStart,
		DayEnd:         dayEnd,
	})
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	cards, err := loadCardsByIDs(ctx, s.db, userID, ids)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, reviewSessionResponse{
		Cards:           cards,
		RemainingCount:  len(cards),
		NextAvailableAt: nextAvailableAt,
	})
}

type reviewCandidateQuery struct {
	UserID         string
	SubjectID      string
	SetIDs         []string
	SessionMode    string
	Now            time.Time
	Limit          int
	NewCardsPerDay int       // 只有 SessionMode == sessionModeLearn 时才会用到
	DayStart       time.Time // 同上，用户本地"今天"的区间，用来算今天引入了几张新卡
	DayEnd         time.Time
}

// queryReviewCandidateIDs 按 subject/set 范围 + Learn/Review 对应的 state 分组取
// 候选卡。Review 模式沿用老逻辑：只要 due_at 到期就按 due_at 升序给一批。Learn
// 模式交给 queryLearnCandidateIDs，因为它要额外考虑每日新卡上限和"今天引入的
// 卡不等 due_at"。如果一张都没到期，顺便查一下这个范围里最早还要多久到期，给
// 前端一个"稍后再来"的提示。
func queryReviewCandidateIDs(ctx context.Context, pool *pgxpool.Pool, q reviewCandidateQuery) ([]string, *time.Time, error) {
	stateFilter := "rs.state IN (0, 1)"
	if q.SessionMode == sessionModeReview {
		stateFilter = "rs.state IN (2, 3)"
	}

	args := []interface{}{q.UserID}
	conditions := []string{
		"c.user_id = $1", "c.deleted_at IS NULL", "s.deleted_at IS NULL", "st.deleted_at IS NULL",
		"rs.mastered_at IS NULL", stateFilter,
	}
	argIndex := 2
	if q.SubjectID != "" {
		conditions = append(conditions, fmt.Sprintf("c.subject_id = $%d", argIndex))
		args = append(args, q.SubjectID)
		argIndex++
	}
	if len(q.SetIDs) > 0 {
		placeholders := make([]string, 0, len(q.SetIDs))
		for _, setID := range q.SetIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, setID)
			argIndex++
		}
		conditions = append(conditions, fmt.Sprintf("c.set_id IN (%s)", strings.Join(placeholders, ",")))
	}
	whereClause := strings.Join(conditions, " AND ")

	limit := q.Limit
	if limit <= 0 {
		limit = sessionCandidateLimit
	}

	var ids []string
	var err error
	if q.SessionMode == sessionModeLearn {
		ids, err = queryLearnCandidateIDs(ctx, pool, whereClause, args, argIndex, q, limit)
	} else {
		ids, err = queryDueCandidateIDs(ctx, pool, whereClause, args, argIndex, q.Now, limit)
	}
	if err != nil {
		return nil, nil, err
	}

	if len(ids) > 0 {
		return ids, nil, nil
	}

	var nextAvailableAt *time.Time
	nextQuery := fmt.Sprintf(`
		SELECT MIN(rs.due_at)
		FROM cards c
		JOIN sets st ON st.id = c.set_id
		JOIN subjects s ON s.id = c.subject_id
		JOIN review_states rs ON rs.card_id = c.id
		WHERE %s
	`, whereClause)
	if err := pool.QueryRow(ctx, nextQuery, args...).Scan(&nextAvailableAt); err != nil && err != pgx.ErrNoRows {
		return nil, nil, err
	}
	if nextAvailableAt != nil && !nextAvailableAt.After(q.Now) {
		nextAvailableAt = nil
	}
	return ids, nextAvailableAt, nil
}

// queryDueCandidateIDs 是 Review 模式（以及历史上 Learn 模式）用的老查询：单纯
// 按 due_at 到期与否给一批，按 due_at、created_at 升序排。
func queryDueCandidateIDs(ctx context.Context, pool *pgxpool.Pool, whereClause string, baseArgs []interface{}, argIndex int, now time.Time, limit int) ([]string, error) {
	args := append(append([]interface{}{}, baseArgs...), now, limit)
	query := fmt.Sprintf(`
		SELECT c.id::text
		FROM cards c
		JOIN sets st ON st.id = c.set_id
		JOIN subjects s ON s.id = c.subject_id
		JOIN review_states rs ON rs.card_id = c.id
		WHERE %s AND rs.due_at <= $%d
		ORDER BY rs.due_at ASC, c.created_at ASC
		LIMIT $%d
	`, whereClause, argIndex, argIndex+1)
	return scanCardIDs(ctx, pool, query, args)
}

// queryLearnCandidateIDs 把 Learn 候选拆成两块合并：
//   - in_progress：state=1（已经在学）的卡，只要 due_at 到期，或者它是今天已经
//     引入的那一批，就算数——这一步让 Again/Hard 之后不用等 FSRS 给的短期
//     due_at，立刻能在同一次学习里再出现。
//   - fresh：state=0（从没学过）的卡，只按今天还剩几个名额来限流：
//     LIMIT max(0, NewCardsPerDay - 今天已引入数 - 往日欠账数)。不管前面的卡
//     反复 Again 多少次，这个 LIMIT 只看"今天开始学的不同卡片数"，不会因为某
//     张卡毕业腾出名额就多塞一张新卡进来。
//
// 每日名额**先给往日欠账卡**（今天之前就开始学、现在又到期的 state=1），剩下的
// 才用来放全新卡。这样一次 Learn 的总数就落在 NewCardsPerDay 上：欠账 2 张 +
// 全新 18 张 = 20，而不是 20 张新卡之外再额外加 2 张欠账。
//
// 边界：欠账数本身超过 NewCardsPerDay 时不截断——已经开始学的卡不该被挡住，
// 此时总数会大于上限，随着这些卡毕业自然回落。
//
// "今天引入"完全靠 review_events 派生（loadCardsIntroducedToday），不落地任何
// 会话状态，所以哪怕 App 被杀掉重开、服务重启，也能照样正确重建。
func queryLearnCandidateIDs(ctx context.Context, pool *pgxpool.Pool, whereClause string, baseArgs []interface{}, argIndex int, q reviewCandidateQuery, limit int) ([]string, error) {
	introducedTodayIDs, err := loadCardsIntroducedToday(ctx, pool, q.UserID, q.DayStart, q.DayEnd)
	if err != nil {
		return nil, err
	}
	carryoverCount, err := countLearnCarryover(ctx, pool, whereClause, baseArgs, argIndex, q.Now, introducedTodayIDs)
	if err != nil {
		return nil, err
	}
	remainingNewSlots := q.NewCardsPerDay - len(introducedTodayIDs) - carryoverCount
	if remainingNewSlots < 0 {
		remainingNewSlots = 0
	}

	args := append([]interface{}{}, baseArgs...)

	nowIndex := argIndex
	args = append(args, q.Now)
	argIndex++

	inProgressCondition := fmt.Sprintf("rs.due_at <= $%d", nowIndex)
	if len(introducedTodayIDs) > 0 {
		placeholders := make([]string, 0, len(introducedTodayIDs))
		for _, id := range introducedTodayIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, id)
			argIndex++
		}
		inProgressCondition = fmt.Sprintf("(%s OR c.id IN (%s))", inProgressCondition, strings.Join(placeholders, ","))
	}

	freshNowIndex := argIndex
	args = append(args, q.Now)
	argIndex++

	freshLimitIndex := argIndex
	args = append(args, remainingNewSlots)
	argIndex++

	overallLimitIndex := argIndex
	args = append(args, limit)
	argIndex++

	query := fmt.Sprintf(`
		WITH in_progress AS (
			SELECT c.id::text AS card_id, rs.due_at AS due_at, c.created_at AS created_at
			FROM cards c
			JOIN sets st ON st.id = c.set_id
			JOIN subjects s ON s.id = c.subject_id
			JOIN review_states rs ON rs.card_id = c.id
			WHERE %s AND rs.state = 1 AND %s
		),
		fresh AS (
			SELECT c.id::text AS card_id, rs.due_at AS due_at, c.created_at AS created_at
			FROM cards c
			JOIN sets st ON st.id = c.set_id
			JOIN subjects s ON s.id = c.subject_id
			JOIN review_states rs ON rs.card_id = c.id
			WHERE %s AND rs.state = 0 AND rs.due_at <= $%d
			ORDER BY c.created_at ASC
			LIMIT $%d
		),
		combined AS (
			SELECT card_id, due_at, created_at FROM in_progress
			UNION ALL
			SELECT card_id, due_at, created_at FROM fresh
		)
		SELECT card_id FROM combined
		ORDER BY due_at ASC, created_at ASC
		LIMIT $%d
	`, whereClause, inProgressCondition, whereClause, freshNowIndex, freshLimitIndex, overallLimitIndex)

	return scanCardIDs(ctx, pool, query, args)
}

// countLearnCarryover 数"往日欠账"：今天之前就开始学、至今还是 state=1、现在
// 又到期的卡。它们不是新卡，但会占用今天的学习名额，让一次 Learn 的总数收敛到
// NewCardsPerDay（见 queryLearnCandidateIDs 的说明）。
//
// 排除今天引入的卡，是因为那批已经通过 len(introducedTodayIDs) 计过一次名额了，
// 两边都算会重复扣。
func countLearnCarryover(ctx context.Context, pool *pgxpool.Pool, whereClause string, baseArgs []interface{}, argIndex int, now time.Time, introducedTodayIDs []string) (int, error) {
	args := append([]interface{}{}, baseArgs...)

	args = append(args, now)
	condition := fmt.Sprintf("rs.state = 1 AND rs.due_at <= $%d", argIndex)
	argIndex++

	if len(introducedTodayIDs) > 0 {
		placeholders := make([]string, 0, len(introducedTodayIDs))
		for _, id := range introducedTodayIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, id)
			argIndex++
		}
		condition = fmt.Sprintf("%s AND c.id NOT IN (%s)", condition, strings.Join(placeholders, ","))
	}

	query := fmt.Sprintf(`
		SELECT count(*)
		FROM cards c
		JOIN sets st ON st.id = c.set_id
		JOIN subjects s ON s.id = c.subject_id
		JOIN review_states rs ON rs.card_id = c.id
		WHERE %s AND %s
	`, whereClause, condition)

	var count int
	if err := pool.QueryRow(ctx, query, args...).Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

// loadCardsIntroducedToday 返回今天(用户本地 [dayStart, dayEnd))第一次出现在
// review_events 里的 card_id。scheduler.Apply 对一张 state=0 的卡评第一次分就
// 必然让它离开 New 状态（Again/Hard/Good 变 Learning，Easy 直接变 Review），所以
// "这张卡在 review_events 里第一次出现的时间"精确等于"今天被引入学习"的时间，
// 不需要额外记一个 first_seen_at 字段。
func loadCardsIntroducedToday(ctx context.Context, pool *pgxpool.Pool, userID string, dayStart, dayEnd time.Time) ([]string, error) {
	return scanCardIDs(ctx, pool, `
		SELECT card_id::text
		FROM review_events
		WHERE user_id = $1
		GROUP BY card_id
		HAVING MIN(created_at) >= $2 AND MIN(created_at) < $3
	`, []interface{}{userID, dayStart, dayEnd})
}

func scanCardIDs(ctx context.Context, pool *pgxpool.Pool, query string, args []interface{}) ([]string, error) {
	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func loadCardsByIDs(ctx context.Context, pool *pgxpool.Pool, userID string, cardIDs []string) ([]model.Card, error) {
	if len(cardIDs) == 0 {
		return []model.Card{}, nil
	}
	cards, err := loadCards(ctx, pool, cardFilters{UserID: userID, CardIDs: cardIDs, Limit: len(cardIDs)})
	if err != nil {
		return nil, err
	}
	byID := make(map[string]model.Card, len(cards))
	for _, card := range cards {
		byID[card.ID] = card
	}
	ordered := make([]model.Card, 0, len(cards))
	for _, id := range cardIDs {
		if card, ok := byID[id]; ok {
			ordered = append(ordered, card)
		}
	}
	return ordered, nil
}

func defaultLearningPreferences() learningPreferencesResponse {
	return learningPreferencesResponse{
		LimitMode:            learningModeNewPlusReview,
		NewCardsPerDay:       20,
		TotalCardsPerDay:     30,
		DailyReminderTime:    "20:00",
		DefaultReviewMode:    "Review",
		DefaultCardDirection: "Chinese -> English",
	}
}

func normalizeLearningPreferences(prefs learningPreferencesResponse) learningPreferencesResponse {
	if prefs.LimitMode != learningModeFixedTotal {
		prefs.LimitMode = learningModeNewPlusReview
	}
	prefs.NewCardsPerDay = clampInt(prefs.NewCardsPerDay, 0, 100)
	prefs.TotalCardsPerDay = clampInt(prefs.TotalCardsPerDay, 1, 300)
	if prefs.DailyReminderTime == "" || !validClockTime(prefs.DailyReminderTime) {
		prefs.DailyReminderTime = "20:00"
	}
	prefs.DefaultReviewMode = "Review"
	prefs.DefaultCardDirection = "Chinese -> English"
	return prefs
}

// computeRemainingToday 算"今天还剩多少张新卡/复习"，公式跟迁移前 iOS
// HomeView.swift 里 todayNewCardCount/todayReviewCount 完全一致，这次搬到
// 后端做单一数据源：new_plus_review 模式下复习不设上限，新卡按 NewCardsPerDay
// 减去今天已毕业的数量；fixed_total 模式下新卡和复习共享每日总量上限。
func computeRemainingToday(prefs learningPreferencesResponse, newCount int, reviewDueCount int, newLearnedToday int) (newRemaining int, reviewRemaining int) {
	if prefs.LimitMode == learningModeFixedTotal {
		reviewRemaining = min(reviewDueCount, prefs.TotalCardsPerDay)
		newRemaining = min(newCount, max(0, prefs.TotalCardsPerDay-reviewRemaining-newLearnedToday))
		return newRemaining, reviewRemaining
	}
	reviewRemaining = reviewDueCount
	newRemaining = min(newCount, max(0, prefs.NewCardsPerDay-newLearnedToday))
	return newRemaining, reviewRemaining
}

func normalizeSessionMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case sessionModeLearn:
		return sessionModeLearn
	default:
		return sessionModeReview
	}
}

// localDayRange 把 now 换算到用户本地时区，返回"今天"这一天在 UTC 下的
// [开始, 结束) 区间，用来判断 graduated_at 这类时间戳是不是落在用户的今天。
func localDayRange(now time.Time, offsetMinutes int) (time.Time, time.Time) {
	zone := time.FixedZone("user", offsetMinutes*60)
	local := now.In(zone)
	start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone)
	return start, start.Add(24 * time.Hour)
}

func timezoneOffsetMinutes(raw string) int {
	if raw == "" {
		return 8 * 60
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < -12*60 || value > 14*60 {
		return 8 * 60
	}
	return value
}

func firstNonEmpty(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}

func firstPositive(value int, fallback int) int {
	if value <= 0 {
		return fallback
	}
	return value
}

func validClockTime(value string) bool {
	_, err := time.Parse("15:04", value)
	return err == nil
}

func clampInt(value int, minValue int, maxValue int) int {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}
