package mcpserver

import (
	"context"
	"testing"

	"memory-app/backend/internal/db"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestToolsAddAndDeleteCards(t *testing.T) {
	// 工具从 context 取 userID（withAuth 中间件负责注入）。测试直接调用工具，
	// 必须自己注入，否则一律返回 "authenticated user is required"。
	baseCtx := context.Background()
	userID := uuid.NewString()
	ctx := context.WithValue(baseCtx, mcpUserIDKey{}, userID)
	pool := testPool(t, ctx)
	tools := &Tools{pool: pool}

	seedUser(t, ctx, pool, userID, userID+"@example.com")
	subjectID := uuid.NewString()
	setID := uuid.NewString()
	seedSubjectAndSetForUser(t, ctx, pool, userID, subjectID, setID)
	secondSetID := uuid.NewString()
	seedSubjectAndSetForUser(t, ctx, pool, userID, subjectID, secondSetID)

	subjectsResult, _, err := tools.GetSubjectsSets(ctx, nil, EmptyInput{})
	if err != nil {
		t.Fatalf("GetSubjectsSets error: %v", err)
	}
	if subjectsResult != nil {
		t.Fatalf("GetSubjectsSets returned unexpected explicit result")
	}

	_, addOutput, err := tools.AddCards(ctx, nil, AddCardsInput{
		Cards: []AddCardInput{
			{
				SetID:      setID,
				FrontText:  "我想确认一下。",
				AnswerText: "I would like to confirm.",
				GrammarPhrases: []GrammarPhrase{
					{Text: "would like to", Note: "polite expression"},
				},
			},
			{
				SetID:      "not-a-real-set",
				FrontText:  "bad card",
				AnswerText: "This should fail.",
			},
		},
	})
	if err != nil {
		t.Fatalf("AddCards error: %v", err)
	}
	if addOutput.CreatedCount != 1 || addOutput.FailedCount != 1 {
		t.Fatalf("AddCards counts = created %d failed %d, want 1/1", addOutput.CreatedCount, addOutput.FailedCount)
	}

	cardID := addOutput.Created[0].CardID
	if cardID == "" {
		t.Fatal("created card ID is empty")
	}

	_, setCards, err := tools.GetSetCards(ctx, nil, GetSetCardsInput{SetID: setID})
	if err != nil {
		t.Fatalf("GetSetCards error: %v", err)
	}
	if len(setCards.Cards) != 1 || setCards.Cards[0].CardID != cardID {
		t.Fatalf("GetSetCards cards = %+v, want created card", setCards.Cards)
	}

	frontText := "我只是想确认一下进展。"
	answerText := "I just wanted to check on the progress."
	cardType := "sentence"
	_, editOutput, err := tools.EditCard(ctx, nil, EditCardInput{
		CardID:     cardID,
		SetID:      &secondSetID,
		FrontText:  &frontText,
		AnswerText: &answerText,
		CardType:   &cardType,
		GrammarPhrases: []GrammarPhrase{
			{Text: "check on", Note: "ask about progress"},
		},
	})
	if err != nil {
		t.Fatalf("EditCard error: %v", err)
	}
	if editOutput.Status != "updated" || editOutput.Card.CardID != cardID || editOutput.Card.SetID != secondSetID {
		t.Fatalf("EditCard output = %+v", editOutput)
	}
	if editOutput.Card.FrontText != frontText || editOutput.Card.AnswerText != answerText {
		t.Fatalf("EditCard text = %q / %q", editOutput.Card.FrontText, editOutput.Card.AnswerText)
	}
	if len(editOutput.Card.GrammarPhrases) != 1 || editOutput.Card.GrammarPhrases[0].Text != "check on" {
		t.Fatalf("EditCard grammar = %+v", editOutput.Card.GrammarPhrases)
	}
	loaded, err := tools.loadCard(ctx, userID, cardID)
	if err != nil {
		t.Fatalf("load edited card: %v", err)
	}
	if len(loaded.AnswerTokens) == 0 || loaded.Direction == "" {
		t.Fatalf("edited card did not regenerate derived fields: direction=%q tokens=%+v", loaded.Direction, loaded.AnswerTokens)
	}

	_, originalSetCards, err := tools.GetSetCards(ctx, nil, GetSetCardsInput{SetID: setID})
	if err != nil {
		t.Fatalf("GetSetCards original set error: %v", err)
	}
	if len(originalSetCards.Cards) != 0 {
		t.Fatalf("original set still has edited card: %+v", originalSetCards.Cards)
	}

	_, deleteOutput, err := tools.DeleteCard(ctx, nil, DeleteCardInput{CardID: cardID})
	if err != nil {
		t.Fatalf("DeleteCard error: %v", err)
	}
	if deleteOutput.Status != "deleted" || deleteOutput.CardID != cardID {
		t.Fatalf("DeleteCard output = %+v", deleteOutput)
	}

	_, secondSetCards, err := tools.GetSetCards(ctx, nil, GetSetCardsInput{SetID: secondSetID})
	if err != nil {
		t.Fatalf("GetSetCards second set error: %v", err)
	}
	if len(secondSetCards.Cards) != 0 {
		t.Fatalf("deleted card still returned from GetSetCards: %+v", secondSetCards.Cards)
	}
}

func TestToolsIsolateCardsByAuthenticatedUser(t *testing.T) {
	ctx := context.Background()
	pool := testPool(t, ctx)
	tools := &Tools{pool: pool}

	userA := uuid.NewString()
	userB := uuid.NewString()
	seedUser(t, ctx, pool, userA, userA+"@example.com")
	seedUser(t, ctx, pool, userB, userB+"@example.com")

	subjectA := uuid.NewString()
	setA := uuid.NewString()
	subjectB := uuid.NewString()
	setB := uuid.NewString()
	seedSubjectAndSetForUser(t, ctx, pool, userA, subjectA, setA)
	seedSubjectAndSetForUser(t, ctx, pool, userB, subjectB, setB)

	userACtx := context.WithValue(ctx, mcpUserIDKey{}, userA)
	_, addOutput, err := tools.AddCards(userACtx, nil, AddCardsInput{
		Cards: []AddCardInput{
			{
				SetID:      setA,
				FrontText:  "我想确认一下。",
				AnswerText: "I would like to confirm.",
			},
			{
				SetID:      setB,
				FrontText:  "cross user",
				AnswerText: "This should fail.",
			},
		},
	})
	if err != nil {
		t.Fatalf("AddCards error: %v", err)
	}
	if addOutput.CreatedCount != 1 || addOutput.FailedCount != 1 {
		t.Fatalf("AddCards counts = created %d failed %d, want 1/1", addOutput.CreatedCount, addOutput.FailedCount)
	}

	userBSubjects := mustGetSubjectsSets(t, tools, context.WithValue(ctx, mcpUserIDKey{}, userB))
	if len(userBSubjects.Subjects) != 1 || userBSubjects.Subjects[0].SubjectID != subjectB {
		t.Fatalf("user B subjects leaked or missing: %+v", userBSubjects.Subjects)
	}

	if _, _, err := tools.DeleteCard(context.WithValue(ctx, mcpUserIDKey{}, userB), nil, DeleteCardInput{CardID: addOutput.Created[0].CardID}); err == nil {
		t.Fatal("user B deleted user A card, want card not found")
	}
	if _, _, err := tools.EditCard(context.WithValue(ctx, mcpUserIDKey{}, userB), nil, EditCardInput{CardID: addOutput.Created[0].CardID}); err == nil {
		t.Fatal("user B edited user A card, want card not found")
	}
	if _, _, err := tools.GetSetCards(context.WithValue(ctx, mcpUserIDKey{}, userB), nil, GetSetCardsInput{SetID: setA}); err == nil {
		t.Fatal("user B listed user A set cards, want set not found")
	}
}

func testPool(t *testing.T, ctx context.Context) *pgxpool.Pool {
	t.Helper()

	pool, err := db.Open(ctx, "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable")
	if err != nil {
		t.Skipf("database unavailable: %v", err)
	}
	t.Cleanup(pool.Close)

	if err := db.SetupTestSchema(ctx, pool); err != nil {
		t.Fatalf("setup test schema: %v", err)
	}
	return pool
}

func seedUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, userID string, email string) {
	t.Helper()

	_, err := pool.Exec(ctx, `
		INSERT INTO users (id, email, name, deleted_at, updated_at)
		VALUES ($1, $2, $3, NULL, now())
		ON CONFLICT (id) DO UPDATE
		SET email = EXCLUDED.email,
		    name = EXCLUDED.name,
		    deleted_at = NULL,
		    updated_at = now()
	`, userID, email, email)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
}

func seedSubjectAndSetForUser(t *testing.T, ctx context.Context, pool *pgxpool.Pool, userID string, subjectID string, setID string) {
	t.Helper()

	// 名称按 subjectID 派生。此前固定用 "MCP Smoke Subject" 配随机 subjectID，
	// ON CONFLICT (id) 挡不住 UNIQUE(user_id, name)，导致测试跑第二次必然
	// 因上一次的残留而失败。
	subjectName := "MCP Smoke Subject " + subjectID[:8]
	_, err := pool.Exec(ctx, `
		INSERT INTO subjects (id, user_id, name, deleted_at, updated_at)
		VALUES ($1, $2, $3, NULL, now())
		ON CONFLICT (id) DO UPDATE
		SET name = EXCLUDED.name,
		    deleted_at = NULL,
		    updated_at = now()
	`, subjectID, userID, subjectName)
	if err != nil {
		t.Fatalf("seed subject: %v", err)
	}

	_, err = pool.Exec(ctx, `
		INSERT INTO sets (id, user_id, subject_id, name, deleted_at, updated_at)
		VALUES ($1, $2, $3, $4, NULL, now())
		ON CONFLICT (id) DO UPDATE
		SET subject_id = EXCLUDED.subject_id,
		    name = EXCLUDED.name,
		    deleted_at = NULL,
		    updated_at = now()
	`, setID, userID, subjectID, "MCP Smoke Set "+setID[:8])
	if err != nil {
		t.Fatalf("seed set: %v", err)
	}
}

func mustGetSubjectsSets(t *testing.T, tools *Tools, ctx context.Context) GetSubjectsSetsOutput {
	t.Helper()

	_, output, err := tools.GetSubjectsSets(ctx, nil, EmptyInput{})
	if err != nil {
		t.Fatalf("GetSubjectsSets error: %v", err)
	}
	return output
}
