package scheduler

import (
	"reflect"
	"testing"
	"time"

	"memory-app/backend/internal/model"
)

func TestApplyAgain(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "review", Ease: 2.3, IntervalDays: 3}
	next := Apply(state, GradeAgain, now)
	if next.Status != "learning" || next.LearningStep != 0 || next.IntervalDays != 1 || next.LapseCount != 1 || !next.DueAt.Equal(now.Add(time.Minute)) {
		t.Fatalf("unexpected again state: %+v", next)
	}
}

func TestApplyHardFromNew(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "new", Ease: 2.3, IntervalDays: 0}
	next := Apply(state, GradeHard, now)
	if next.Status != "learning" || next.IntervalDays != 0 || !next.DueAt.Equal(now.Add(6*time.Minute)) {
		t.Fatalf("unexpected hard state: %+v", next)
	}
}

func TestApplyGoodFromNewMovesToSecondLearningStep(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "new", Ease: 2.3, IntervalDays: 0}
	next := Apply(state, GradeGood, now)
	if next.Status != "learning" || next.LearningStep != 1 || next.IntervalDays != 0 || !next.DueAt.Equal(now.Add(10*time.Minute)) {
		t.Fatalf("unexpected good state: %+v", next)
	}
}

func TestApplyGoodFromSecondLearningStepGraduates(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "learning", LearningStep: 1, Ease: 2.3, IntervalDays: 0}
	next := Apply(state, GradeGood, now)
	if next.Status != "review" || next.LearningStep != 0 || next.IntervalDays != 1 || !next.DueAt.Equal(now.Add(24*time.Hour)) {
		t.Fatalf("unexpected good graduate state: %+v", next)
	}
}

func TestApplyEasyFromNew(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "new", Ease: 2.3, IntervalDays: 0}
	next := Apply(state, GradeEasy, now)
	if next.Status != "review" || next.IntervalDays != 4 || !next.DueAt.Equal(now.AddDate(0, 0, 4)) {
		t.Fatalf("unexpected easy state: %+v", next)
	}
}

func TestApplyHardFromReviewCompletesReview(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "review", Ease: 2.3, IntervalDays: 5}
	next := Apply(state, GradeHard, now)
	if next.Status != "review" || next.IntervalDays != 6 || !next.DueAt.Equal(now.AddDate(0, 0, 6)) {
		t.Fatalf("unexpected hard review state: %+v", next)
	}
}

func TestPreviewUsesApplyIntervals(t *testing.T) {
	now := time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)
	state := model.ReviewState{Status: "new", Ease: 2.3, IntervalDays: 0}
	previews := Preview(state, now)
	if len(previews) != len(Grades) {
		t.Fatalf("expected %d previews, got %d", len(Grades), len(previews))
	}

	for index, grade := range Grades {
		preview := previews[index]
		if preview.Grade != grade {
			t.Fatalf("preview %d grade = %q, want %q", index, preview.Grade, grade)
		}
		expectedNext := Apply(state, grade, now)
		if !reflect.DeepEqual(preview.Next, expectedNext) {
			t.Fatalf("preview %s next mismatch: %+v != %+v", grade, preview.Next, expectedNext)
		}
		expectedSeconds := int(expectedNext.DueAt.Sub(now).Seconds())
		if preview.IntervalSeconds != expectedSeconds {
			t.Fatalf("preview %s seconds = %d, want %d", grade, preview.IntervalSeconds, expectedSeconds)
		}
	}
}
