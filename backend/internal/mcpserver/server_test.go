package mcpserver

import (
	"context"
	"testing"

	"memory-app/backend/internal/db"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestToolsAddAndDeleteCards(t *testing.T) {
	ctx := context.Background()
	pool := testPool(t, ctx)
	tools := &Tools{pool: pool}

	subjectID := uuid.NewString()
	setID := uuid.NewString()
	seedSubjectAndSet(t, ctx, pool, subjectID, setID)

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
				SubjectID:  subjectID,
				SetIDs:     []string{setID},
				FrontText:  "我想确认一下。",
				AnswerText: "I would like to confirm.",
				GrammarPhrases: []GrammarPhrase{
					{Text: "would like to", Note: "polite expression"},
				},
			},
			{
				SubjectID:  subjectID,
				SetIDs:     []string{"not-a-real-set"},
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

	_, deleteOutput, err := tools.DeleteCard(ctx, nil, DeleteCardInput{CardID: cardID})
	if err != nil {
		t.Fatalf("DeleteCard error: %v", err)
	}
	if deleteOutput.Status != "deleted" || deleteOutput.CardID != cardID {
		t.Fatalf("DeleteCard output = %+v", deleteOutput)
	}
}

func testPool(t *testing.T, ctx context.Context) *pgxpool.Pool {
	t.Helper()

	pool, err := db.Open(ctx, "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable")
	if err != nil {
		t.Skipf("database unavailable: %v", err)
	}
	t.Cleanup(pool.Close)

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	if err := db.EnsureDemoUser(ctx, pool); err != nil {
		t.Fatalf("ensure demo user: %v", err)
	}
	return pool
}

func seedSubjectAndSet(t *testing.T, ctx context.Context, pool *pgxpool.Pool, subjectID string, setID string) {
	t.Helper()

	_, err := pool.Exec(ctx, `
		INSERT INTO subjects (id, user_id, name, deleted_at, updated_at)
		VALUES ($1, $2, $3, NULL, now())
		ON CONFLICT (id) DO UPDATE
		SET name = EXCLUDED.name,
		    deleted_at = NULL,
		    updated_at = now()
	`, subjectID, db.DemoUserID, "MCP Smoke Subject")
	if err != nil {
		t.Fatalf("seed subject: %v", err)
	}

	_, err = pool.Exec(ctx, `
		INSERT INTO tags (id, user_id, subject_id, name, deleted_at, updated_at)
		VALUES ($1, $2, $3, $4, NULL, now())
		ON CONFLICT (id) DO UPDATE
		SET subject_id = EXCLUDED.subject_id,
		    name = EXCLUDED.name,
		    deleted_at = NULL,
		    updated_at = now()
	`, setID, db.DemoUserID, subjectID, "MCP Smoke Set")
	if err != nil {
		t.Fatalf("seed set: %v", err)
	}
}
