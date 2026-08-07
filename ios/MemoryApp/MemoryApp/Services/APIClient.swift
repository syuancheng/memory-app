import Foundation

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid API URL"
        case .badStatus(let status, let message):
            return "API error \(status): \(message)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let rawBaseURL = ProcessInfo.processInfo.environment["MEMORY_API_BASE_URL"] ?? "http://127.0.0.1:8081/api"
        self.baseURL = URL(string: rawBaseURL)!
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func listSubjects() async throws -> [AppSubject] {
        try await request(path: "/subjects")
    }

    func createSubject(name: String) async throws -> AppSubject {
        try await request(path: "/subjects", method: "POST", body: NamePayload(name: name))
    }

    func updateSubject(subjectID: String, name: String) async throws -> AppSubject {
        try await request(path: "/subjects/\(subjectID)", method: "PUT", body: NamePayload(name: name))
    }

    func deleteSubject(subjectID: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/subjects/\(subjectID)", method: "DELETE")
    }

    func getMeSummary() async throws -> MeSummary {
        try await request(path: "/me/summary")
    }

    func listTags(subjectID: String) async throws -> [AppTag] {
        try await request(path: "/subjects/\(subjectID)/tags")
    }

    func createTag(subjectID: String, name: String) async throws -> AppTag {
        try await request(path: "/subjects/\(subjectID)/tags", method: "POST", body: NamePayload(name: name))
    }

    func updateTag(subjectID: String, tagID: String, name: String) async throws -> AppTag {
        try await request(path: "/subjects/\(subjectID)/tags/\(tagID)", method: "PUT", body: NamePayload(name: name))
    }

    func deleteTag(subjectID: String, tagID: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/subjects/\(subjectID)/tags/\(tagID)", method: "DELETE")
    }

    func listCards(search: String = "", subjectID: String? = nil, tagIDs: [String] = []) async throws -> [ReviewCard] {
        var components = URLComponents(url: baseURL.appendingPathComponent("cards"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let subjectID, !subjectID.isEmpty {
            queryItems.append(URLQueryItem(name: "subject_id", value: subjectID))
        }
        if !tagIDs.isEmpty {
            queryItems.append(URLQueryItem(name: "tag_ids", value: tagIDs.joined(separator: ",")))
        }
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw APIError.badURL
        }
        return try await request(url: url)
    }

    func createCard(_ payload: CardPayload) async throws -> ReviewCard {
        try await request(path: "/cards", method: "POST", body: payload)
    }

    func updateCard(cardID: String, payload: CardPayload) async throws -> ReviewCard {
        try await request(path: "/cards/\(cardID)", method: "PUT", body: payload)
    }

    func listDueCards(subjectID: String, tagIDs: [String], limit: Int = 30) async throws -> [ReviewCard] {
        var components = URLComponents(url: baseURL.appendingPathComponent("review/due"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "subject_id", value: subjectID),
            URLQueryItem(name: "tag_ids", value: tagIDs.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            throw APIError.badURL
        }
        return try await request(url: url)
    }

    func getReviewPreviews(cardID: String) async throws -> [ReviewGradePreview] {
        try await request(path: "/cards/\(cardID)/review-preview")
    }

    func submitReview(card: ReviewCard, mode: StudyMode = .review, rating: Rating, revealedCount: Int) async throws -> ReviewState {
        let payload = ReviewResultPayload(
            cardID: card.id,
            mode: mode.rawValue,
            rating: rating.rawValue,
            revealedTokensCount: revealedCount,
            totalTokensCount: card.answerTokens.count
        )
        return try await request(path: "/review/result", method: "POST", body: payload)
    }

    func deleteCard(_ card: ReviewCard) async throws {
        let _: ActionStatusResponse = try await request(path: "/cards/\(card.id)", method: "DELETE")
    }

    func markCardMastered(_ card: ReviewCard) async throws {
        let _: ActionStatusResponse = try await request(path: "/cards/\(card.id)/master", method: "POST")
    }

    private func request<T: Decodable>(path: String, method: String = "GET") async throws -> T {
        try await request(url: baseURL.appendingPathComponent(path), method: method, bodyData: nil)
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> T {
        try await request(url: baseURL.appendingPathComponent(path), method: method, bodyData: encoder.encode(body))
    }

    private func request<T: Decodable>(url: URL, method: String = "GET", bodyData: Data? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badStatus(-1, "Invalid response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.badStatus(httpResponse.statusCode, message)
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct ActionStatusResponse: Decodable {
    let status: String
}

private struct NamePayload: Encodable {
    let name: String
}

private struct ReviewResultPayload: Encodable {
    let cardID: String
    let mode: String
    let rating: String
    let revealedTokensCount: Int
    let totalTokensCount: Int

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case mode
        case rating
        case revealedTokensCount = "revealed_tokens_count"
        case totalTokensCount = "total_tokens_count"
    }
}
