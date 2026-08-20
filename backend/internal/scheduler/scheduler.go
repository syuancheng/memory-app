package scheduler

import (
	"math"
	"time"

	"github.com/open-spaced-repetition/go-fsrs/v3"

	"memory-app/backend/internal/model"
)

const (
	GradeAgain = "again"
	GradeHard  = "hard"
	GradeGood  = "good"
	GradeEasy  = "easy"
)

var Grades = []string{GradeAgain, GradeHard, GradeGood, GradeEasy}

// engine 用库默认参数：RequestRetention=0.9，EnableShortTerm=true（新卡/学习中的卡
// 走库自带的短期步进：New 卡 Again/Hard/Good 分别是 1/5/10 分钟后再考，Easy 直接毕业；
// Learning/Relearning 状态下 Again/Hard 是 5/10 分钟后再考，Good/Easy 毕业进入 Review），
// EnableFuzz=false（不加随机扰动，间隔可预测、方便测试）。
var engine = fsrs.NewFSRS(fsrs.DefaultParam())

type GradePreview struct {
	Grade           string
	Next            model.ReviewState
	IntervalSeconds int
}

func Preview(state model.ReviewState, now time.Time) []GradePreview {
	card := toCard(state)
	log := engine.Repeat(card, now)
	previews := make([]GradePreview, 0, len(Grades))
	for _, gradeStr := range Grades {
		grade, _ := gradeFromString(gradeStr)
		info := log[grade]
		next := applyGraduation(state, toReviewState(state, info.Card))
		seconds := int(math.Ceil(next.DueAt.Sub(now).Seconds()))
		if seconds < 0 {
			seconds = 0
		}
		previews = append(previews, GradePreview{
			Grade:           gradeStr,
			Next:            next,
			IntervalSeconds: seconds,
		})
	}
	return previews
}

func IsGrade(rating string) bool {
	_, ok := gradeFromString(rating)
	return ok
}

func Apply(state model.ReviewState, rating string, now time.Time) model.ReviewState {
	grade, ok := gradeFromString(rating)
	if !ok {
		return state
	}
	info := engine.Next(toCard(state), now, grade)
	return applyGraduation(state, toReviewState(state, info.Card))
}

// applyGraduation 记录"第一次进入 Review/Relearning"的时间，只设一次，之后即使卡片
// 又回到 Learning/Relearning（lapse），也不会清空——一张卡毕业过就永远算毕业过。
func applyGraduation(previous model.ReviewState, next model.ReviewState) model.ReviewState {
	next.GraduatedAt = previous.GraduatedAt
	if next.GraduatedAt == nil && (next.State == fsrs.Review || next.State == fsrs.Relearning) {
		next.GraduatedAt = next.LastReviewedAt
	}
	return next
}

func gradeFromString(rating string) (fsrs.Rating, bool) {
	switch rating {
	case GradeAgain:
		return fsrs.Again, true
	case GradeHard:
		return fsrs.Hard, true
	case GradeGood:
		return fsrs.Good, true
	case GradeEasy:
		return fsrs.Easy, true
	}
	return 0, false
}

func toCard(state model.ReviewState) fsrs.Card {
	lastReview := time.Time{}
	if state.LastReviewedAt != nil {
		lastReview = *state.LastReviewedAt
	}
	return fsrs.Card{
		Due:           state.DueAt,
		Stability:     state.Stability,
		Difficulty:    state.Difficulty,
		ElapsedDays:   uint64(state.ElapsedDays),
		ScheduledDays: uint64(state.ScheduledDays),
		Reps:          uint64(state.ReviewCount),
		Lapses:        uint64(state.LapseCount),
		State:         state.State,
		LastReview:    lastReview,
	}
}

func toReviewState(previous model.ReviewState, card fsrs.Card) model.ReviewState {
	lastReview := card.LastReview
	return model.ReviewState{
		CardID:         previous.CardID,
		State:          card.State,
		Stability:      card.Stability,
		Difficulty:     card.Difficulty,
		DueAt:          card.Due,
		ScheduledDays:  int(card.ScheduledDays),
		ElapsedDays:    int(card.ElapsedDays),
		ReviewCount:    int(card.Reps),
		LapseCount:     int(card.Lapses),
		LastReviewedAt: &lastReview,
		MasteredAt:     previous.MasteredAt,
	}
}
