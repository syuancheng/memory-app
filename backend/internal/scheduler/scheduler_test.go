package scheduler

import (
	"reflect"
	"testing"
	"time"

	"github.com/open-spaced-repetition/go-fsrs/v3"

	"memory-app/backend/internal/model"
)

var testNow = time.Date(2026, 7, 28, 12, 0, 0, 0, time.UTC)

func ptrTime(t time.Time) *time.Time {
	return &t
}

func TestApplyNewAgainEntersLearningWithOneMinuteDelay(t *testing.T) {
	state := model.ReviewState{State: fsrs.New}
	next := Apply(state, GradeAgain, testNow)
	if next.State != fsrs.Learning {
		t.Fatalf("state = %v, want Learning", next.State)
	}
	if !next.DueAt.Equal(testNow.Add(time.Minute)) {
		t.Fatalf("due_at = %v, want now+1m", next.DueAt)
	}
	if next.LapseCount != 0 {
		t.Fatalf("lapse_count = %d, want 0 (failing a New card is not a lapse)", next.LapseCount)
	}
	if next.GraduatedAt != nil {
		t.Fatalf("graduated_at = %v, want nil", next.GraduatedAt)
	}
}

func TestApplyNewEasyGraduatesInstantly(t *testing.T) {
	state := model.ReviewState{State: fsrs.New}
	next := Apply(state, GradeEasy, testNow)
	if next.State != fsrs.Review {
		t.Fatalf("state = %v, want Review", next.State)
	}
	if next.ScheduledDays != 16 {
		t.Fatalf("scheduled_days = %d, want 16", next.ScheduledDays)
	}
	if next.GraduatedAt == nil || !next.GraduatedAt.Equal(testNow) {
		t.Fatalf("graduated_at = %v, want %v", next.GraduatedAt, testNow)
	}
}

func TestApplyGoodFromLearningGraduatesToReview(t *testing.T) {
	state := model.ReviewState{
		State:          fsrs.Learning,
		Stability:      1,
		Difficulty:     5,
		DueAt:          testNow,
		LastReviewedAt: ptrTime(testNow.Add(-time.Minute)),
	}
	next := Apply(state, GradeGood, testNow)
	if next.State != fsrs.Review {
		t.Fatalf("state = %v, want Review", next.State)
	}
	if next.ScheduledDays != 1 {
		t.Fatalf("scheduled_days = %d, want 1", next.ScheduledDays)
	}
	if next.GraduatedAt == nil || !next.GraduatedAt.Equal(testNow) {
		t.Fatalf("graduated_at should be set to now on first graduation, got %v", next.GraduatedAt)
	}
}

func TestApplyAgainFromReviewLapsesToRelearningAndIncrementsLapseCount(t *testing.T) {
	graduatedAt := testNow.AddDate(0, 0, -30)
	state := model.ReviewState{
		State:          fsrs.Review,
		Stability:      10,
		Difficulty:     5,
		DueAt:          testNow,
		ScheduledDays:  10,
		ReviewCount:    3,
		LastReviewedAt: ptrTime(testNow.Add(-10 * 24 * time.Hour)),
		GraduatedAt:    &graduatedAt,
	}
	next := Apply(state, GradeAgain, testNow)
	if next.State != fsrs.Relearning {
		t.Fatalf("state = %v, want Relearning", next.State)
	}
	if next.LapseCount != 1 {
		t.Fatalf("lapse_count = %d, want 1", next.LapseCount)
	}
	if !next.DueAt.Equal(testNow.Add(5 * time.Minute)) {
		t.Fatalf("due_at = %v, want now+5m", next.DueAt)
	}
	// 已经毕业过的卡再 lapse，graduated_at 不清空、不改变——一张卡毕业过就永远算毕业过。
	if next.GraduatedAt == nil || !next.GraduatedAt.Equal(graduatedAt) {
		t.Fatalf("graduated_at = %v, want unchanged %v", next.GraduatedAt, graduatedAt)
	}
}

func TestApplyGoodFromReviewExtendsInterval(t *testing.T) {
	state := model.ReviewState{
		State:          fsrs.Review,
		Stability:      10,
		Difficulty:     5,
		DueAt:          testNow,
		ScheduledDays:  10,
		ReviewCount:    3,
		LastReviewedAt: ptrTime(testNow.Add(-10 * 24 * time.Hour)),
	}
	next := Apply(state, GradeGood, testNow)
	if next.State != fsrs.Review {
		t.Fatalf("state = %v, want Review", next.State)
	}
	if next.ScheduledDays != 33 {
		t.Fatalf("scheduled_days = %d, want 33", next.ScheduledDays)
	}
	if next.LapseCount != 0 {
		t.Fatalf("lapse_count = %d, want 0", next.LapseCount)
	}
}

func TestApplyUnknownRatingIsNoop(t *testing.T) {
	state := model.ReviewState{State: fsrs.New, Stability: 1}
	next := Apply(state, "invalid", testNow)
	if !reflect.DeepEqual(next, state) {
		t.Fatalf("unknown rating should return state unchanged: %+v != %+v", next, state)
	}
}

func TestIsGrade(t *testing.T) {
	for _, g := range Grades {
		if !IsGrade(g) {
			t.Errorf("IsGrade(%q) = false, want true", g)
		}
	}
	if IsGrade("invalid") {
		t.Errorf("IsGrade(invalid) = true, want false")
	}
}

func TestPreviewMatchesApplyForEachGrade(t *testing.T) {
	state := model.ReviewState{State: fsrs.New}
	previews := Preview(state, testNow)
	if len(previews) != len(Grades) {
		t.Fatalf("expected %d previews, got %d", len(Grades), len(previews))
	}

	for index, grade := range Grades {
		preview := previews[index]
		if preview.Grade != grade {
			t.Fatalf("preview %d grade = %q, want %q", index, preview.Grade, grade)
		}
		expectedNext := Apply(state, grade, testNow)
		if !reflect.DeepEqual(preview.Next, expectedNext) {
			t.Fatalf("preview %s next mismatch: %+v != %+v", grade, preview.Next, expectedNext)
		}
		expectedSeconds := int(expectedNext.DueAt.Sub(testNow).Seconds())
		if preview.IntervalSeconds != expectedSeconds {
			t.Fatalf("preview %s seconds = %d, want %d", grade, preview.IntervalSeconds, expectedSeconds)
		}
	}
}
