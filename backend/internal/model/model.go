package model

import (
	"encoding/json"
	"time"
)

type Subject struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CardCount int    `json:"card_count"`
	DueCount  int    `json:"due_count"`
}

type Set struct {
	ID        string `json:"id"`
	SubjectID string `json:"subject_id"`
	Name      string `json:"name"`
	CardCount int    `json:"card_count"`
	DueCount  int    `json:"due_count"`
}

type GrammarPhrase struct {
	Text string `json:"text"`
	Note string `json:"note"`
}

type AnswerToken struct {
	Text  string `json:"text"`
	Index int    `json:"index"`
}

type Card struct {
	ID             string          `json:"id"`
	SetID          string          `json:"set_id"`
	SubjectID      string          `json:"subject_id"`
	SubjectName    string          `json:"subject_name,omitempty"`
	Set            Set             `json:"set"`
	CardType       string          `json:"card_type"`
	Direction      string          `json:"direction"`
	FrontText      string          `json:"front_text"`
	AnswerText     string          `json:"answer_text"`
	GrammarPhrases []GrammarPhrase `json:"grammar_phrases"`
	AnswerTokens   []AnswerToken   `json:"answer_tokens"`
	CreatedAt      time.Time       `json:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at"`
}

type ReviewState struct {
	CardID         string     `json:"card_id"`
	Status         string     `json:"status"`
	LearningStep   int        `json:"learning_step"`
	Ease           float64    `json:"ease"`
	IntervalDays   int        `json:"interval_days"`
	DueAt          time.Time  `json:"due_at"`
	ReviewCount    int        `json:"review_count"`
	LapseCount     int        `json:"lapse_count"`
	LastReviewedAt *time.Time `json:"last_reviewed_at,omitempty"`
	MasteredAt     *time.Time `json:"mastered_at,omitempty"`
}

func GrammarJSON(phrases []GrammarPhrase) ([]byte, error) {
	if phrases == nil {
		phrases = []GrammarPhrase{}
	}
	return json.Marshal(phrases)
}

func TokensJSON(tokens []AnswerToken) ([]byte, error) {
	if tokens == nil {
		tokens = []AnswerToken{}
	}
	return json.Marshal(tokens)
}
