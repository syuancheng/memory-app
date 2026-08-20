import Foundation
import Security

enum APIError: LocalizedError {
    case badURL
    case badStatus(Int, String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid API URL"
        case .badStatus(let status, let message):
            // 后端错误体是 {"error":"..."}，直接把整段 JSON 甩给用户没有意义。
            // 能解析出 error 字段就只显示那句话，解析不了才回落到原始文本。
            if let data = message.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reason = object["error"] as? String,
               !reason.isEmpty {
                return reason
            }
            return message.isEmpty ? "Request failed (\(status))" : message
        case .unauthorized:
            return "Please sign in again."
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let rawBaseURL = ProcessInfo.processInfo.environment["MEMORY_API_BASE_URL"] ?? "https://api.siyuancheng.com/api"
        self.baseURL = URL(string: rawBaseURL)!
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func listSubjects() async throws -> [AppSubject] {
        try await request(path: "/subjects")
    }

    func requestAuthCode(email: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/auth/request-code", method: "POST", body: EmailPayload(email: email), requiresAuth: false)
    }

    func loginWithPassword(email: String, password: String) async throws -> AuthResponse {
        try await request(path: "/auth/login-password", method: "POST",
                          body: PasswordLoginPayload(email: email, password: password), requiresAuth: false)
    }

    func setPassword(_ password: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/auth/password", method: "POST",
                                                        body: SetPasswordPayload(password: password))
    }

    func requestPasswordResetCode(email: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/auth/password/reset-code", method: "POST",
                                                        body: EmailPayload(email: email), requiresAuth: false)
    }

    func resetPassword(email: String, code: String, password: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/auth/password/reset", method: "POST",
                                                        body: ResetPasswordPayload(email: email, code: code, password: password),
                                                        requiresAuth: false)
    }

    func updateDisplayName(_ name: String) async throws -> AuthResponse {
        try await request(path: "/account", method: "PATCH", body: DisplayNamePayload(displayName: name))
    }

    func verifyAuthCode(email: String, code: String) async throws -> AuthResponse {
        try await request(path: "/auth/verify-code", method: "POST", body: VerifyCodePayload(email: email, code: code), requiresAuth: false)
    }

    func signInWithApple(identityToken: String, authorizationCode: String, nonce: String, fullName: String?, email: String?) async throws -> AuthResponse {
        try await request(
            path: "/auth/apple",
            method: "POST",
            body: AppleSignInPayload(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                fullName: fullName,
                email: email
            ),
            requiresAuth: false
        )
    }

    func getCurrentUser() async throws -> AuthResponse {
        try await request(path: "/auth/me")
    }

    func logout() async throws {
        let _: ActionStatusResponse = try await request(path: "/auth/logout", method: "POST")
    }

    func requestDeleteAccountCode() async throws {
        let _: ActionStatusResponse = try await request(path: "/account/delete-code", method: "POST")
    }

    func deleteAccount(email: String, code: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/account", method: "DELETE", body: VerifyCodePayload(email: email, code: code))
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

    // MARK: MCP 个人访问令牌

    func listMCPTokens() async throws -> [MCPToken] {
        try await request(path: "/mcp/tokens")
    }

    func createMCPToken(name: String) async throws -> MCPToken {
        try await request(path: "/mcp/tokens", method: "POST", body: NamePayload(name: name))
    }

    func revokeMCPToken(tokenID: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/mcp/tokens/\(tokenID)", method: "DELETE")
    }

    func getMeSummary() async throws -> MeSummary {
        var components = URLComponents(url: baseURL.appendingPathComponent("me/summary"), resolvingAgainstBaseURL: false)
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60
        components?.queryItems = [
            URLQueryItem(name: "tz_offset_minutes", value: String(offsetMinutes))
        ]
        guard let url = components?.url else {
            throw APIError.badURL
        }
        return try await request(url: url)
    }

    func getLearningPreferences() async throws -> LearningPreferences {
        try await request(path: "/learning/preferences")
    }

    func updateLearningPreferences(_ preferences: LearningPreferencesPayload) async throws -> LearningPreferences {
        try await request(path: "/learning/preferences", method: "PATCH", body: preferences)
    }

    func listSets() async throws -> [AppSet] {
        try await request(path: "/sets")
    }

    func listSets(subjectID: String) async throws -> [AppSet] {
        try await request(path: "/subjects/\(subjectID)/sets")
    }

    func createSet(subjectID: String, name: String) async throws -> AppSet {
        try await request(path: "/subjects/\(subjectID)/sets", method: "POST", body: NamePayload(name: name))
    }

    func updateSet(subjectID: String, setID: String, name: String) async throws -> AppSet {
        try await request(path: "/subjects/\(subjectID)/sets/\(setID)", method: "PUT", body: NamePayload(name: name))
    }

    func deleteSet(subjectID: String, setID: String) async throws {
        let _: ActionStatusResponse = try await request(path: "/subjects/\(subjectID)/sets/\(setID)", method: "DELETE")
    }

    func listCards(search: String = "", subjectID: String? = nil, setIDs: [String] = []) async throws -> [ReviewCard] {
        var components = URLComponents(url: baseURL.appendingPathComponent("cards"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let subjectID, !subjectID.isEmpty {
            queryItems.append(URLQueryItem(name: "subject_id", value: subjectID))
        }
        if !setIDs.isEmpty {
            queryItems.append(URLQueryItem(name: "set_ids", value: setIDs.joined(separator: ",")))
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

    func listDueCards(subjectID: String, setIDs: [String], limit: Int = 30) async throws -> [ReviewCard] {
        var components = URLComponents(url: baseURL.appendingPathComponent("review/due"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "subject_id", value: subjectID),
            URLQueryItem(name: "set_ids", value: setIDs.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            throw APIError.badURL
        }
        return try await request(url: url)
    }

    func getReviewSession(subjectID: String, setIDs: [String], mode: StudyMode = .review) async throws -> ReviewSessionPayload {
        var components = URLComponents(url: baseURL.appendingPathComponent("review/session"), resolvingAgainstBaseURL: false)
        let offsetMinutes = TimeZone.current.secondsFromGMT() / 60
        components?.queryItems = [
            URLQueryItem(name: "subject_id", value: subjectID),
            URLQueryItem(name: "set_ids", value: setIDs.joined(separator: ",")),
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "tz_offset_minutes", value: String(offsetMinutes))
        ]
        guard let url = components?.url else {
            throw APIError.badURL
        }
        return try await request(url: url)
    }

    func getReviewPreviews(cardID: String) async throws -> [ReviewGradePreview] {
        try await request(path: "/cards/\(cardID)/review-preview")
    }

    func submitReview(card: ReviewCard, mode: StudyMode = .review, rating: Rating, revealedCount: Int, clientReviewID: String = UUID().uuidString) async throws -> ReviewState {
        try await submitReview(
            cardID: card.id,
            mode: mode.rawValue,
            rating: rating,
            revealedCount: revealedCount,
            totalTokensCount: card.answerTokens.count,
            clientReviewID: clientReviewID
        )
    }

    func submitReview(cardID: String, mode: String, rating: Rating, revealedCount: Int, totalTokensCount: Int, clientReviewID: String) async throws -> ReviewState {
        let payload = ReviewResultPayload(
            cardID: cardID,
            clientReviewID: clientReviewID,
            mode: mode,
            rating: rating.rawValue,
            revealedTokensCount: revealedCount,
            totalTokensCount: totalTokensCount
        )
        return try await request(path: "/review/result", method: "POST", body: payload)
    }

    func deleteCard(_ card: ReviewCard) async throws {
        let _: ActionStatusResponse = try await request(path: "/cards/\(card.id)", method: "DELETE")
    }

    func markCardMastered(_ card: ReviewCard) async throws {
        let _: ActionStatusResponse = try await request(path: "/cards/\(card.id)/master", method: "POST")
    }

    private func request<T: Decodable>(path: String, method: String = "GET", requiresAuth: Bool = true) async throws -> T {
        try await request(url: baseURL.appendingPathComponent(path), method: method, bodyData: nil, requiresAuth: requiresAuth)
    }

    private func request<T: Decodable, Body: Encodable>(path: String, method: String, body: Body, requiresAuth: Bool = true) async throws -> T {
        try await request(url: baseURL.appendingPathComponent(path), method: method, bodyData: encoder.encode(body), requiresAuth: requiresAuth)
    }

    private func request<T: Decodable>(url: URL, method: String = "GET", bodyData: Data? = nil, requiresAuth: Bool = true) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if requiresAuth, let token = SessionKeychainReader.readToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.badStatus(-1, "Invalid response")
        }
        if httpResponse.statusCode == 401 {
            NotificationCenter.default.post(name: AuthSessionStore.sessionDidExpire, object: nil)
            throw APIError.unauthorized
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

private struct PasswordLoginPayload: Encodable {
    let email: String
    let password: String
}

private struct SetPasswordPayload: Encodable {
    let password: String
}

private struct ResetPasswordPayload: Encodable {
    let email: String
    let code: String
    let password: String
}

private struct DisplayNamePayload: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct NamePayload: Encodable {
    let name: String
}

private struct EmailPayload: Encodable {
    let email: String
}

private struct VerifyCodePayload: Encodable {
    let email: String
    let code: String
}

private struct AppleSignInPayload: Encodable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case nonce
        case fullName = "full_name"
        case email
    }
}

private struct ReviewResultPayload: Encodable {
    let cardID: String
    let clientReviewID: String
    let mode: String
    let rating: String
    let revealedTokensCount: Int
    let totalTokensCount: Int

    enum CodingKeys: String, CodingKey {
        case cardID = "card_id"
        case clientReviewID = "client_review_id"
        case mode
        case rating
        case revealedTokensCount = "revealed_tokens_count"
        case totalTokensCount = "total_tokens_count"
    }
}

private enum SessionKeychainReader {
    static func readToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.siyuancheng.Cardly",
            kSecAttrAccount as String: "session-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
