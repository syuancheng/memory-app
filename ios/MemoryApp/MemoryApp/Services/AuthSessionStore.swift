import Foundation
import Security

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var user: MeUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isCheckingSession = true

    nonisolated static let sessionDidExpire = Notification.Name("AuthSessionDidExpire")

    private let keychain = SessionKeychain()
    private var expirationObserver: NSObjectProtocol?

    init() {
        expirationObserver = NotificationCenter.default.addObserver(
            forName: Self.sessionDidExpire,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearLocalSession()
            }
        }
    }

    deinit {
        if let expirationObserver {
            NotificationCenter.default.removeObserver(expirationObserver)
        }
    }

    var sessionToken: String? {
        keychain.readToken()
    }

    func restoreSession() async {
        guard sessionToken != nil else {
            clearLocalSession()
            isCheckingSession = false
            return
        }

        do {
            let response = try await APIClient.shared.getCurrentUser()
            user = response.user
            isAuthenticated = true
        } catch {
            clearLocalSession()
        }
        isCheckingSession = false
    }

    func requestLoginCode(email: String) async throws {
        try await APIClient.shared.requestAuthCode(email: email)
    }

    func verifyLoginCode(email: String, code: String) async throws {
        let response = try await APIClient.shared.verifyAuthCode(email: email, code: code)
        try completeSignIn(response)
    }

    func signInWithApple(identityToken: String, authorizationCode: String, nonce: String, fullName: String?, email: String?) async throws {
        let response = try await APIClient.shared.signInWithApple(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: nonce,
            fullName: fullName,
            email: email
        )
        try completeSignIn(response)
    }

    private func completeSignIn(_ response: AuthResponse) throws {
        guard let token = response.sessionToken, !token.isEmpty else {
            throw APIError.badStatus(-1, "Missing session token")
        }
        try keychain.saveToken(token)
        user = response.user
        isAuthenticated = true
    }

    func logout() async {
        do {
            try await APIClient.shared.logout()
        } catch {
            // Local logout should still complete if the server is unreachable.
        }
        clearLocalSession()
    }

    func requestDeleteAccountCode() async throws {
        try await APIClient.shared.requestDeleteAccountCode()
    }

    func deleteAccount(email: String, code: String) async throws {
        try await APIClient.shared.deleteAccount(email: email, code: code)
        clearLocalSession()
    }

    private func clearLocalSession() {
        keychain.deleteToken()
        user = nil
        isAuthenticated = false
    }
}

private final class SessionKeychain {
    private let service = "com.siyuancheng.Cardly"
    private let account = "session-token"

    func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updateStatus != errSecSuccess {
                throw APIError.badStatus(Int(updateStatus), "Could not update session token")
            }
            return
        }
        if status != errSecSuccess {
            throw APIError.badStatus(Int(status), "Could not save session token")
        }
    }

    func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
