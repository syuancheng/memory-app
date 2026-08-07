package mcpserver

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"memory-app/backend/internal/db"
	"memory-app/backend/internal/model"
	"memory-app/backend/internal/service"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const maxBatchCards = 100

type ServerConfig struct {
	AuthToken      string
	AllowedHosts   []string
	AllowedOrigins []string
	JSONResponse   bool
}

func NewHTTPHandler(pool *pgxpool.Pool, cfg ServerConfig) http.Handler {
	server := NewServer(pool)
	handler := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server {
		return server
	}, &mcp.StreamableHTTPOptions{JSONResponse: cfg.JSONResponse})
	return withHostValidation(cfg.AllowedHosts, withCORS(cfg.AllowedOrigins, withAuth(cfg.AuthToken, handler)))
}

func NewServer(pool *pgxpool.Pool) *mcp.Server {
	tools := &Tools{pool: pool}
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "memory-app",
		Version: "0.1.0",
	}, &mcp.ServerOptions{
		Instructions: "Use get_subjects_sets before add_cards so you can pass exact subject_id and set_ids. Use add_cards for single-card or batch creation. Only use delete_card when the exact card_id is known.",
	})

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_subjects_sets",
		Title:       "Get Subjects And Sets",
		Description: "Return all English learning subjects and their sets. Sets map to backend tags.",
		Annotations: &mcp.ToolAnnotations{
			ReadOnlyHint:  true,
			OpenWorldHint: boolPtr(false),
		},
	}, tools.GetSubjectsSets)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "add_cards",
		Title:       "Add Cards",
		Description: "Create one or more flashcards under existing subject and set IDs.",
		Annotations: &mcp.ToolAnnotations{
			ReadOnlyHint:    false,
			DestructiveHint: boolPtr(false),
			IdempotentHint:  false,
			OpenWorldHint:   boolPtr(false),
		},
	}, tools.AddCards)

	mcp.AddTool(server, &mcp.Tool{
		Name:        "delete_card",
		Title:       "Delete Card",
		Description: "Delete a flashcard by exact card ID.",
		Annotations: &mcp.ToolAnnotations{
			ReadOnlyHint:    false,
			DestructiveHint: boolPtr(true),
			IdempotentHint:  true,
			OpenWorldHint:   boolPtr(false),
		},
	}, tools.DeleteCard)

	return server
}

type Tools struct {
	pool *pgxpool.Pool
}

type EmptyInput struct{}

type GetSubjectsSetsOutput struct {
	Subjects []SubjectWithSets `json:"subjects" jsonschema:"all subjects with their sets"`
}

type SubjectWithSets struct {
	SubjectID   string       `json:"subject_id" jsonschema:"subject ID"`
	SubjectName string       `json:"subject_name" jsonschema:"subject name"`
	CardCount   int          `json:"card_count" jsonschema:"number of active cards under the subject"`
	DueCount    int          `json:"due_count" jsonschema:"number of due cards under the subject"`
	Sets        []SetSummary `json:"sets" jsonschema:"sets under this subject"`
}

type SetSummary struct {
	SetID     string `json:"set_id" jsonschema:"set ID"`
	SetName   string `json:"set_name" jsonschema:"set name"`
	CardCount int    `json:"card_count" jsonschema:"number of active cards in the set"`
	DueCount  int    `json:"due_count" jsonschema:"number of due cards in the set"`
}

func (t *Tools) GetSubjectsSets(ctx context.Context, _ *mcp.CallToolRequest, _ EmptyInput) (*mcp.CallToolResult, GetSubjectsSetsOutput, error) {
	subjects, err := t.listSubjects(ctx)
	if err != nil {
		return nil, GetSubjectsSetsOutput{}, err
	}

	output := GetSubjectsSetsOutput{Subjects: make([]SubjectWithSets, 0, len(subjects))}
	for _, subject := range subjects {
		sets, err := t.listSets(ctx, subject.ID)
		if err != nil {
			return nil, GetSubjectsSetsOutput{}, err
		}

		item := SubjectWithSets{
			SubjectID:   subject.ID,
			SubjectName: subject.Name,
			CardCount:   subject.CardCount,
			DueCount:    subject.DueCount,
			Sets:        make([]SetSummary, 0, len(sets)),
		}
		for _, set := range sets {
			item.Sets = append(item.Sets, SetSummary{
				SetID:     set.ID,
				SetName:   set.Name,
				CardCount: set.CardCount,
				DueCount:  set.DueCount,
			})
		}
		output.Subjects = append(output.Subjects, item)
	}

	return nil, output, nil
}

type AddCardsInput struct {
	Cards []AddCardInput `json:"cards" jsonschema:"cards to create in order"`
}

type AddCardInput struct {
	SubjectID      string          `json:"subject_id" jsonschema:"existing subject ID"`
	SetIDs         []string        `json:"set_ids" jsonschema:"existing set IDs; sets map to backend tags"`
	FrontText      string          `json:"front_text" jsonschema:"front prompt, usually Chinese"`
	AnswerText     string          `json:"answer_text" jsonschema:"English answer sentence"`
	GrammarPhrases []GrammarPhrase `json:"grammar_phrases,omitempty" jsonschema:"phrase, grammar, or vocabulary hints"`
	CardType       string          `json:"card_type,omitempty" jsonschema:"card type: speaking_expression, grammar, or sentence"`
	Direction      string          `json:"direction,omitempty" jsonschema:"card direction; defaults to zh_to_en"`
}

type GrammarPhrase struct {
	Text string `json:"text" jsonschema:"phrase, grammar pattern, or vocabulary item"`
	Note string `json:"note,omitempty" jsonschema:"optional note or explanation"`
}

type AddCardsOutput struct {
	CreatedCount int                  `json:"created_count" jsonschema:"number of cards created"`
	FailedCount  int                  `json:"failed_count" jsonschema:"number of cards that failed"`
	Created      []CreatedCardSummary `json:"created" jsonschema:"created cards"`
	Failed       []FailedCardSummary  `json:"failed" jsonschema:"failed card inputs"`
}

type CreatedCardSummary struct {
	Index      int      `json:"index" jsonschema:"index in the input cards array"`
	CardID     string   `json:"card_id" jsonschema:"created card ID"`
	SubjectID  string   `json:"subject_id" jsonschema:"subject ID"`
	SetIDs     []string `json:"set_ids" jsonschema:"set IDs attached to the card"`
	FrontText  string   `json:"front_text" jsonschema:"front prompt"`
	AnswerText string   `json:"answer_text" jsonschema:"answer text"`
}

type FailedCardSummary struct {
	Index int    `json:"index" jsonschema:"index in the input cards array"`
	Error string `json:"error" jsonschema:"failure reason"`
}

func (t *Tools) AddCards(ctx context.Context, _ *mcp.CallToolRequest, input AddCardsInput) (*mcp.CallToolResult, AddCardsOutput, error) {
	if len(input.Cards) == 0 {
		return nil, AddCardsOutput{}, errors.New("cards must contain at least one card")
	}
	if len(input.Cards) > maxBatchCards {
		return nil, AddCardsOutput{}, fmt.Errorf("cards cannot contain more than %d cards", maxBatchCards)
	}

	output := AddCardsOutput{
		Created: []CreatedCardSummary{},
		Failed:  []FailedCardSummary{},
	}
	for index, cardInput := range input.Cards {
		card, err := t.createCard(ctx, cardInput)
		if err != nil {
			output.Failed = append(output.Failed, FailedCardSummary{Index: index, Error: err.Error()})
			continue
		}

		setIDs := make([]string, 0, len(card.Tags))
		for _, tag := range card.Tags {
			setIDs = append(setIDs, tag.ID)
		}
		output.Created = append(output.Created, CreatedCardSummary{
			Index:      index,
			CardID:     card.ID,
			SubjectID:  card.SubjectID,
			SetIDs:     setIDs,
			FrontText:  card.FrontText,
			AnswerText: card.AnswerText,
		})
	}
	output.CreatedCount = len(output.Created)
	output.FailedCount = len(output.Failed)

	result := &mcp.CallToolResult{}
	if output.CreatedCount == 0 && output.FailedCount > 0 {
		result.IsError = true
	}
	return result, output, nil
}

type DeleteCardInput struct {
	CardID string `json:"card_id" jsonschema:"existing card ID to delete"`
}

type DeleteCardOutput struct {
	Status string `json:"status" jsonschema:"delete status"`
	CardID string `json:"card_id" jsonschema:"deleted card ID"`
}

func (t *Tools) DeleteCard(ctx context.Context, _ *mcp.CallToolRequest, input DeleteCardInput) (*mcp.CallToolResult, DeleteCardOutput, error) {
	cardID := strings.TrimSpace(input.CardID)
	if cardID == "" {
		return nil, DeleteCardOutput{}, errors.New("card_id is required")
	}

	commandTag, err := t.pool.Exec(ctx, `
		UPDATE cards SET deleted_at = now(), updated_at = now()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
	`, cardID, db.DemoUserID)
	if err != nil {
		return nil, DeleteCardOutput{}, err
	}
	if commandTag.RowsAffected() == 0 {
		return nil, DeleteCardOutput{}, errors.New("card not found")
	}

	_, err = t.pool.Exec(ctx, `
		UPDATE review_states SET status = 'deleted'
		WHERE card_id = $1
	`, cardID)
	if err != nil {
		return nil, DeleteCardOutput{}, err
	}

	return nil, DeleteCardOutput{Status: "deleted", CardID: cardID}, nil
}

func (t *Tools) listSubjects(ctx context.Context) ([]model.Subject, error) {
	rows, err := t.pool.Query(ctx, `
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
		return nil, err
	}
	defer rows.Close()

	var subjects []model.Subject
	for rows.Next() {
		var subject model.Subject
		if err := rows.Scan(&subject.ID, &subject.Name, &subject.CardCount, &subject.DueCount); err != nil {
			return nil, err
		}
		subjects = append(subjects, subject)
	}
	return subjects, rows.Err()
}

func (t *Tools) listSets(ctx context.Context, subjectID string) ([]model.Tag, error) {
	rows, err := t.pool.Query(ctx, `
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
		return nil, err
	}
	defer rows.Close()

	var sets []model.Tag
	for rows.Next() {
		var set model.Tag
		if err := rows.Scan(&set.ID, &set.SubjectID, &set.Name, &set.CardCount, &set.DueCount); err != nil {
			return nil, err
		}
		sets = append(sets, set)
	}
	return sets, rows.Err()
}

func (t *Tools) createCard(ctx context.Context, input AddCardInput) (model.Card, error) {
	input.SubjectID = strings.TrimSpace(input.SubjectID)
	input.FrontText = strings.TrimSpace(input.FrontText)
	input.AnswerText = strings.TrimSpace(input.AnswerText)
	input.CardType = strings.TrimSpace(input.CardType)
	input.Direction = strings.TrimSpace(input.Direction)

	if input.SubjectID == "" {
		return model.Card{}, errors.New("subject_id is required")
	}
	if len(input.SetIDs) == 0 {
		return model.Card{}, errors.New("set_ids must contain at least one set")
	}
	if input.FrontText == "" {
		return model.Card{}, errors.New("front_text is required")
	}
	if input.AnswerText == "" {
		return model.Card{}, errors.New("answer_text is required")
	}
	if input.CardType == "" {
		input.CardType = "speaking_expression"
	}
	if input.Direction == "" {
		input.Direction = "zh_to_en"
	}

	cardID := uuid.NewString()
	grammarPhrases := make([]model.GrammarPhrase, 0, len(input.GrammarPhrases))
	for _, phrase := range input.GrammarPhrases {
		text := strings.TrimSpace(phrase.Text)
		if text == "" {
			continue
		}
		grammarPhrases = append(grammarPhrases, model.GrammarPhrase{
			Text: text,
			Note: strings.TrimSpace(phrase.Note),
		})
	}

	grammarJSON, err := model.GrammarJSON(grammarPhrases)
	if err != nil {
		return model.Card{}, err
	}
	tokensJSON, err := model.TokensJSON(service.TokenizeAnswer(input.AnswerText))
	if err != nil {
		return model.Card{}, err
	}

	tx, err := t.pool.Begin(ctx)
	if err != nil {
		return model.Card{}, err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO cards (
			id, user_id, subject_id, card_type, direction, front_text, answer_text,
			grammar_phrases, answer_tokens
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb)
	`, cardID, db.DemoUserID, input.SubjectID, input.CardType, input.Direction, input.FrontText, input.AnswerText, string(grammarJSON), string(tokensJSON))
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

	for _, rawSetID := range input.SetIDs {
		setID := strings.TrimSpace(rawSetID)
		if setID == "" {
			return model.Card{}, errors.New("set_ids cannot contain empty values")
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO card_tags (card_id, tag_id)
			VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, cardID, setID)
		if err != nil {
			return model.Card{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return model.Card{}, err
	}

	return t.loadCard(ctx, cardID)
}

func (t *Tools) loadCard(ctx context.Context, cardID string) (model.Card, error) {
	var card model.Card
	var grammarBytes []byte
	var tokenBytes []byte
	err := t.pool.QueryRow(ctx, `
		SELECT c.id::text, c.subject_id::text, s.name, c.card_type, c.direction,
		       c.front_text, c.answer_text, c.grammar_phrases, c.answer_tokens,
		       c.created_at, c.updated_at
		FROM cards c
		JOIN subjects s ON s.id = c.subject_id
		WHERE c.id = $1 AND c.user_id = $2 AND c.deleted_at IS NULL
	`, cardID, db.DemoUserID).Scan(
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
	)
	if err == pgx.ErrNoRows {
		return model.Card{}, errors.New("card not found after create")
	}
	if err != nil {
		return model.Card{}, err
	}
	if err := json.Unmarshal(grammarBytes, &card.GrammarPhrases); err != nil {
		return model.Card{}, err
	}
	if err := json.Unmarshal(tokenBytes, &card.AnswerTokens); err != nil {
		return model.Card{}, err
	}
	card.Tags, err = t.loadCardTags(ctx, card.ID)
	if err != nil {
		return model.Card{}, err
	}
	return card, nil
}

func (t *Tools) loadCardTags(ctx context.Context, cardID string) ([]model.Tag, error) {
	rows, err := t.pool.Query(ctx, `
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

	var tags []model.Tag
	for rows.Next() {
		var tag model.Tag
		if err := rows.Scan(&tag.ID, &tag.SubjectID, &tag.Name, &tag.CardCount, &tag.DueCount); err != nil {
			return nil, err
		}
		tags = append(tags, tag)
	}
	return tags, rows.Err()
}

func withAuth(token string, next http.Handler) http.Handler {
	if token == "" {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		bearer := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		headerToken := strings.TrimSpace(r.Header.Get("X-Memory-Mcp-Token"))
		if bearer == token || headerToken == token {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	})
}

func withCORS(allowedOrigins []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && originAllowed(origin, allowedOrigins) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
		}
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Mcp-Session-Id, X-Memory-Mcp-Token")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Expose-Headers", "Mcp-Session-Id")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func withHostValidation(allowedHosts []string, next http.Handler) http.Handler {
	if len(allowedHosts) == 0 {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host := r.Host
		if idx := strings.LastIndex(host, ":"); idx >= 0 {
			host = host[:idx]
		}
		for _, allowed := range allowedHosts {
			if strings.EqualFold(host, allowed) {
				next.ServeHTTP(w, r)
				return
			}
		}
		http.Error(w, "host not allowed", http.StatusForbidden)
	})
}

func originAllowed(origin string, allowedOrigins []string) bool {
	if len(allowedOrigins) == 0 {
		return true
	}
	for _, allowed := range allowedOrigins {
		if allowed == "*" || allowed == origin {
			return true
		}
	}
	return false
}

func boolPtr(value bool) *bool {
	return &value
}
