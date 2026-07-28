package service

import "testing"

func TestTokenizeAnswer(t *testing.T) {
	tokens := TokenizeAnswer("Any chance of getting it by tomorrow?")
	if len(tokens) != 7 {
		t.Fatalf("expected 7 tokens, got %d", len(tokens))
	}
	if tokens[6].Text != "tomorrow?" || tokens[6].Index != 6 {
		t.Fatalf("unexpected last token: %+v", tokens[6])
	}
}
