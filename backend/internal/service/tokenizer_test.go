package service

import "testing"

func TestTokenizeAnswerZhToEn(t *testing.T) {
	tokens := TokenizeAnswer("Any chance of getting it by tomorrow?", DirectionZhToEn)
	if len(tokens) != 7 {
		t.Fatalf("expected 7 tokens, got %d", len(tokens))
	}
	if tokens[6].Text != "tomorrow?" || tokens[6].Index != 6 {
		t.Fatalf("unexpected last token: %+v", tokens[6])
	}
}

// 英→中：整句作为单个 token，保持 answer_tokens 与 answer_text 一致
func TestTokenizeAnswerEnToZhIsSingleBlock(t *testing.T) {
	answer := "有没有可能明天之前拿到？"
	tokens := TokenizeAnswer(answer, DirectionEnToZh)
	if len(tokens) != 1 {
		t.Fatalf("expected 1 token for en_to_zh, got %d", len(tokens))
	}
	if tokens[0].Text != answer || tokens[0].Index != 0 {
		t.Fatalf("unexpected token: %+v", tokens[0])
	}
}

// 即使中文里混有空格，也不应被切开
func TestTokenizeAnswerEnToZhKeepsSpaces(t *testing.T) {
	tokens := TokenizeAnswer("这个 可以 打包吗？", DirectionEnToZh)
	if len(tokens) != 1 {
		t.Fatalf("expected 1 token, got %d", len(tokens))
	}
}

func TestNormalizeDirection(t *testing.T) {
	cases := map[string]string{
		"":            DirectionZhToEn,
		"zh_to_en":    DirectionZhToEn,
		"en_to_zh":    DirectionEnToZh,
		"  en_to_zh ": DirectionEnToZh,
		"garbage":     DirectionZhToEn,
	}
	for in, want := range cases {
		if got := NormalizeDirection(in); got != want {
			t.Fatalf("NormalizeDirection(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestTokenizeAnswerEmpty(t *testing.T) {
	if len(TokenizeAnswer("   ", DirectionZhToEn)) != 0 {
		t.Fatal("expected no tokens for blank answer")
	}
}

func TestDetectDirection(t *testing.T) {
	cases := map[string]string{
		"有没有可能明天之前拿到？":                           DirectionZhToEn,
		"这个可以打包吗？":                               DirectionZhToEn,
		"Is there any chance we could have it?":  DirectionEnToZh,
		"The board pushed back on the proposal.": DirectionEnToZh,
		"":                                       DirectionEnToZh,
		"Deadline 是明天":                           DirectionZhToEn, // 混排只要含汉字即视为中文提示
	}
	for front, want := range cases {
		if got := DetectDirection(front); got != want {
			t.Fatalf("DetectDirection(%q) = %q, want %q", front, got, want)
		}
	}
}
