package scheduler

import (
	"math"
	"time"

	"memory-app/backend/internal/model"
)

func Apply(state model.ReviewState, rating string, now time.Time) model.ReviewState {
	next := state
	next.ReviewCount++
	next.LastReviewedAt = &now

	switch rating {
	case "forgot":
		next.Status = "learning"
		next.IntervalDays = 0
		next.Ease = math.Max(1.3, state.Ease-0.2)
		next.LapseCount++
	case "fuzzy":
		next.Status = "learning"
		next.IntervalDays = 0
		next.Ease = math.Max(1.3, state.Ease-0.05)
	case "remembered":
		next.Status = "review"
		next.IntervalDays = maxInt(3, int(math.Round(float64(state.IntervalDays)*state.Ease)))
		next.Ease = math.Min(2.8, state.Ease+0.05)
	}

	next.DueAt = now.AddDate(0, 0, next.IntervalDays)
	return next
}

func maxInt(a int, b int) int {
	if a > b {
		return a
	}
	return b
}
