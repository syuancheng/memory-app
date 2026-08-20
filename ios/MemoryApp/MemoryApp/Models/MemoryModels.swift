import Foundation

struct AppSubject: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let cardCount: Int
    let dueCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cardCount = "card_count"
        case dueCount = "due_count"
    }
}

struct AppSet: Identifiable, Codable, Hashable {
    let id: String
    let subjectID: String
    let name: String
    let cardCount: Int
    let dueCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case subjectID = "subject_id"
        case name
        case cardCount = "card_count"
        case dueCount = "due_count"
    }
}

struct GrammarPhrase: Identifiable, Codable, Hashable {
    var id: String { "\(text)-\(note)" }
    let text: String
    let note: String
}

struct AnswerToken: Identifiable, Codable, Hashable {
    var id: Int { index }
    let text: String
    let index: Int
}

/// 卡片方向。**唯一作用是决定背面答案要不要遮挡**，除此之外两种卡完全一样。
/// 方向不由用户选择，由正面文本自动识别（与后端 service.DetectDirection 同规则）。
enum CardDirection: String, Hashable {
    /// 正面中文提示 → 背面英文答案，逐词遮挡（练产出）
    case zhToEn = "zh_to_en"
    /// 正面英文句子 → 背面中文翻译，直接呈现（练理解，遮中文没有意义）
    case enToZh = "en_to_zh"

    init(rawValueOrDefault raw: String?) {
        self = CardDirection(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces)) ?? .zhToEn
    }

    /// 正面含汉字即视为中文提示
    static func detected(fromFront frontText: String) -> CardDirection {
        frontText.unicodeScalars.contains { $0.properties.isIdeographic } ? .zhToEn : .enToZh
    }

    /// 背面答案是否遮挡。这是两种方向唯一的行为差异。
    var masksAnswer: Bool { self == .zhToEn }
}

struct ReviewCard: Identifiable, Codable, Hashable {
    let id: String
    let setID: String
    let subjectID: String
    let subjectName: String?
    let set: AppSet
    let cardType: String
    let direction: String
    let frontText: String
    let answerText: String
    let grammarPhrases: [GrammarPhrase]
    let answerTokens: [AnswerToken]
    let createdAt: String
    let updatedAt: String

    /// 解析后的方向；未知值回落 zh_to_en，与后端 NormalizeDirection 行为一致
    var cardDirection: CardDirection { CardDirection(rawValueOrDefault: direction) }

    /// 这张卡里真正的英语句子：zh_to_en 藏在背面答案，en_to_zh 就在正面。
    var englishSentence: String {
        cardDirection == .enToZh ? frontText : answerText
    }

    enum CodingKeys: String, CodingKey {
        case id
        case setID = "set_id"
        case subjectID = "subject_id"
        case subjectName = "subject_name"
        case set
        case cardType = "card_type"
        case direction
        case frontText = "front_text"
        case answerText = "answer_text"
        case grammarPhrases = "grammar_phrases"
        case answerTokens = "answer_tokens"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CardPayload: Encodable {
    let setID: String
    let cardType: String
    let direction: String
    let frontText: String
    let answerText: String
    let grammarPhrases: [GrammarPhrasePayload]

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case cardType = "card_type"
        case direction
        case frontText = "front_text"
        case answerText = "answer_text"
        case grammarPhrases = "grammar_phrases"
    }
}

struct GrammarPhrasePayload: Encodable, Hashable {
    var text: String
    var note: String
}

struct ReviewState: Codable {
    let cardID: String
    let state: Int
    let stability: Double
    let difficulty: Double
    let dueAt: String
    let scheduledDays: Int
    let elapsedDays: Int
    let reviewCount: Int
    let lapseCount: Int
    let lastReviewedAt: String?
    let graduatedAt: String?
    let masteredAt: String?

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case state
        case stability
        case difficulty
        case dueAt = "due_at"
        case scheduledDays = "scheduled_days"
        case elapsedDays = "elapsed_days"
        case reviewCount = "review_count"
        case lapseCount = "lapse_count"
        case lastReviewedAt = "last_reviewed_at"
        case graduatedAt = "graduated_at"
        case masteredAt = "mastered_at"
    }
}

enum DailyLimitMode: String, CaseIterable, Codable, Identifiable {
    case newPlusReview = "new_plus_review"
    case fixedTotal = "fixed_total"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newPlusReview:
            return "New + Review"
        case .fixedTotal:
            return "Fixed Total"
        }
    }
}

struct LearningPreferences: Codable, Hashable {
    var limitMode: DailyLimitMode
    var newCardsPerDay: Int
    var totalCardsPerDay: Int
    var dailyReminderEnabled: Bool
    var dailyReminderTime: String
    let defaultReviewMode: String
    let defaultCardDirection: String

    enum CodingKeys: String, CodingKey {
        case limitMode = "limit_mode"
        case newCardsPerDay = "new_cards_per_day"
        case totalCardsPerDay = "total_cards_per_day"
        case dailyReminderEnabled = "daily_reminder_enabled"
        case dailyReminderTime = "daily_reminder_time"
        case defaultReviewMode = "default_review_mode"
        case defaultCardDirection = "default_card_direction"
    }
}

struct LearningPreferencesPayload: Encodable {
    let limitMode: String
    let newCardsPerDay: Int
    let totalCardsPerDay: Int
    let dailyReminderEnabled: Bool
    let dailyReminderTime: String

    enum CodingKeys: String, CodingKey {
        case limitMode = "limit_mode"
        case newCardsPerDay = "new_cards_per_day"
        case totalCardsPerDay = "total_cards_per_day"
        case dailyReminderEnabled = "daily_reminder_enabled"
        case dailyReminderTime = "daily_reminder_time"
    }
}

struct ReviewSessionPayload: Codable, Hashable {
    let remainingCount: Int
    let cards: [ReviewCard]
    let nextAvailableAt: String?

    enum CodingKeys: String, CodingKey {
        case remainingCount = "remaining_count"
        case cards
        case nextAvailableAt = "next_available_at"
    }
}

struct ReviewGradePreview: Identifiable, Codable, Hashable {
    var id: Rating { grade }
    let grade: Rating
    let intervalSeconds: Int
    let dueAt: String

    enum CodingKeys: String, CodingKey {
        case grade
        case intervalSeconds = "interval_seconds"
        case dueAt = "due_at"
    }
}

/// MCP 个人访问令牌。`token` 明文**只在创建时返回一次**，之后服务端只存哈希、不可恢复。
struct MCPToken: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let createdAt: String
    let lastUsedAt: String?
    /// 仅创建接口返回；列表接口为 nil
    let token: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case token
    }
}

struct MeSummary: Codable {
    let user: MeUser
    let totalCards: Int
    let dueCount: Int
    let newCount: Int
    let reviewDueCount: Int
    let newLearnedToday: Int
    /// 今天还剩多少张新卡要学——已经把每日目标、已毕业数量都算进去了，
    /// 跟后端 computeRemainingToday 是同一份口径，客户端不再自己重算。
    let newRemainingToday: Int
    /// 今天还剩多少张复习——new_plus_review 模式下等于 reviewDueCount，
    /// fixed_total 模式下会被每日总量上限截断。
    let reviewRemainingToday: Int
    /// 今天是否已经打卡；只有 newRemainingToday==0 && reviewRemainingToday==0
    /// 时后端才会接受打卡请求。
    let checkedInToday: Bool
    let masteredCount: Int
    let reviewedToday: Int
    let totalReviewed: Int
    let currentStreak: Int
    let recentActivity: [ActivityDay]

    enum CodingKeys: String, CodingKey {
        case user
        case totalCards = "total_cards"
        case dueCount = "due_count"
        case newCount = "new_count"
        case reviewDueCount = "review_due_count"
        case newLearnedToday = "new_learned_today"
        case newRemainingToday = "new_remaining_today"
        case reviewRemainingToday = "review_remaining_today"
        case checkedInToday = "checked_in_today"
        case masteredCount = "mastered_count"
        case reviewedToday = "reviewed_today"
        case totalReviewed = "total_reviewed"
        case currentStreak = "current_streak"
        case recentActivity = "recent_activity"
    }

    // 服务端还没上线 new_count/review_due_count 之前，旧响应里没有这两个键——
    // 用 dueCount（旧的「新+复习」合并口径）兜底 reviewDueCount，newCount 兜 0，
    // 保持和这次拆分之前完全一样的行为，而不是直接解码失败。同理，打卡功能上线
    // 之前的旧响应也没有 remaining/checked_in 这三个键，兜底成「无剩余、未打卡」。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decode(MeUser.self, forKey: .user)
        totalCards = try c.decode(Int.self, forKey: .totalCards)
        dueCount = try c.decode(Int.self, forKey: .dueCount)
        newCount = try c.decodeIfPresent(Int.self, forKey: .newCount) ?? 0
        reviewDueCount = try c.decodeIfPresent(Int.self, forKey: .reviewDueCount) ?? dueCount
        newLearnedToday = try c.decodeIfPresent(Int.self, forKey: .newLearnedToday) ?? 0
        newRemainingToday = try c.decodeIfPresent(Int.self, forKey: .newRemainingToday) ?? 0
        reviewRemainingToday = try c.decodeIfPresent(Int.self, forKey: .reviewRemainingToday) ?? 0
        checkedInToday = try c.decodeIfPresent(Bool.self, forKey: .checkedInToday) ?? false
        masteredCount = try c.decode(Int.self, forKey: .masteredCount)
        reviewedToday = try c.decode(Int.self, forKey: .reviewedToday)
        totalReviewed = try c.decode(Int.self, forKey: .totalReviewed)
        currentStreak = try c.decode(Int.self, forKey: .currentStreak)
        recentActivity = try c.decode([ActivityDay].self, forKey: .recentActivity)
    }
}

struct MeUser: Codable, Hashable {
    let id: String?
    let name: String
    let email: String
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case provider
    }
}

struct AuthResponse: Codable, Hashable {
    let user: MeUser
    let sessionToken: String?
    /// 本次验证码登录顺带创建了账号 —— 客户端据此引导设置密码。
    let isNewUser: Bool
    /// 该账号是否已设过密码，决定是否展示「用密码登录」入口。
    let hasPassword: Bool

    enum CodingKeys: String, CodingKey {
        case user
        case sessionToken = "session_token"
        case isNewUser = "is_new_user"
        case hasPassword = "has_password"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decode(MeUser.self, forKey: .user)
        sessionToken = try c.decodeIfPresent(String.self, forKey: .sessionToken)
        // 两个字段是后加的；缺失时按「老账号、无密码」处理，
        // 避免旧后端或 PATCH /account 这类不返回它们的响应解码失败。
        isNewUser = try c.decodeIfPresent(Bool.self, forKey: .isNewUser) ?? false
        hasPassword = try c.decodeIfPresent(Bool.self, forKey: .hasPassword) ?? false
    }
}

struct ActivityDay: Identifiable, Codable, Hashable {
    var id: String { date }
    let date: String
    let count: Int
}

enum Rating: String, CaseIterable, Codable, Hashable {
    case again
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}
