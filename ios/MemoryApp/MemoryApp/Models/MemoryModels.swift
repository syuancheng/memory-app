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

struct AppTag: Identifiable, Codable, Hashable {
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

struct ReviewCard: Identifiable, Codable, Hashable {
    let id: String
    let subjectID: String
    let subjectName: String?
    let tags: [AppTag]
    let cardType: String
    let direction: String
    let frontText: String
    let answerText: String
    let grammarPhrases: [GrammarPhrase]
    let answerTokens: [AnswerToken]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case subjectID = "subject_id"
        case subjectName = "subject_name"
        case tags
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

struct ReviewState: Codable {
    let cardID: String
    let status: String
    let ease: Double
    let intervalDays: Int
    let dueAt: String
    let reviewCount: Int
    let lapseCount: Int

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case status
        case ease
        case intervalDays = "interval_days"
        case dueAt = "due_at"
        case reviewCount = "review_count"
        case lapseCount = "lapse_count"
    }
}

struct MeSummary: Codable {
    let user: MeUser
    let totalCards: Int
    let dueCount: Int
    let masteredCount: Int
    let reviewedToday: Int
    let totalReviewed: Int
    let currentStreak: Int
    let recentActivity: [ActivityDay]

    enum CodingKeys: String, CodingKey {
        case user
        case totalCards = "total_cards"
        case dueCount = "due_count"
        case masteredCount = "mastered_count"
        case reviewedToday = "reviewed_today"
        case totalReviewed = "total_reviewed"
        case currentStreak = "current_streak"
        case recentActivity = "recent_activity"
    }
}

struct MeUser: Codable, Hashable {
    let name: String
    let email: String
}

struct ActivityDay: Identifiable, Codable, Hashable {
    var id: String { date }
    let date: String
    let count: Int
}

enum Rating: String, CaseIterable {
    case forgot
    case fuzzy
    case remembered

    var title: String {
        switch self {
        case .forgot: return "忘了"
        case .fuzzy: return "模糊"
        case .remembered: return "记住了"
        }
    }
}
