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

// getReviewSession 现查 review_states，不再有"今天的队列快照"：Learn 拿
// state IN (New, Learning) 的候选，Review 拿 state IN (Review, Relearning) 的候选，
// 都要求 due_at <= now()。学习偏好（每日目标张数）不再在这里截断候选池，只是
// Home 页展示"今天还剩多少"用的软目标。
func (s *Server) getReviewSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := currentUserID(r)
	subjectID := r.URL.Query().Get("subject_id")
	setIDs := splitCSV(r.URL.Query().Get("set_ids"))
	sessionMode := normalizeSessionMode(r.URL.Query().Get("mode"))
	now := time.Now().UTC()

	ids, nextAvailableAt, err := queryReviewCandidateIDs(ctx, s.db, userID, subjectID, setIDs, sessionMode, now, sessionCandidateLimit)
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

// queryReviewCandidateIDs 按 subject/set 范围 + Learn/Review 对应的 state 分组，
// 取 due_at 已到期的卡，按 due_at 升序给一批（上限 limit）。如果一张都没到期，
// 顺便查一下"这个范围里最早还要多久到期"，给前端一个"稍后再来"的提示。
func queryReviewCandidateIDs(ctx context.Context, pool *pgxpool.Pool, userID string, subjectID string, setIDs []string, sessionMode string, now time.Time, limit int) ([]string, *time.Time, error) {
	stateFilter := "rs.state IN (0, 1)"
	if sessionMode == sessionModeReview {
		stateFilter = "rs.state IN (2, 3)"
	}

	args := []interface{}{userID}
	conditions := []string{
		"c.user_id = $1", "c.deleted_at IS NULL", "s.deleted_at IS NULL", "st.deleted_at IS NULL",
		"rs.mastered_at IS NULL", stateFilter,
	}
	argIndex := 2
	if subjectID != "" {
		conditions = append(conditions, fmt.Sprintf("c.subject_id = $%d", argIndex))
		args = append(args, subjectID)
		argIndex++
	}
	if len(setIDs) > 0 {
		placeholders := make([]string, 0, len(setIDs))
		for _, setID := range setIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, setID)
			argIndex++
		}
		conditions = append(conditions, fmt.Sprintf("c.set_id IN (%s)", strings.Join(placeholders, ",")))
	}
	whereClause := strings.Join(conditions, " AND ")

	if limit <= 0 {
		limit = sessionCandidateLimit
	}
	dueArgs := append(append([]interface{}{}, args...), now, limit)
	dueQuery := fmt.Sprintf(`
		SELECT c.id::text
		FROM cards c
		JOIN sets st ON st.id = c.set_id
		JOIN subjects s ON s.id = c.subject_id
		JOIN review_states rs ON rs.card_id = c.id
		WHERE %s AND rs.due_at <= $%d
		ORDER BY rs.due_at ASC, c.created_at ASC
		LIMIT $%d
	`, whereClause, argIndex, argIndex+1)

	rows, err := pool.Query(ctx, dueQuery, dueArgs...)
	if err != nil {
		return nil, nil, err
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, nil, err
	}
	rows.Close()

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
	if nextAvailableAt != nil && !nextAvailableAt.After(now) {
		nextAvailableAt = nil
	}
	return ids, nextAvailableAt, nil
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
