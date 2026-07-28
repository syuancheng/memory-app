package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"memory-app/backend/internal/db"
	"memory-app/backend/internal/model"
	"memory-app/backend/internal/scheduler"
	"memory-app/backend/internal/service"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type nameRequest struct {
	Name string `json:"name"`
}

type cardRequest struct {
	SubjectID      string                `json:"subject_id"`
	TagIDs         []string              `json:"tag_ids"`
	CardType       string                `json:"card_type"`
	Direction      string                `json:"direction"`
	FrontText      string                `json:"front_text"`
	AnswerText     string                `json:"answer_text"`
	GrammarPhrases []model.GrammarPhrase `json:"grammar_phrases"`
}

type reviewResultRequest struct {
	CardID              string `json:"card_id"`
	Mode                string `json:"mode"`
	Rating              string `json:"rating"`
	RevealedTokensCount int    `json:"revealed_tokens_count"`
	TotalTokensCount    int    `json:"total_tokens_count"`
}

type meSummaryResponse struct {
	User           meUserResponse        `json:"user"`
	TotalCards     int                   `json:"total_cards"`
	DueCount       int                   `json:"due_count"`
	MasteredCount  int                   `json:"mastered_count"`
	ReviewedToday  int                   `json:"reviewed_today"`
	TotalReviewed  int                   `json:"total_reviewed"`
	CurrentStreak  int                   `json:"current_streak"`
	RecentActivity []activityDayResponse `json:"recent_activity"`
}

type meUserResponse struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

type activityDayResponse struct {
	Date  string `json:"date"`
	Count int    `json:"count"`
}

func (s *Server) getMeSummary(w http.ResponseWriter, r *http.Request) {
	var summary meSummaryResponse
	err := s.db.QueryRow(r.Context(), `
		SELECT u.name,
		       u.email,
		       COUNT(DISTINCT c.id) FILTER (WHERE c.deleted_at IS NULL)::int AS total_cards,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL
		           AND rs.status NOT IN ('deleted', 'mastered')
		           AND rs.due_at <= now()
		       )::int AS due_count,
		       COUNT(DISTINCT c.id) FILTER (
		         WHERE c.deleted_at IS NULL AND rs.status = 'mastered'
		       )::int AS mastered_count
		FROM users u
		LEFT JOIN cards c ON c.user_id = u.id
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE u.id = $1
		GROUP BY u.id, u.name, u.email
	`, db.DemoUserID).Scan(
		&summary.User.Name,
		&summary.User.Email,
		&summary.TotalCards,
		&summary.DueCount,
		&summary.MasteredCount,
	)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	err = s.db.QueryRow(r.Context(), `
		SELECT COUNT(*) FILTER (WHERE created_at::date = now()::date)::int,
		       COUNT(*)::int
		FROM review_events
		WHERE user_id = $1
	`, db.DemoUserID).Scan(&summary.ReviewedToday, &summary.TotalReviewed)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	rows, err := s.db.Query(r.Context(), `
		SELECT day::date::text,
		       COUNT(re.id)::int
		FROM generate_series(current_date - interval '27 days', current_date, interval '1 day') AS day
		LEFT JOIN review_events re
		  ON re.user_id = $1 AND re.created_at::date = day::date
		GROUP BY day
		ORDER BY day
	`, db.DemoUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	summary.RecentActivity = []activityDayResponse{}
	for rows.Next() {
		var day activityDayResponse
		if err := rows.Scan(&day.Date, &day.Count); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		summary.RecentActivity = append(summary.RecentActivity, day)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	for i := len(summary.RecentActivity) - 1; i >= 0; i-- {
		if summary.RecentActivity[i].Count == 0 {
			break
		}
		summary.CurrentStreak++
	}

	writeJSON(w, http.StatusOK, summary)
}

func (s *Server) listSubjects(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.Query(r.Context(), `
		SELECT s.id::text, s.name,
		       COUNT(DISTINCT c.id)::int AS card_count,
		       COUNT(DISTINCT CASE
		         WHEN rs.due_at <= now() AND rs.status NOT IN ('deleted', 'mastered') THEN c.id
		       END)::int AS due_count
		FROM subjects s
		LEFT JOIN cards c ON c.subject_id = s.id AND c.deleted_at IS NULL
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE s.user_id = $1 AND s.deleted_at IS NULL
		GROUP BY s.id, s.name
		ORDER BY s.name
	`, db.DemoUserID)
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

func (s *Server) createSubject(w http.ResponseWriter, r *http.Request) {
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
	`, id, db.DemoUserID, strings.TrimSpace(req.Name)).Scan(&subject.ID, &subject.Name, &subject.CardCount, &subject.DueCount)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, subject)
}

func (s *Server) listTags(w http.ResponseWriter, r *http.Request) {
	subjectID := chi.URLParam(r, "subjectID")
	rows, err := s.db.Query(r.Context(), `
		SELECT t.id::text, t.subject_id::text, t.name,
		       COUNT(DISTINCT c.id)::int AS card_count,
		       COUNT(DISTINCT CASE
		         WHEN rs.due_at <= now() AND rs.status NOT IN ('deleted', 'mastered') THEN c.id
		       END)::int AS due_count
		FROM tags t
		LEFT JOIN card_tags ct ON ct.tag_id = t.id
		LEFT JOIN cards c ON c.id = ct.card_id AND c.deleted_at IS NULL
		LEFT JOIN review_states rs ON rs.card_id = c.id
		WHERE t.user_id = $1 AND t.subject_id = $2 AND t.deleted_at IS NULL
		GROUP BY t.id, t.subject_id, t.name
		ORDER BY t.name
	`, db.DemoUserID, subjectID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	tags := []model.Tag{}
	for rows.Next() {
		var tag model.Tag
		if err := rows.Scan(&tag.ID, &tag.SubjectID, &tag.Name, &tag.CardCount, &tag.DueCount); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		tags = append(tags, tag)
	}
	writeJSON(w, http.StatusOK, tags)
}

func (s *Server) createTag(w http.ResponseWriter, r *http.Request) {
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
	id := uuid.NewString()
	var tag model.Tag
	err := s.db.QueryRow(r.Context(), `
		INSERT INTO tags (id, user_id, subject_id, name)
		VALUES ($1, $2, $3, $4)
		RETURNING id::text, subject_id::text, name, 0, 0
	`, id, db.DemoUserID, subjectID, strings.TrimSpace(req.Name)).Scan(&tag.ID, &tag.SubjectID, &tag.Name, &tag.CardCount, &tag.DueCount)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, tag)
}

func (s *Server) listCards(w http.ResponseWriter, r *http.Request) {
	cards, err := loadCards(r.Context(), s.db, cardFilters{
		SubjectID: r.URL.Query().Get("subject_id"),
		TagIDs:    splitCSV(r.URL.Query().Get("tag_ids")),
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
	cards, err := loadCards(r.Context(), s.db, cardFilters{CardID: chi.URLParam(r, "cardID"), Limit: 1})
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

func (s *Server) createCard(w http.ResponseWriter, r *http.Request) {
	var req cardRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	card, err := upsertCard(r.Context(), s.db, "", req)
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
	card, err := upsertCard(r.Context(), s.db, chi.URLParam(r, "cardID"), req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, card)
}

func (s *Server) deleteCard(w http.ResponseWriter, r *http.Request) {
	commandTag, err := s.db.Exec(r.Context(), `
		UPDATE cards SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, chi.URLParam(r, "cardID"), db.DemoUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if commandTag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, "card not found")
		return
	}
	_, err = s.db.Exec(r.Context(), `
		UPDATE review_states SET status = 'deleted'
		WHERE card_id = $1
	`, chi.URLParam(r, "cardID"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) masterCard(w http.ResponseWriter, r *http.Request) {
	cardID := chi.URLParam(r, "cardID")
	commandTag, err := s.db.Exec(r.Context(), `
		UPDATE review_states
		SET status = 'mastered',
		    due_at = now() + interval '100 years',
		    mastered_at = now(),
		    last_reviewed_at = now()
		WHERE card_id = $1
		  AND EXISTS (
		    SELECT 1 FROM cards
		    WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		  )
	`, cardID, db.DemoUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if commandTag.RowsAffected() == 0 {
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
		SubjectID: r.URL.Query().Get("subject_id"),
		TagIDs:    splitCSV(r.URL.Query().Get("tag_ids")),
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
	var req reviewResultRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Mode == "" {
		req.Mode = "review"
	}
	if req.Rating != "forgot" && req.Rating != "fuzzy" && req.Rating != "remembered" {
		writeError(w, http.StatusBadRequest, "rating must be forgot, fuzzy, or remembered")
		return
	}

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback(r.Context())

	var state model.ReviewState
	err = tx.QueryRow(r.Context(), `
		SELECT card_id::text, status, ease::float8, interval_days, due_at, review_count, lapse_count,
		       last_reviewed_at, mastered_at
		FROM review_states
		WHERE card_id = $1
		FOR UPDATE
	`, req.CardID).Scan(
		&state.CardID,
		&state.Status,
		&state.Ease,
		&state.IntervalDays,
		&state.DueAt,
		&state.ReviewCount,
		&state.LapseCount,
		&state.LastReviewedAt,
		&state.MasteredAt,
	)
	if err == pgx.ErrNoRows {
		writeError(w, http.StatusNotFound, "review state not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	now := time.Now().UTC()
	next := scheduler.Apply(state, req.Rating, now)
	_, err = tx.Exec(r.Context(), `
		INSERT INTO review_events (
			id, card_id, user_id, mode, rating, revealed_tokens_count, total_tokens_count
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, uuid.NewString(), req.CardID, db.DemoUserID, req.Mode, req.Rating, req.RevealedTokensCount, req.TotalTokensCount)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	_, err = tx.Exec(r.Context(), `
		UPDATE review_states
		SET status = $2,
		    ease = $3,
		    interval_days = $4,
		    due_at = $5,
		    review_count = $6,
		    lapse_count = $7,
		    last_reviewed_at = $8,
		    mastered_at = $9
		WHERE card_id = $1
	`, next.CardID, next.Status, next.Ease, next.IntervalDays, next.DueAt, next.ReviewCount, next.LapseCount, next.LastReviewedAt, next.MasteredAt)
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

func upsertCard(ctx context.Context, pool *pgxpool.Pool, cardID string, req cardRequest) (model.Card, error) {
	if err := required(req.SubjectID, "subject_id"); err != nil {
		return model.Card{}, err
	}
	if err := required(req.FrontText, "front_text"); err != nil {
		return model.Card{}, err
	}
	if err := required(req.AnswerText, "answer_text"); err != nil {
		return model.Card{}, err
	}
	if len(req.TagIDs) == 0 {
		return model.Card{}, fmt.Errorf("at least one tag_id is required")
	}
	if req.CardType == "" {
		req.CardType = "speaking_expression"
	}
	if req.Direction == "" {
		req.Direction = "zh_to_en"
	}

	grammarJSON, err := model.GrammarJSON(req.GrammarPhrases)
	if err != nil {
		return model.Card{}, err
	}
	tokens := service.TokenizeAnswer(req.AnswerText)
	tokensJSON, err := model.TokensJSON(tokens)
	if err != nil {
		return model.Card{}, err
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return model.Card{}, err
	}
	defer tx.Rollback(ctx)

	if cardID == "" {
		cardID = uuid.NewString()
		_, err = tx.Exec(ctx, `
			INSERT INTO cards (
				id, user_id, subject_id, card_type, direction, front_text, answer_text,
				grammar_phrases, answer_tokens
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb)
		`, cardID, db.DemoUserID, req.SubjectID, req.CardType, req.Direction, strings.TrimSpace(req.FrontText), strings.TrimSpace(req.AnswerText), string(grammarJSON), string(tokensJSON))
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
		commandTag, err := tx.Exec(ctx, `
			UPDATE cards
			SET subject_id = $3,
			    card_type = $4,
			    direction = $5,
			    front_text = $6,
			    answer_text = $7,
			    grammar_phrases = $8::jsonb,
			    answer_tokens = $9::jsonb,
			    updated_at = now()
			WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		`, cardID, db.DemoUserID, req.SubjectID, req.CardType, req.Direction, strings.TrimSpace(req.FrontText), strings.TrimSpace(req.AnswerText), string(grammarJSON), string(tokensJSON))
		if err != nil {
			return model.Card{}, err
		}
		if commandTag.RowsAffected() == 0 {
			return model.Card{}, fmt.Errorf("card not found")
		}
		_, err = tx.Exec(ctx, `DELETE FROM card_tags WHERE card_id = $1`, cardID)
		if err != nil {
			return model.Card{}, err
		}
	}

	for _, tagID := range req.TagIDs {
		_, err = tx.Exec(ctx, `
			INSERT INTO card_tags (card_id, tag_id)
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, cardID, tagID)
		if err != nil {
			return model.Card{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return model.Card{}, err
	}
	cards, err := loadCards(ctx, pool, cardFilters{CardID: cardID, Limit: 1})
	if err != nil {
		return model.Card{}, err
	}
	if len(cards) == 0 {
		return model.Card{}, fmt.Errorf("card not found after save")
	}
	return cards[0], nil
}

type cardFilters struct {
	CardID    string
	SubjectID string
	TagIDs    []string
	Search    string
	OnlyDue   bool
	Limit     int
}

func loadCards(ctx context.Context, pool *pgxpool.Pool, filters cardFilters) ([]model.Card, error) {
	args := []interface{}{db.DemoUserID}
	conditions := []string{"c.user_id = $1", "c.deleted_at IS NULL"}
	argIndex := 2

	if filters.CardID != "" {
		conditions = append(conditions, fmt.Sprintf("c.id = $%d", argIndex))
		args = append(args, filters.CardID)
		argIndex++
	}
	if filters.SubjectID != "" {
		conditions = append(conditions, fmt.Sprintf("c.subject_id = $%d", argIndex))
		args = append(args, filters.SubjectID)
		argIndex++
	}
	if filters.Search != "" {
		conditions = append(conditions, fmt.Sprintf("(c.front_text ILIKE $%d OR c.answer_text ILIKE $%d)", argIndex, argIndex))
		args = append(args, "%"+filters.Search+"%")
		argIndex++
	}
	if filters.OnlyDue {
		conditions = append(conditions, "rs.due_at <= now()", "rs.status NOT IN ('deleted', 'mastered')")
	}
	if len(filters.TagIDs) > 0 {
		placeholders := make([]string, 0, len(filters.TagIDs))
		for _, tagID := range filters.TagIDs {
			placeholders = append(placeholders, fmt.Sprintf("$%d", argIndex))
			args = append(args, tagID)
			argIndex++
		}
		conditions = append(conditions, fmt.Sprintf(`
			EXISTS (
				SELECT 1 FROM card_tags selected
				WHERE selected.card_id = c.id AND selected.tag_id IN (%s)
			)
		`, strings.Join(placeholders, ",")))
	}

	limit := filters.Limit
	if limit <= 0 {
		limit = 100
	}
	args = append(args, limit)
	limitPlaceholder := fmt.Sprintf("$%d", argIndex)

	query := fmt.Sprintf(`
		SELECT c.id::text, c.subject_id::text, s.name, c.card_type, c.direction,
		       c.front_text, c.answer_text, c.grammar_phrases, c.answer_tokens,
		       c.created_at, c.updated_at
		FROM cards c
		JOIN subjects s ON s.id = c.subject_id
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
			&card.SubjectID,
			&card.SubjectName,
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
		tags, err := loadCardTags(ctx, pool, card.ID)
		if err != nil {
			return nil, err
		}
		card.Tags = tags
		cards = append(cards, card)
	}
	return cards, rows.Err()
}

func loadCardTags(ctx context.Context, pool *pgxpool.Pool, cardID string) ([]model.Tag, error) {
	rows, err := pool.Query(ctx, `
		SELECT t.id::text, t.subject_id::text, t.name, 0, 0
		FROM tags t
		JOIN card_tags ct ON ct.tag_id = t.id
		WHERE ct.card_id = $1 AND t.deleted_at IS NULL
		ORDER BY t.name
	`, cardID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	tags := []model.Tag{}
	for rows.Next() {
		var tag model.Tag
		if err := rows.Scan(&tag.ID, &tag.SubjectID, &tag.Name, &tag.CardCount, &tag.DueCount); err != nil {
			return nil, err
		}
		tags = append(tags, tag)
	}
	return tags, rows.Err()
}
