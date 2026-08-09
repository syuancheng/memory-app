package service

import (
	"strings"
	"unicode"

	"memory-app/backend/internal/model"
)

// 卡片类型。只有两种：单词与句子。
const (
	CardTypeWord     = "word"
	CardTypeSentence = "sentence"
)

// NormalizeCardType 收敛卡片类型，并兼容历史值。
// 早期有 speaking_expression / grammar 两种，语义上都是整句，统一并入 sentence。
func NormalizeCardType(cardType string) string {
	switch strings.TrimSpace(cardType) {
	case CardTypeWord:
		return CardTypeWord
	default:
		return CardTypeSentence
	}
}

// 卡片方向。决定正面是什么语言，也决定背面答案如何切分遮挡。
const (
	// DirectionZhToEn 正面中文提示 → 背面英文答案 + 语法短语。
	// 训练目标是「产出」：逐词遮挡英文答案，用户逐个揭示以主动回忆。
	DirectionZhToEn = "zh_to_en"
	// DirectionEnToZh 正面英文句子 → 背面中文翻译 + 句子剖析。
	// 训练目标是「理解」：翻译直接呈现，不做遮挡。
	DirectionEnToZh = "en_to_zh"
)

// NormalizeDirection 把任意输入收敛到受支持的方向，非法值回落到默认方向。
func NormalizeDirection(direction string) string {
	switch strings.TrimSpace(direction) {
	case DirectionEnToZh:
		return DirectionEnToZh
	default:
		return DirectionZhToEn
	}
}

// DetectDirection 由**正面文本**推断卡片方向，是方向的唯一权威来源。
//
// 映射本身是确定的，不需要用户选择：
//   正面含汉字 → 提示是中文，要产出英文 → zh_to_en
//   正面纯拉丁 → 句子是英文，要理解中文 → en_to_zh
//
// 由后端统一推断（而非客户端传入），可以杜绝「正面是中文但 direction 标成 en_to_zh」
// 这类自相矛盾的数据；API 与 MCP 两条写入路径共用此函数。
func DetectDirection(frontText string) string {
	if containsHan(frontText) {
		return DirectionZhToEn
	}
	return DirectionEnToZh
}

func containsHan(text string) bool {
	for _, r := range text {
		if unicode.Is(unicode.Han, r) {
			return true
		}
	}
	return false
}

// TokenizeAnswer 按方向切分背面答案。
//
// zh_to_en：答案是英文，按空白切成词，逐词遮挡。
// en_to_zh：答案是中文，前端不遮挡、直接呈现，故不需要切分。
//
//	仍返回整句作为单个 token，是为了让 answer_tokens 与 answer_text 保持一致
//	（复习提交时的 total_tokens_count 有值），而不是为了遮挡。
//	注意不能按空白切：中文没有词间空格，切出来只会是一个覆盖整句的巨大 token。
func TokenizeAnswer(answer string, direction string) []model.AnswerToken {
	trimmed := strings.TrimSpace(answer)
	if trimmed == "" {
		return []model.AnswerToken{}
	}

	if NormalizeDirection(direction) == DirectionEnToZh {
		return []model.AnswerToken{{Text: trimmed, Index: 0}}
	}

	parts := strings.Fields(trimmed)
	tokens := make([]model.AnswerToken, 0, len(parts))
	for index, part := range parts {
		tokens = append(tokens, model.AnswerToken{Text: part, Index: index})
	}
	return tokens
}
