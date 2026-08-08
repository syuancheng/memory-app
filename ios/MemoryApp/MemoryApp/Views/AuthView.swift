import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: AuthSessionStore

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppSurface.muted)

                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)
                            .authFieldStyle()
                    }

                    if codeSent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Verification code")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppSurface.muted)

                            TextField("6-digit code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .authFieldStyle()
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(codeSent ? "Sign in" : "Send code")
                        }
                    }
                    .buttonStyle(AuthPrimaryButtonStyle())
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.55 : 1)

                    if codeSent {
                        Button {
                            Task { await sendCode() }
                        } label: {
                            Text("Send a new code")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppSurface.accent)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isSubmitting)
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppSurface.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppSurface.coral)
                            .frame(maxWidth: .infinity, alignment: .center)
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

    private var isDisabled: Bool {
        isSubmitting ||
            email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (codeSent && code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func submit() async {
        if codeSent {
            await verifyCode()
        } else {
            await sendCode()
        }
    }

    private func sendCode() async {
        isSubmitting = true
        errorMessage = nil
        message = nil
        do {
            try await session.requestLoginCode(email: email)
            codeSent = true
            message = "Code sent. Check your email."
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func verifyCode() async {
        isSubmitting = true
        errorMessage = nil
        message = nil
        do {
            try await session.verifyLoginCode(email: email, code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

private extension View {
    func authFieldStyle() -> some View {
        self
            .font(.system(size: 16, weight: .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(AppSurface.cardSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppSurface.line, lineWidth: 1)
            )
    }
}

private struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(AppSurface.dark)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
