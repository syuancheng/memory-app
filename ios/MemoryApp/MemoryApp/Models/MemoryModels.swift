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

struct CardPayload: Encodable {
    let subjectID: String
    let tagIDs: [String]
    let cardType: String
    let direction: String
    let frontText: String
    let answerText: String
    let grammarPhrases: [GrammarPhrasePayload]

    enum CodingKeys: String, CodingKey {
        case subjectID = "subject_id"
        case tagIDs = "tag_ids"
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

    enum CodingKeys: String, CodingKey {
        case user
        case sessionToken = "session_token"
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
