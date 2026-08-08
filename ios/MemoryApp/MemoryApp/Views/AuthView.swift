import AuthenticationServices
import CryptoKit
import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: AuthSessionStore

    @State private var currentNonce: String?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Cardly")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(AppSurface.text)

                    Text("AI flashcards for active recall")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppSurface.muted)
                }

                VStack(alignment: .leading, spacing: 18) {
                    SignInWithAppleButton(.continue) { request in
                        let nonce = randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = sha256(nonce)
                    } onCompletion: { result in
                        handleAppleCompletion(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(isSigningIn)
                    .opacity(isSigningIn ? 0.6 : 1)

                    if isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(AppSurface.accent)
                            Text("Signing in...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppSurface.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppSurface.coral)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(22)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppSurface.line, lineWidth: 1)
                )
                .shadow(color: AppSurface.shadow.opacity(0.08), radius: 28, x: 0, y: 16)

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 24)
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Could not read Apple sign-in response."
                return
            }
            guard let nonce = currentNonce else {
                errorMessage = "Missing sign-in nonce."
                return
            }
            guard
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                errorMessage = "Missing Apple identity token."
                return
            }
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let fullName = credential.fullName.map { components in
                PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            }

            isSigningIn = true
            errorMessage = nil
            Task {
                do {
                    try await session.signInWithApple(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode,
                        nonce: nonce,
                        fullName: fullName,
                        email: credential.email
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSigningIn = false
                currentNonce = nil
            }
        case .failure(let error):
            currentNonce = nil
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    return hashedData.map { String(format: "%02x", $0) }.joined()
}

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var randoms = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
        if status != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
        }

        for random in randoms {
            if remainingLength == 0 {
                break
            }
            if Int(random) < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }

    return result
}
