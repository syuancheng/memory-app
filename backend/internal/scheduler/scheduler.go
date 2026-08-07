package scheduler

import (
	"math"
	"time"

	"memory-app/backend/internal/model"
)

const (
	GradeAgain = "again"
	GradeHard  = "hard"
	GradeGood  = "good"
	GradeEasy  = "easy"
)

var Grades = []string{GradeAgain, GradeHard, GradeGood, GradeEasy}

type GradePreview struct {
	Grade           string
	Next            model.ReviewState
	IntervalSeconds int
}

func Preview(state model.ReviewState, now time.Time) []GradePreview {
	previews := make([]GradePreview, 0, len(Grades))
	for _, grade := range Grades {
		next := Apply(state, grade, now)
		seconds := int(math.Ceil(next.DueAt.Sub(now).Seconds()))
		if seconds < 0 {
			seconds = 0
		}
		previews = append(previews, GradePreview{
			Grade:           grade,
			Next:            next,
			IntervalSeconds: seconds,
		})
	}
	return previews
}

func IsGrade(rating string) bool {
	for _, grade := range Grades {
		if rating == grade {
			return true
		}
	}
	return false
}

func Apply(state model.ReviewState, rating string, now time.Time) model.ReviewState {
	next := state
	next.ReviewCount++
	next.LastReviewedAt = &now

	switch rating {
	case GradeAgain:
		next.Status = "learning"
		next.IntervalDays = 0
		next.Ease = math.Max(1.3, state.Ease-0.2)
		next.LapseCount++
		next.DueAt = now.Add(time.Minute)
	case GradeHard:
		next.Status = "learning"
		next.IntervalDays = 0
		next.Ease = math.Max(1.3, state.Ease-0.05)
		next.DueAt = now.Add(6 * time.Minute)
	case GradeGood:
		next.Status = "review"
		next.IntervalDays = maxInt(3, int(math.Round(float64(state.IntervalDays)*state.Ease)))
		next.Ease = math.Min(2.8, state.Ease+0.05)
		next.DueAt = now.AddDate(0, 0, next.IntervalDays)
	case GradeEasy:
		next.Status = "review"
		baseInterval := maxInt(1, state.IntervalDays)
		next.IntervalDays = maxInt(4, int(math.Round(float64(baseInterval)*(state.Ease+1.0))))
		next.Ease = math.Min(3.0, state.Ease+0.15)
		next.DueAt = now.AddDate(0, 0, next.IntervalDays)
	default:
		return state
	}
	return next
}

func maxInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}
