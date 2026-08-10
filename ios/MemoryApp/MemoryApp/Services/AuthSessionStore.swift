import Foundation
import Security

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var user: MeUser?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isCheckingSession = true
    /// 当前账号是否已设密码；决定登录页是否展示「用密码登录」，
    /// 以及 Me 页 Password 一栏显示「设置」还是「修改」。
    @Published private(set) var hasPassword = false
    /// 刚注册的账号进入主界面后提示设置密码。可跳过，跳过后不再打扰。
    @Published var shouldOfferPasswordSetup = false

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

    /// 返回本次是否顺带注册了新账号，供界面决定要不要引导设置密码。
    @discardableResult
    func verifyLoginCode(email: String, code: String) async throws -> Bool {
        let response = try await APIClient.shared.verifyAuthCode(email: email, code: code)
        try completeSignIn(response)
        shouldOfferPasswordSetup = response.isNewUser
        return response.isNewUser
    }

    func loginWithPassword(email: String, password: String) async throws {
        let response = try await APIClient.shared.loginWithPassword(email: email, password: password)
        try completeSignIn(response)
    }

    func setPassword(_ password: String) async throws {
        try await APIClient.shared.setPassword(password)
        hasPassword = true
        shouldOfferPasswordSetup = false
    }

    func requestPasswordResetCode(email: String) async throws {
        try await APIClient.shared.requestPasswordResetCode(email: email)
    }

    /// 重置成功后后端会撤销所有旧 session，因此这里不写入登录态，
    /// 界面应引导用户用新密码重新登录。
    func resetPassword(email: String, code: String, password: String) async throws {
        try await APIClient.shared.resetPassword(email: email, code: code, password: password)
    }

    func updateDisplayName(_ name: String) async throws {
        let response = try await APIClient.shared.updateDisplayName(name)
        user = response.user
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
        hasPassword = response.hasPassword
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
