package service

import (
	"strings"

	"memory-app/backend/internal/model"
)

func TokenizeAnswer(answer string) []model.AnswerToken {
	parts := strings.Fields(answer)
	tokens := make([]model.AnswerToken, 0, len(parts))
	for index, part := range parts {
		tokens = append(tokens, model.AnswerToken{Text: part, Index: index})
	}
	return tokens
}
