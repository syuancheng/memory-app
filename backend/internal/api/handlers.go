package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"memory-app/backend/internal/model"
	"memory-app/backend/internal/scheduler"
	"memory-app/backend/internal/service"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/open-spaced-repetition/go-fsrs/v3"
)

type nameRequest struct {
	Name string `json:"name"`
}

type cardRequest struct {
	SetID          string                `json:"set_id"`
	CardType       string                `json:"card_type"`
	Direction      string                `json:"direction"`
	FrontText      string                `json:"front_text"`
	AnswerText     string                `json:"answer_text"`
	GrammarPhrases []model.GrammarPhrase `json:"grammar_phrases"`
}

type reviewResultRequest struct {
	CardID              string `json:"card_id"`
	ClientReviewID      string `json:"client_review_id"`
	Mode                string `json:"mode"`
	Rating              string `json:"rating"`
	RevealedTokensCount int    `json:"revealed_tokens_count"`
	TotalTokensCount    int    `json:"total_tokens_count"`
}

type reviewPreviewResponse struct {
	Grade           string    `json:"grade"`
	IntervalSeconds int       `json:"interval_seconds"`
	DueAt           time.Time `json:"due_at"`
}

type meSummaryResponse struct {
	User                 meUserResponse        `json:"user"`
	TotalCards           int                   `json:"total_cards"`
	DueCount             int                   `json:"due_count"`
	NewCount             int                   `json:"new_count"`
	ReviewDueCount       int                   `json:"review_due_count"`
	NewLearnedToday      int                   `json:"new_learned_today"`
	NewRemainingToday    int                   `json:"new_remaining_today"`
	ReviewRemainingToday int                   `json:"review_remaining_today"`
	CheckedInToday       bool                  `json:"checked_in_today"`
	MasteredCount        int                   `json:"mastered_count"`
	ReviewedToday        int                   `json:"reviewed_today"`
	TotalReviewed        int                   `json:"total_reviewed"`
	CurrentStreak        int                   `json:"current_streak"`
	RecentActivity       []activityDayResponse `json:"recent_activity"`
}

type meUserResponse struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Provider string `json:"provider,omitempty"`
}

type activityDayResponse struct {
	Date  string `json:"date"`
	Count int    `json:"count"`
}

func (s *Server) getMeSummary(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	tzOffsetMinutes := timezoneOffsetMinutes(r.URL.Query().Get("tz_offset_minutes"))
	summary, err := s.loadMeSummary(r.Context(), userID, tzOffsetMinutes)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

// checkIn 记录"今天打卡"。服务端用跟 /me/summary 完全一样的口径重新核实今天的
// 新学/复习目标是否都已经完成——不信任客户端传来的状态，避免设备时钟/时区偏差
// 或者绕过 UI 直接调接口就能打卡。同一个本地日重复打卡是幂等的。
func (s *Server) checkIn(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID := currentUserID(r)
	tzOffsetMinutes := timezoneOffsetMinutes(r.URL.Query().Get("tz_offset_minutes"))

	summary, err := s.loadMeSummary(ctx, userID, tzOffsetMinutes)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if summary.NewRemainingToday > 0 || summary.ReviewRemainingToday > 0 {
		writeError(w, http.StatusBadRequest, "today's learning is not finished yet")
		return
	}

	dayStart, _ := localDayRange(time.Now().UTC(), tzOffsetMinutes)
	_, err = s.db.Exec(ctx, `
		INSERT INTO daily_check_ins (id, user_id, check_in_date)
		VALUES ($1, $2, $3)
		ON CONFLICT (user_id, check_in_date) DO NOTHING
	`, uuid.NewString(), userID, dayStart.Format("2006-01-02"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// 打卡前后只有「打卡了没」「streak」两个字段会变——其余字段（今天的计数、
	// 活动热力图）两次查询之间不可能变化，不用把整份 loadMeSummary 再跑一遍。
	summary.CheckedInToday = true
	summary.CurrentStreak, err = s.currentCheckInStreak(ctx, userID, dayStart)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

// loadMeSummary 是 /me/summary 和 /check-in 共用的一份查询逻辑，两个接口都需要
// 「今天新学/复习各还剩多少」「今天打卡了没」「连续打卡天数」这一整套数据。
func (s *Server) loadMeSummary(ctx context.Context, userID string, tzOffsetMinutes int) (meSummaryResponse, error) {
	var summary meSummaryResponse
	err := s.db.QueryRow(ctx, `
		SELECT COALESCE(u.display_name, u.name, ''),
		       COALESCE(u.primary_email, ac.email, u.email),
		       COALESCE(ac.provider, 'email'),
		       COUNT(DISTINCT c.id) FILTER (WHERE c.deleted_at IS NULL)::int AS total_cards,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL
		           AND rs.mastered_at IS NULL
		           AND rs.due_at <= now()
		       )::int AS due_count,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL
		           AND rs.mastered_at IS NULL
		           AND rs.state IN (0, 1)
		           AND rs.due_at <= now()
		       )::int AS new_count,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL
		           AND rs.mastered_at IS NULL
		           AND rs.state IN (2, 3)
		           AND rs.due_at <= now()
		       )::int AS review_due_count,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL AND rs.mastered_at IS NOT NULL
		       )::int AS mastered_count
		FROM users u
		LEFT JOIN account_connections ac ON ac.user_id = u.id AND ac.provider = 'apple'
		LEFT JOIN cards c ON c.user_id = u.id
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE u.id = $1
		GROUP BY u.id, u.display_name, u.name, u.primary_email, u.email, ac.email, ac.provider
	`, userID).Scan(
		&summary.User.Name,
		&summary.User.Email,
		&summary.User.Provider,
		&summary.TotalCards,
		&summary.DueCount,
		&summary.NewCount,
		&summary.ReviewDueCount,
		&summary.MasteredCount,
	)
	if err != nil {
		return meSummaryResponse{}, err
	}

	err = s.db.QueryRow(ctx, `
		SELECT COUNT(*) FILTER (WHERE created_at::date = now()::date)::int,
		       COUNT(*)::int
		FROM review_events
		WHERE user_id = $1
	`, userID).Scan(&summary.ReviewedToday, &summary.TotalReviewed)
	if err != nil {
		return meSummaryResponse{}, err
	}

	// 今天真正"毕业"的新卡数——直接看 graduated_at 落在用户本地的今天，而不是
	// 数据库的 UTC 今天。graduated_at 只在一张卡第一次进入 Review/Relearning 时
	// 写一次（见 scheduler.applyGraduation），之后即使又 lapse 也不会重复计数。
	dayStart, dayEnd := localDayRange(time.Now().UTC(), tzOffsetMinutes)
	err = s.db.QueryRow(ctx, `
		SELECT COUNT(*)::int
		FROM review_states rs
		JOIN cards c ON c.id = rs.card_id
		WHERE c.user_id = $1 AND c.deleted_at IS NULL
		  AND rs.graduated_at >= $2 AND rs.graduated_at < $3
	`, userID, dayStart, dayEnd).Scan(&summary.NewLearnedToday)
	if err != nil {
		return meSummaryResponse{}, err
	}

	prefs, err := s.loadLearningPreferences(ctx, userID)
	if err != nil {
		return meSummaryResponse{}, err
	}
	summary.NewRemainingToday, summary.ReviewRemainingToday, err = s.computeRemainingTodayForUser(
		ctx, userID, prefs, summary, dayStart, dayEnd,
	)
	if err != nil {
		return meSummaryResponse{}, err
	}

	checkInDate := dayStart.Format("2006-01-02")
	err = s.db.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM daily_check_ins WHERE user_id = $1 AND check_in_date = $2)
	`, userID, checkInDate).Scan(&summary.CheckedInToday)
	if err != nil {
		return meSummaryResponse{}, err
	}

	summary.CurrentStreak, err = s.currentCheckInStreak(ctx, userID, dayStart)
	if err != nil {
		return meSummaryResponse{}, err
	}

	// 窗口必须覆盖前端最长的展示跨度：
	//   · Me 页热力图 16 周 = 112 天
	//   · 成就页月历可回翻 12 个月
	// 原来只给 28 天，导致热力图左侧 3/4 恒为空、月历翻页永远无数据。
	// 这里展示的是"活动量"热力图，跟下面基于打卡记录的 current_streak 是两个
	// 不同的概念，有意保留：有活动不代表打满了当天的卡。
	rows, err := s.db.Query(ctx, `
		SELECT day::date::text,
		       COUNT(re.id)::int
		FROM generate_series(current_date - interval '364 days', current_date, interval '1 day') AS day
		LEFT JOIN review_events re
		  ON re.user_id = $1 AND re.created_at::date = day::date
		GROUP BY day
		ORDER BY day
	`, userID)
	if err != nil {
		return meSummaryResponse{}, err
	}
	defer rows.Close()

	summary.RecentActivity = []activityDayResponse{}
	for rows.Next() {
		var day activityDayResponse
		if err := rows.Scan(&day.Date, &day.Count); err != nil {
			return meSummaryResponse{}, err
		}
		summary.RecentActivity = append(summary.RecentActivity, day)
	}
	if err := rows.Err(); err != nil {
		return meSummaryResponse{}, err
	}

	return summary, nil
}

// currentCheckInStreak 从"本地今天"往回走连续打卡天数：今天已打卡就从今天数起，
// 没打卡就从昨天开始数，遇到第一个没打卡的日子就停。跟旧口径（当天有任意复习
// 记录就算一天）不同——现在必须真的点了"打卡"才算数。
func (s *Server) currentCheckInStreak(ctx context.Context, userID string, dayStart time.Time) (int, error) {
	rows, err := s.db.Query(ctx, `
		SELECT check_in_date::text
		FROM daily_check_ins
		WHERE user_id = $1 AND check_in_date >= $2
	`, userID, dayStart.AddDate(0, 0, -400).Format("2006-01-02"))
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	checkedInDates := make(map[string]bool)
	for rows.Next() {
		var date string
		if err := rows.Scan(&date); err != nil {
			return 0, err
		}
		checkedInDates[date] = true
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}

	cursor := dayStart
	if !checkedInDates[cursor.Format("2006-01-02")] {
		cursor = cursor.AddDate(0, 0, -1)
	}
	streak := 0
	for checkedInDates[cursor.Format("2006-01-02")] {
		streak++
		cursor = cursor.AddDate(0, 0, -1)
	}
	return streak, nil
}

func (s *Server) listSubjects(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	rows, err := s.db.Query(r.Context(), `
		SELECT s.id::text, s.name,
		       COUNT(DISTINCT c.id)::int AS card_count,
		       COUNT(DISTINCT CASE
		         WHEN rs.mastered_at IS NULL AND rs.state IN (2, 3) AND rs.due_at <= now() THEN c.id
		       END)::int AS due_count
		FROM subjects s
		LEFT JOIN sets st ON st.subject_id = s.id AND st.deleted_at IS NULL
		LEFT JOIN cards c ON c.set_id = st.id AND c.deleted_at IS NULL
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE s.user_id = $1 AND s.deleted_at IS NULL
		GROUP BY s.id, s.name
		ORDER BY s.name
	`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	subjects := []model.Subject{}
	for rows.Next() {
		var subject model.Subject
		if err := rows.Scan(&subject.ID, &subject.Name, &subject.CardCount, &subject.DueCount); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		subjects = append(subjects, subject)
	}
	writeJSON(w, http.StatusOK, subjects)
}

func (s *Server) listAllSets(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	rows, err := s.db.Query(r.Context(), `
		SELECT st.id::text, st.subject_id::text, st.name,
		       COUNT(DISTINCT c.id)::int AS card_count,
		       COUNT(DISTINCT CASE
		         WHEN rs.mastered_at IS NULL AND rs.state IN (2, 3) AND rs.due_at <= now() THEN c.id
		       END)::int AS due_count
		FROM sets st
		LEFT JOIN cards c ON c.set_id = st.id AND c.deleted_at IS NULL
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE st.user_id = $1 AND st.deleted_at IS NULL
		GROUP BY st.id, st.subject_id, st.name
		ORDER BY st.name
	`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	sets := []model.Set{}
	for rows.Next() {
		var set model.Set
		if err := rows.Scan(&set.ID, &set.SubjectID, &set.Name, &set.CardCount, &set.DueCount); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		sets = append(sets, set)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, sets)
}

func (s *Server) createSubject(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	var req nameRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := required(req.Name, "name"); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	id := uuid.NewString()
	var subject model.Subject
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO subjects (id, user_id, name)
		VALUES ($1, $2, $3)
		RETURNING id::text, name, 0, 0
	`, id, userID, strings.TrimSpace(req.Name)).Scan(&subject.ID, &subject.Name, &subject.CardCount, &subject.DueCount)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, subject)
}

func (s *Server) updateSubject(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	var req nameRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := required(req.Name, "name"); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	var subject model.Subject
	err := s.db.QueryRow(r.Context(), `
		UPDATE subjects
		SET name = $1, updated_at = now()
		WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
		RETURNING id::text, name, 0, 0
	`, strings.TrimSpace(req.Name), chi.URLParam(r, "subjectID"), userID).Scan(
		&subject.ID,
		&subject.Name,
		&subject.CardCount,
		&subject.DueCount,
	)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "subject not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, subject)
}

func (s *Server) deleteSubject(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	subjectID := chi.URLParam(r, "subjectID")
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	result, err := tx.Exec(r.Context(), `
		UPDATE subjects SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, subjectID, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if result.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "subject not found")
		return
	}

	if _, err = tx.Exec(r.Context(), `
		UPDATE sets SET deleted_at = now(), updated_at = now()
		WHERE subject_id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, subjectID, userID); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if _, err = tx.Exec(r.Context(), `
		UPDATE cards SET deleted_at = now(), updated_at = now()
		WHERE user_id = $2
		  AND deleted_at IS NULL
		  AND set_id IN (
		    SELECT id FROM sets WHERE subject_id = $1 AND user_id = $2
		  )
	`, subjectID, userID); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if err = tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) listSets(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	subjectID := chi.URLParam(r, "subjectID")
	rows, err := s.db.Query(r.Context(), `
		SELECT st.id::text, st.subject_id::text, st.name,
		       COUNT(DISTINCT c.id)::int AS card_count,
		       COUNT(DISTINCT CASE
		         WHEN rs.mastered_at IS NULL AND rs.state IN (2, 3) AND rs.due_at <= now() THEN c.id
		       END)::int AS due_count
		FROM sets st
		LEFT JOIN cards c ON c.set_id = st.id AND c.deleted_at IS NULL
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE st.user_id = $1 AND st.subject_id = $2 AND st.deleted_at IS NULL
		GROUP BY st.id, st.subject_id, st.name
		ORDER BY st.name
	`, userID, subjectID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	sets := []model.Set{}
	for rows.Next() {
		var set model.Set
		if err := rows.Scan(&set.ID, &set.SubjectID, &set.Name, &set.CardCount, &set.DueCount); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		sets = append(sets, set)
	}
	writeJSON(w, http.StatusOK, sets)
}

func (s *Server) createSet(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	subjectID := chi.URLParam(r, "subjectID")
	var req nameRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := required(req.Name, "name"); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	var subjectExists bool
	if err := s.db.QueryRow(r.Context(), `
		SELECT EXISTS (
			SELECT 1 FROM subjects
			WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		)
	`, subjectID, userID).Scan(&subjectExists); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if !subjectExists {
		writeError(w, http.StatusNotFound, "subject not found")
		return
	}
	id := uuid.NewString()
	var set model.Set
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO sets (id, user_id, subject_id, name)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, subject_id::text, name, 0, 0
	`, id, userID, subjectID, strings.TrimSpace(req.Name)).Scan(&set.ID, &set.SubjectID, &set.Name, &set.CardCount, &set.DueCount)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, set)
}

func (s *Server) updateSet(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	var req nameRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := required(req.Name, "name"); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	var set model.Set
	err := s.db.QueryRow(r.Context(), `
		UPDATE sets
		SET name = $1, updated_at = now()
		WHERE id = $2 AND subject_id = $3 AND user_id = $4 AND deleted_at IS NULL
		RETURNING id::text, subject_id::text, name, 0, 0
	`, strings.TrimSpace(req.Name), chi.URLParam(r, "setID"), chi.URLParam(r, "subjectID"), userID).Scan(
		&set.ID,
		&set.SubjectID,
		&set.Name,
		&set.CardCount,
		&set.DueCount,
	)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "set not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, set)
}

func (s *Server) deleteSet(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	subjectID := chi.URLParam(r, "subjectID")
	setID := chi.URLParam(r, "setID")
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	result, err := tx.Exec(r.Context(), `
		UPDATE sets SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND subject_id = $2 AND user_id = $3 AND deleted_at IS NULL
	`, setID, subjectID, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if result.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "set not found")
		return
	}

	if _, err = tx.Exec(r.Context(), `
			UPDATE cards SET deleted_at = now(), updated_at = now()
			WHERE set_id = $1
			  AND user_id = $2
			  AND deleted_at IS NULL
		`, setID, userID); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if err = tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) listCards(w http.ResponseWriter, r *http.Request) {
	cards, err := loadCards(r.Context(), s.db, cardFilters{
		UserID:    currentUserID(r),
		SubjectID: r.URL.Query().Get("subject_id"),
		SetIDs:    splitCSV(r.URL.Query().Get("set_ids")),
		Search:    r.URL.Query().Get("search"),
		OnlyDue:   false,
		Limit:     200,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, cards)
}

func (s *Server) getCard(w http.ResponseWriter, r *http.Request) {
	cards, err := loadCards(r.Context(), s.db, cardFilters{UserID: currentUserID(r), CardID: chi.URLParam(r, "cardID"), Limit: 1})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if len(cards) == 0 {
		writeError(w, http.StatusNotFound, "card not found")
		return
	}
	writeJSON(w, http.StatusOK, cards[0])
}

func (s *Server) getReviewPreview(w http.ResponseWriter, r *http.Request) {
	state, err := loadReviewState(r.Context(), s.db, currentUserID(r), chi.URLParam(r, "cardID"))
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "review state not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	now := time.Now().UTC()
	previews := scheduler.Preview(state, now)
	response := make([]reviewPreviewResponse, 0, len(previews))
	for _, preview := range previews {
		response = append(response, reviewPreviewResponse{
			Grade:           preview.Grade,
			IntervalSeconds: preview.IntervalSeconds,
			DueAt:           preview.Next.DueAt,
		})
	}
	writeJSON(w, http.StatusOK, response)
}

func (s *Server) createCard(w http.ResponseWriter, r *http.Request) {
	var req cardRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	card, err := upsertCard(r.Context(), s.db, currentUserID(r), "", req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, card)
}

func (s *Server) updateCard(w http.ResponseWriter, r *http.Request) {
	var req cardRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	card, err := upsertCard(r.Context(), s.db, currentUserID(r), chi.URLParam(r, "cardID"), req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, card)
}

func (s *Server) deleteCard(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	result, err := s.db.Exec(r.Context(), `
		UPDATE cards SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, chi.URLParam(r, "cardID"), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if result.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "card not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) masterCard(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	cardID := chi.URLParam(r, "cardID")
	result, err := s.db.Exec(r.Context(), `
		UPDATE review_states
		SET due_at = now() + interval '100 years',
		    mastered_at = now(),
		    last_reviewed_at = now()
		WHERE card_id = $1
		  AND EXISTS (
		    SELECT 1 FROM cards
		    WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		  )
	`, cardID, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if result.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "card not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "mastered"})
}

func (s *Server) listDueCards(w http.ResponseWriter, r *http.Request) {
	limit := 30
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}
	cards, err := loadCards(r.Context(), s.db, cardFilters{
		UserID:    currentUserID(r),
		SubjectID: r.URL.Query().Get("subject_id"),
		SetIDs:    splitCSV(r.URL.Query().Get("set_ids")),
		OnlyDue:   true,
		Limit:     limit,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, cards)
}

func (s *Server) submitReviewResult(w http.ResponseWriter, r *http.Request) {
	userID := currentUserID(r)
	var req reviewResultRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Mode == "" {
		req.Mode = "review"
	}
	if !scheduler.IsGrade(req.Rating) {
		writeError(w, http.StatusBadRequest, "rating must be again, hard, good, or easy")
		return
	}

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	state, err := loadReviewStateForUpdate(r.Context(), tx, userID, req.CardID)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "review state not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if req.ClientReviewID != "" {
		var existingCardID string
		err = tx.QueryRow(r.Context(), `
			SELECT card_id::text
			FROM review_events
			WHERE user_id = $1 AND client_review_id = $2
			LIMIT 1
		`, userID, req.ClientReviewID).Scan(&existingCardID)
		if err == nil {
			if existingCardID != req.CardID {
				writeError(w, http.StatusConflict, "client_review_id already used")
				return
			}
			writeJSON(w, http.StatusOK, state)
			return
		}
		if err != pgx.ErrNoRows {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
	}

	now := time.Now().UTC()
	next := scheduler.Apply(state, req.Rating, now)
	_, err = tx.Exec(r.Context(), `
		INSERT INTO review_events (
			id, card_id, user_id, client_review_id, mode, rating, revealed_tokens_count, total_tokens_count
		) VALUES ($1, $2, $3, NULLIF($4, ''), $5, $6, $7, $8)
	`, uuid.NewString(), req.CardID, userID, req.ClientReviewID, req.Mode, req.Rating, req.RevealedTokensCount, req.TotalTokensCount)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	_, err = tx.Exec(r.Context(), `
		UPDATE review_states
		SET state = $2,
		    stability = $3,
		    difficulty = $4,
		    due_at = $5,
		    scheduled_days = $6,
		    elapsed_days = $7,
		    review_count = $8,
		    lapse_count = $9,
		    last_reviewed_at = $10,
		    graduated_at = $11,
		    mastered_at = $12
		WHERE card_id = $1
	`, next.CardID, int16(next.State), next.Stability, next.Difficulty, next.DueAt, next.ScheduledDays, next.ElapsedDays, next.ReviewCount, next.LapseCount, next.LastReviewedAt, next.GraduatedAt, next.MasteredAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, next)
}

func loadReviewState(ctx context.Context, pool *pgxpool.Pool, userID string, cardID string) (model.ReviewState, error) {
	var state model.ReviewState
	var stateValue int16
	err := pool.QueryRow(ctx, `
		SELECT rs.card_id::text, rs.state, rs.stability, rs.difficulty, rs.due_at,
		       rs.scheduled_days, rs.elapsed_days, rs.review_count, rs.lapse_count,
		       rs.last_reviewed_at, rs.graduated_at, rs.mastered_at
		FROM review_states rs
		JOIN cards c ON c.id = rs.card_id
		WHERE rs.card_id = $1 AND c.user_id = $2 AND c.deleted_at IS NULL
	`, cardID, userID).Scan(
		&state.CardID,
		&stateValue,
		&state.Stability,
		&state.Difficulty,
		&state.DueAt,
		&state.ScheduledDays,
		&state.ElapsedDays,
		&state.ReviewCount,
		&state.LapseCount,
		&state.LastReviewedAt,
		&state.GraduatedAt,
		&state.MasteredAt,
	)
	state.State = fsrs.State(stateValue)
	return state, err
}

func loadReviewStateForUpdate(ctx context.Context, tx pgx.Tx, userID string, cardID string) (model.ReviewState, error) {
	var state model.ReviewState
	var stateValue int16
	err := tx.QueryRow(ctx, `
		SELECT rs.card_id::text, rs.state, rs.stability, rs.difficulty, rs.due_at,
		       rs.scheduled_days, rs.elapsed_days, rs.review_count, rs.lapse_count,
		       rs.last_reviewed_at, rs.graduated_at, rs.mastered_at
		FROM review_states rs
		JOIN cards c ON c.id = rs.card_id
		WHERE rs.card_id = $1 AND c.user_id = $2 AND c.deleted_at IS NULL
		FOR UPDATE OF rs
	`, cardID, userID).Scan(
		&state.CardID,
		&stateValue,
		&state.Stability,
		&state.Difficulty,
		&state.DueAt,
		&state.ScheduledDays,
		&state.ElapsedDays,
		&state.ReviewCount,
		&state.LapseCount,
		&state.LastReviewedAt,
		&state.GraduatedAt,
		&state.MasteredAt,
	)
	state.State = fsrs.State(stateValue)
	return state, err
}

func upsertCard(ctx context.Context, pool *pgxpool.Pool, userID string, cardID string, req cardRequest) (model.Card, error) {
	if err := required(req.SetID, "set_id"); err != nil {
		return model.Card{}, err
	}
	if err := required(req.FrontText, "front_text"); err != nil {
		return model.Card{}, err
	}
	if err := required(req.AnswerText, "answer_text"); err != nil {
		return model.Card{}, err
	}
	req.CardType = service.NormalizeCardType(req.CardType)
	req.SetID = strings.TrimSpace(req.SetID)
	// 方向由正面文本推断，不接受客户端指定 —— 避免与内容自相矛盾
	req.Direction = service.DetectDirection(req.FrontText)

	grammarJSON, err := model.GrammarJSON(req.GrammarPhrases)
	if err != nil {
		return model.Card{}, err
	}
	tokens := service.TokenizeAnswer(req.AnswerText, req.Direction)
	tokensJSON, err := model.TokensJSON(tokens)
	if err != nil {
		return model.Card{}, err
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return model.Card{}, err
	}
	defer tx.Rollback(ctx)

	var setSubjectID string
	if err = tx.QueryRow(ctx, `
		SELECT st.subject_id::text
		FROM sets st
		JOIN subjects s ON s.id = st.subject_id
		WHERE st.id = $1
		  AND st.user_id = $2
		  AND st.deleted_at IS NULL
		  AND s.deleted_at IS NULL
	`, req.SetID, userID).Scan(&setSubjectID); err != nil {
		if err == pgx.ErrNoRows {
			return model.Card{}, fmt.Errorf("set not found")
		}
		return model.Card{}, err
	}

	if cardID == "" {
		cardID = uuid.NewString()
		_, err = tx.Exec(ctx, `
				INSERT INTO cards (
					id, user_id, subject_id, set_id, card_type, direction, front_text, answer_text,
					grammar_phrases, answer_tokens
				) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb)
			`, cardID, userID, setSubjectID, req.SetID, req.CardType, req.Direction, strings.TrimSpace(req.FrontText), strings.TrimSpace(req.AnswerText), string(grammarJSON), string(tokensJSON))
		if err != nil {
			return model.Card{}, err
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO review_states (card_id)
			VALUES ($1)
		`, cardID)
		if err != nil {
			return model.Card{}, err
		}
	} else {
		result, err := tx.Exec(ctx, `
				UPDATE cards
				SET subject_id = $3,
				    set_id = $4,
				    card_type = $5,
				    direction = $6,
				    front_text = $7,
				    answer_text = $8,
				    grammar_phrases = $9::jsonb,
				    answer_tokens = $10::jsonb,
				    updated_at = now()
				WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
			`, cardID, userID, setSubjectID, req.SetID, req.CardType, req.Direction, strings.TrimSpace(req.FrontText), strings.TrimSpace(req.AnswerText), string(grammarJSON), string(tokensJSON))
		if err != nil {
			return model.Card{}, err
		}
		if result.RowsAffected() == 0 {
			return model.Card{}, fmt.Errorf("card not found")
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return model.Card{}, err
	}
	cards, err := loadCards(ctx, pool, cardFilters{UserID: userID, CardID: cardID, Limit: 1})
	if err != nil {
		return model.Card{}, err
	}
	if len(cards) == 0 {
		return model.Card{}, fmt.Errorf("card not found after save")
	}
	return cards[0], nil
}

type cardFilters struct {
	UserID    string
	CardID    string
	CardIDs   []string
	SubjectID string
	SetIDs    []string
	Search    string
	OnlyDue   bool
	Limit     int
}

func loadCards(ctx context.Context, pool *pgxpool.Pool, filters cardFilters) ([]model.Card, error) {
	args := []interface{}{filters.UserID}
	conditions := []string{"c.user_id = $1", "c.deleted_at IS NULL"}
	argIndex := 2

	if filters.CardID != "" {
		conditions = append(conditions, fmt.Sprintf("c.id = $%d", argIndex))
		args = append(args, filters.CardID)
		argIndex++
	}
	if len(filters.CardIDs) > 0 {
		placeholders := make([]string, 0, len(filters.CardIDs))
		for _, cardID := range filters.CardIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, cardID)
			argIndex++
		}
		conditions = append(conditions, fmt.Sprintf("c.id IN (%s)", strings.Join(placeholders, ",")))
	}
	if filters.SubjectID != "" {
		conditions = append(conditions, fmt.Sprintf("st.subject_id = $%d", argIndex))
		args = append(args, filters.SubjectID)
		argIndex++
	}
	if filters.Search != "" {
		conditions = append(conditions, fmt.Sprintf("(c.front_text ILIKE $%d OR c.answer_text ILIKE $%d)", argIndex, argIndex))
		args = append(args, "%"+filters.Search+"%")
		argIndex++
	}
	if filters.OnlyDue {
		conditions = append(conditions, "rs.due_at <= now()", "rs.mastered_at IS NULL")
	}
	if len(filters.SetIDs) > 0 {
		placeholders := make([]string, 0, len(filters.SetIDs))
		for _, setID := range filters.SetIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, setID)
			argIndex++
		}
		conditions = append(conditions, fmt.Sprintf("c.set_id IN (%s)", strings.Join(placeholders, ",")))
	}

	limit := filters.Limit
	if limit <= 0 {
		limit = 100
	}
	args = append(args, limit)
	limitPlaceholder := fmt.Sprintf("$%d", argIndex)

	query := fmt.Sprintf(`
			SELECT c.id::text,
			       c.set_id::text,
			       st.subject_id::text,
			       s.name,
			       st.id::text,
			       st.name,
			       c.card_type,
			       c.direction,
			       c.front_text, c.answer_text, c.grammar_phrases, c.answer_tokens,
			       c.created_at, c.updated_at
			FROM cards c
			JOIN sets st ON st.id = c.set_id AND st.deleted_at IS NULL
			JOIN subjects s ON s.id = st.subject_id AND s.deleted_at IS NULL
			JOIN review_states rs ON rs.card_id = c.id
			WHERE %s
			ORDER BY rs.due_at ASC, c.created_at DESC
		LIMIT %s
	`, strings.Join(conditions, " AND "), limitPlaceholder)

	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	cards := []model.Card{}
	for rows.Next() {
		var card model.Card
		var grammarBytes []byte
		var tokenBytes []byte
		if err := rows.Scan(
			&card.ID,
			&card.SetID,
			&card.SubjectID,
			&card.SubjectName,
			&card.Set.ID,
			&card.Set.Name,
			&card.CardType,
			&card.Direction,
			&card.FrontText,
			&card.AnswerText,
			&grammarBytes,
			&tokenBytes,
			&card.CreatedAt,
			&card.UpdatedAt,
		); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(grammarBytes, &card.GrammarPhrases); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(tokenBytes, &card.AnswerTokens); err != nil {
			return nil, err
		}
		card.Set.SubjectID = card.SubjectID
		cards = append(cards, card)
	}
	return cards, rows.Err()
}
