package scheduler

import (
	"testing"
	"time"

	"memory-app/backend/internal/model"
)

func TestApplyForgot(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Ease: 2.3}
	next := Apply(state, "forgot", now)
	if next.Status != "learning" || next.IntervalDays != 0 || next.LapseCount != 1 || !next.DueAt.Equal(now) {
		t.Fatalf("unexpected forgot state: %+v", next)
	}
}

func TestApplyFuzzyFromNew(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Ease: 2.3, IntervalDays: 0}
	next := Apply(state, "fuzzy", now)
	if next.Status != "learning" || next.IntervalDays != 0 || !next.DueAt.Equal(now) {
		t.Fatalf("unexpected fuzzy state: %+v", next)
	}
}

func TestApplyRememberedFromNew(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Ease: 2.3, IntervalDays: 0}
	next := Apply(state, "remembered", now)
	if next.Status != "review" || next.IntervalDays != 3 {
		t.Fatalf("unexpected remembered state: %+v", next)
	}
}
