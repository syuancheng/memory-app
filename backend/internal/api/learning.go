package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"memory-app/backend/internal/model"
	"memory-app/backend/internal/scheduler"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	learningModeNewPlusReview = "new_plus_review"
	learningModeFixedTotal    = "fixed_total"
	sessionModeReview         = "review"
	sessionModeLearn          = "learn"
	maxDailyRetries           = 3
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
	ID                 string       `json:"id"`
	Date               string       `json:"date"`
	InitialTotalCount  int          `json:"initial_total_count"`
	RemainingCount     int          `json:"remaining_count"`
	CompletedCount     int          `json:"completed_count"`
	LeechedCount       int          `json:"leeched_count"`
	IsCheckInCompleted bool         `json:"is_check_in_completed"`
	Cards              []model.Card `json:"cards"`
	NextAvailableAt    *time.Time   `json:"next_available_at,omitempty"`
}

type dailySessionRecord struct {
	ID                 string
	UserID             string
	Date               string
	InitialTotalCount  int
	ActiveQueueCardIDs []string
	CompletedCardIDs   []string
	LeechedCardIDs     []string
	CardRetryCounts    map[string]int
	IsCheckInCompleted bool
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

func (s *Server) getReviewSession(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := currentUserID(r)
	subjectID := r.URL.Query().Get("subject_id")
	setIDs := splitCSV(r.URL.Query().Get("set_ids"))
	sessionMode := normalizeSessionMode(r.URL.Query().Get("mode"))
	now := time.Now().UTC()
	sessionDate := localDateString(now, timezoneOffsetMinutes(r.URL.Query().Get("tz_offset_minutes")))
	scopeKey := buildSessionScopeKey(sessionMode, subjectID, setIDs)

	prefs, err := s.loadLearningPreferences(ctx, userID)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}

	tx, err := s.db.Begin(ctx)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	defer tx.Rollback(ctx)

	session, err := s.loadOrCreateDailySession(ctx, tx, userID, sessionDate, sessionMode, scopeKey, subjectID, setIDs, prefs, now)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	if err := tx.Commit(ctx); err != nil {
		writeError(w, 500, err.Error())
		return
	}

	response, err := s.buildReviewSessionResponse(ctx, session, userID, now)
	if err != nil {
		writeError(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, response)
}

func (s *Server) loadOrCreateDailySession(
	ctx context.Context,
	tx pgx.Tx,
	userID string,
	sessionDate string,
	sessionMode string,
	scopeKey string,
	subjectID string,
	setIDs []string,
	prefs learningPreferencesResponse,
	now time.Time,
) (dailySessionRecord, error) {
	session, err := loadDailySessionByScope(ctx, tx, userID, sessionDate, scopeKey)
	if err == nil {
		return session, nil
	}
	if err != pgx.ErrNoRows {
		return dailySessionRecord{}, err
	}

	reviewIDs, err := querySessionCandidateIDs(ctx, tx, userID, subjectID, setIDs, true, 1000)
	if err != nil {
		return dailySessionRecord{}, err
	}
	newCandidateLimit := prefs.NewCardsPerDay
	if prefs.LimitMode == learningModeFixedTotal {
		newCandidateLimit = prefs.TotalCardsPerDay
	}
	if sessionMode == sessionModeLearn && prefs.LimitMode == learningModeFixedTotal {
		newCandidateLimit = maxInt(0, prefs.TotalCardsPerDay-minInt(len(reviewIDs), prefs.TotalCardsPerDay))
	}
	newIDs, err := querySessionCandidateIDs(ctx, tx, userID, subjectID, setIDs, false, newCandidateLimit)
	if err != nil {
		return dailySessionRecord{}, err
	}

	queue := buildDailyQueue(reviewIDs, newIDs, prefs, sessionMode)
	setIDsJSON, _ := json.Marshal(sortedStrings(setIDs))
	queueJSON, _ := json.Marshal(queue)
	emptyArrayJSON := []byte("[]")
	retryJSON := []byte("{}")

	sessionID := uuid.NewString()
	_, err = tx.Exec(ctx, `
		INSERT INTO daily_sessions (
			id, user_id, session_date, session_mode, scope_key, subject_id, set_ids, initial_total_count,
			active_queue_card_ids, completed_card_ids, leeched_card_ids, card_retry_counts,
			is_check_in_completed
		) VALUES ($1, $2, $3::date, $4, $5, NULLIF($6, '')::uuid, $7::jsonb, $8,
		          $9::jsonb, $10::jsonb, $11::jsonb, $12::jsonb, $13)
	`, sessionID, userID, sessionDate, sessionMode, scopeKey, subjectID, string(setIDsJSON), len(queue), string(queueJSON), string(emptyArrayJSON), string(emptyArrayJSON), string(retryJSON), len(queue) == 0)
	if err != nil {
		return dailySessionRecord{}, err
	}
	return dailySessionRecord{
		ID:                 sessionID,
		UserID:             userID,
		Date:               sessionDate,
		InitialTotalCount:  len(queue),
		ActiveQueueCardIDs: queue,
		CompletedCardIDs:   []string{},
		LeechedCardIDs:     []string{},
		CardRetryCounts:    map[string]int{},
		IsCheckInCompleted: len(queue) == 0,
	}, nil
}

func loadDailySessionByScope(ctx context.Context, tx pgx.Tx, userID string, sessionDate string, scopeKey string) (dailySessionRecord, error) {
	var session dailySessionRecord
	var activeBytes, completedBytes, leechedBytes, retryBytes []byte
	err := tx.QueryRow(ctx, `
		SELECT id::text, user_id::text, session_date::text, initial_total_count,
		       active_queue_card_ids, completed_card_ids, leeched_card_ids,
		       card_retry_counts, is_check_in_completed
		FROM daily_sessions
		WHERE user_id = $1 AND session_date = $2::date AND scope_key = $3
		FOR UPDATE
	`, userID, sessionDate, scopeKey).Scan(
		&session.ID,
		&session.UserID,
		&session.Date,
		&session.InitialTotalCount,
		&activeBytes,
		&completedBytes,
		&leechedBytes,
		&retryBytes,
		&session.IsCheckInCompleted,
	)
	if err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(activeBytes, &session.ActiveQueueCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(completedBytes, &session.CompletedCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(leechedBytes, &session.LeechedCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(retryBytes, &session.CardRetryCounts); err != nil {
		return dailySessionRecord{}, err
	}
	return session, nil
}

func querySessionCandidateIDs(ctx context.Context, tx pgx.Tx, userID string, subjectID string, setIDs []string, dueReview bool, limit int) ([]string, error) {
	args := []interface{}{userID}
	conditions := []string{"c.user_id = $1", "c.deleted_at IS NULL", "s.deleted_at IS NULL", "st.deleted_at IS NULL"}
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
	if dueReview {
		conditions = append(conditions, "rs.status IN ('learning', 'review')", "rs.due_at <= now()")
	} else {
		conditions = append(conditions, "rs.status = 'new'")
	}
	if limit <= 0 {
		limit = 100
	}
	args = append(args, limit)
	limitPlaceholder := fmt.Sprintf("$%d", argIndex)

	query := fmt.Sprintf(`
		SELECT c.id::text
		FROM cards c
		JOIN sets st ON st.id = c.set_id
		JOIN subjects s ON s.id = c.subject_id
		JOIN review_states rs ON rs.card_id = c.id
		WHERE %s
		ORDER BY rs.due_at ASC, c.created_at ASC
		LIMIT %s
	`, strings.Join(conditions, " AND "), limitPlaceholder)

	rows, err := tx.Query(ctx, query, args...)
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

func (s *Server) buildReviewSessionResponse(ctx context.Context, session dailySessionRecord, userID string, now time.Time) (reviewSessionResponse, error) {
	unfinishedIDs := activeUnfinishedIDs(session)
	availableIDs, nextAvailableAt, err := s.availableSessionCardIDs(ctx, userID, unfinishedIDs, now)
	if err != nil {
		return reviewSessionResponse{}, err
	}
	cards, err := loadCardsByIDs(ctx, s.db, userID, availableIDs)
	if err != nil {
		return reviewSessionResponse{}, err
	}

	return reviewSessionResponse{
		ID:                 session.ID,
		Date:               session.Date,
		InitialTotalCount:  session.InitialTotalCount,
		RemainingCount:     maxInt(0, session.InitialTotalCount-len(session.CompletedCardIDs)-len(session.LeechedCardIDs)),
		CompletedCount:     len(session.CompletedCardIDs),
		LeechedCount:       len(session.LeechedCardIDs),
		IsCheckInCompleted: session.IsCheckInCompleted,
		Cards:              cards,
		NextAvailableAt:    nextAvailableAt,
	}, nil
}

func (s *Server) availableSessionCardIDs(ctx context.Context, userID string, cardIDs []string, now time.Time) ([]string, *time.Time, error) {
	if len(cardIDs) == 0 {
		return []string{}, nil, nil
	}
	args := []interface{}{userID}
	placeholders := make([]string, 0, len(cardIDs))
	for index, id := range cardIDs {
		placeholders = append(placeholders, fmt.Sprintf("$%d", index+2))
		args = append(args, id)
	}
	rows, err := s.db.Query(ctx, fmt.Sprintf(`
		SELECT rs.card_id::text, rs.due_at
		FROM review_states rs
		JOIN cards c ON c.id = rs.card_id
		WHERE c.user_id = $1
		  AND c.deleted_at IS NULL
		  AND rs.status NOT IN ('deleted', 'mastered')
		  AND rs.card_id IN (%s)
	`, strings.Join(placeholders, ",")), args...)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	dueByID := map[string]time.Time{}
	var nextAvailableAt *time.Time
	for rows.Next() {
		var id string
		var dueAt time.Time
		if err := rows.Scan(&id, &dueAt); err != nil {
			return nil, nil, err
		}
		dueByID[id] = dueAt
		if dueAt.After(now) && (nextAvailableAt == nil || dueAt.Before(*nextAvailableAt)) {
			value := dueAt
			nextAvailableAt = &value
		}
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}

	available := []string{}
	for _, id := range cardIDs {
		if dueAt, ok := dueByID[id]; ok && !dueAt.After(now) {
			available = append(available, id)
		}
	}
	return available, nextAvailableAt, nil
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

func updateDailySessionProgress(ctx context.Context, tx pgx.Tx, userID string, sessionID string, cardID string, rating string, previous model.ReviewState, next model.ReviewState) error {
	if sessionID == "" {
		return nil
	}
	session, err := loadDailySessionByID(ctx, tx, userID, sessionID)
	if err != nil {
		return err
	}
	if !containsString(session.ActiveQueueCardIDs, cardID) &&
		!containsString(session.CompletedCardIDs, cardID) &&
		!containsString(session.LeechedCardIDs, cardID) {
		return fmt.Errorf("card is not in today's session")
	}

	switch rating {
	case scheduler.GradeAgain:
		session.CardRetryCounts[cardID] = session.CardRetryCounts[cardID] + 1
		if session.CardRetryCounts[cardID] >= maxDailyRetries {
			session.ActiveQueueCardIDs = removeString(session.ActiveQueueCardIDs, cardID)
			session.LeechedCardIDs = appendUnique(session.LeechedCardIDs, cardID)
		} else {
			session.ActiveQueueCardIDs = moveStringToBack(session.ActiveQueueCardIDs, cardID)
		}
	case scheduler.GradeHard:
		if previous.Status == "review" {
			session.ActiveQueueCardIDs = removeString(session.ActiveQueueCardIDs, cardID)
			session.CompletedCardIDs = appendUnique(session.CompletedCardIDs, cardID)
		} else {
			session.ActiveQueueCardIDs = moveStringToBack(session.ActiveQueueCardIDs, cardID)
		}
	case scheduler.GradeGood:
		if next.Status == "review" {
			session.ActiveQueueCardIDs = removeString(session.ActiveQueueCardIDs, cardID)
			session.CompletedCardIDs = appendUnique(session.CompletedCardIDs, cardID)
		} else {
			session.ActiveQueueCardIDs = moveStringToBack(session.ActiveQueueCardIDs, cardID)
		}
	case scheduler.GradeEasy:
		session.ActiveQueueCardIDs = removeString(session.ActiveQueueCardIDs, cardID)
		session.CompletedCardIDs = appendUnique(session.CompletedCardIDs, cardID)
	}

	session.IsCheckInCompleted = len(session.ActiveQueueCardIDs) == 0 &&
		len(session.CompletedCardIDs)+len(session.LeechedCardIDs) >= session.InitialTotalCount
	return saveDailySessionProgress(ctx, tx, session)
}

func loadDailySessionByID(ctx context.Context, tx pgx.Tx, userID string, sessionID string) (dailySessionRecord, error) {
	var session dailySessionRecord
	var activeBytes, completedBytes, leechedBytes, retryBytes []byte
	err := tx.QueryRow(ctx, `
		SELECT id::text, user_id::text, session_date::text, initial_total_count,
		       active_queue_card_ids, completed_card_ids, leeched_card_ids,
		       card_retry_counts, is_check_in_completed
		FROM daily_sessions
		WHERE id = $1 AND user_id = $2
		FOR UPDATE
	`, sessionID, userID).Scan(
		&session.ID,
		&session.UserID,
		&session.Date,
		&session.InitialTotalCount,
		&activeBytes,
		&completedBytes,
		&leechedBytes,
		&retryBytes,
		&session.IsCheckInCompleted,
	)
	if err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(activeBytes, &session.ActiveQueueCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(completedBytes, &session.CompletedCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(leechedBytes, &session.LeechedCardIDs); err != nil {
		return dailySessionRecord{}, err
	}
	if err := decodeJSON(retryBytes, &session.CardRetryCounts); err != nil {
		return dailySessionRecord{}, err
	}
	return session, nil
}

func saveDailySessionProgress(ctx context.Context, tx pgx.Tx, session dailySessionRecord) error {
	activeJSON, _ := json.Marshal(session.ActiveQueueCardIDs)
	completedJSON, _ := json.Marshal(session.CompletedCardIDs)
	leechedJSON, _ := json.Marshal(session.LeechedCardIDs)
	retryJSON, _ := json.Marshal(session.CardRetryCounts)
	_, err := tx.Exec(ctx, `
		UPDATE daily_sessions
		SET active_queue_card_ids = $3::jsonb,
		    completed_card_ids = $4::jsonb,
		    leeched_card_ids = $5::jsonb,
		    card_retry_counts = $6::jsonb,
		    is_check_in_completed = $7,
		    updated_at = now()
		WHERE id = $1 AND user_id = $2
	`, session.ID, session.UserID, string(activeJSON), string(completedJSON), string(leechedJSON), string(retryJSON), session.IsCheckInCompleted)
	return err
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

func buildDailyQueue(reviewIDs []string, newIDs []string, prefs learningPreferencesResponse, sessionMode string) []string {
	queue := []string{}
	if sessionMode == sessionModeLearn {
		limit := prefs.NewCardsPerDay
		if prefs.LimitMode == learningModeFixedTotal {
			limit = len(newIDs)
		}
		return append(queue, newIDs[:minInt(len(newIDs), limit)]...)
	}
	if sessionMode == sessionModeReview {
		limit := len(reviewIDs)
		if prefs.LimitMode == learningModeFixedTotal {
			limit = minInt(len(reviewIDs), prefs.TotalCardsPerDay)
		}
		return append(queue, reviewIDs[:limit]...)
	}
	if prefs.LimitMode == learningModeFixedTotal {
		reviewLimit := minInt(len(reviewIDs), prefs.TotalCardsPerDay)
		queue = append(queue, reviewIDs[:reviewLimit]...)
		newLimit := minInt(len(newIDs), maxInt(0, prefs.TotalCardsPerDay-reviewLimit))
		queue = append(queue, newIDs[:newLimit]...)
		return queue
	}
	queue = append(queue, reviewIDs...)
	newLimit := minInt(len(newIDs), prefs.NewCardsPerDay)
	queue = append(queue, newIDs[:newLimit]...)
	return queue
}

func activeUnfinishedIDs(session dailySessionRecord) []string {
	completed := stringSet(session.CompletedCardIDs)
	leeched := stringSet(session.LeechedCardIDs)
	ids := make([]string, 0, len(session.ActiveQueueCardIDs))
	for _, id := range session.ActiveQueueCardIDs {
		if !completed[id] && !leeched[id] {
			ids = append(ids, id)
		}
	}
	return ids
}

func buildSessionScopeKey(sessionMode string, subjectID string, setIDs []string) string {
	parts := []string{"mode:" + normalizeSessionMode(sessionMode), "subject:" + strings.TrimSpace(subjectID)}
	for _, id := range sortedStrings(setIDs) {
		parts = append(parts, "set:"+id)
	}
	return strings.Join(parts, "|")
}

func normalizeSessionMode(mode string) string {
	switch strings.TrimSpace(mode) {
	case sessionModeLearn:
		return sessionModeLearn
	default:
		return sessionModeReview
	}
}

func localDateString(now time.Time, offsetMinutes int) string {
	return now.In(time.FixedZone("user", offsetMinutes*60)).Format("2006-01-02")
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

func sortedStrings(values []string) []string {
	result := append([]string{}, values...)
	sort.Strings(result)
	return result
}

func decodeJSON(data []byte, target interface{}) error {
	if len(data) == 0 {
		data = []byte("null")
	}
	if err := json.Unmarshal(data, target); err != nil {
		return err
	}
	switch value := target.(type) {
	case *[]string:
		if *value == nil {
			*value = []string{}
		}
	case *map[string]int:
		if *value == nil {
			*value = map[string]int{}
		}
	}
	return nil
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func appendUnique(values []string, value string) []string {
	if containsString(values, value) {
		return values
	}
	return append(values, value)
}

func removeString(values []string, target string) []string {
	result := values[:0]
	for _, value := range values {
		if value != target {
			result = append(result, value)
		}
	}
	return result
}

func moveStringToBack(values []string, target string) []string {
	values = removeString(values, target)
	return append(values, target)
}

func stringSet(values []string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
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

func minInt(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}
