import SwiftUI

/// 登录方式。密码是可选的快捷方式，验证码始终可用 ——
/// 因此验证码是默认项，密码登录只是一个平级切换。
private enum AuthMode {
    case code
    case password
}

struct AuthView: View {
    @EnvironmentObject private var session: AuthSessionStore

    @State private var mode: AuthMode = .code
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var codeSent = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var showingForgotPassword = false

    // 与后端 auth.SendCooldown 对应。
    // 改造前没有倒计时，用户只能靠点一下撞出 400 才知道要等 —— 用报错代替提示。
    private static let resendCooldown: TimeInterval = 60

    @State private var lastSentAt: Date?
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 距离可以重发还剩几秒；0 表示现在就能发
    private var resendRemaining: Int {
        guard let lastSentAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastSentAt)
        return max(0, Int((Self.resendCooldown - elapsed).rounded(.up)))
    }

    var body: some View {
        ZStack {
            AppColor.surfaceBase
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpace.xxxl) {
                    Spacer(minLength: AppSpace.xxl)

                    VStack(alignment: .leading, spacing: AppSpace.sm) {
                        // 登录页是唯一没有其他 display 级元素的屏，品牌名占用 display。
                        Text("Cardly")
                            .appText(AppType.display)

                        Text("AI flashcards for active recall")
                            .appText(AppType.body, color: AppColor.textTertiary)
                    }

                    AppCard(padding: AppSpace.xl) {
                        VStack(alignment: .leading, spacing: AppSpace.lg) {
                            AppTextField(label: "Email", text: $email, placeholder: "")
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.emailAddress)

                            switch mode {
                            case .code:
                                codeFields
                            case .password:
                                passwordFields
                            }

                            statusText

                            modeSwitch
                        }
                    }

                    Spacer(minLength: AppSpace.giant)
                }
                .padding(.horizontal, AppLayout.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onReceive(ticker) { now = $0 }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView(initialEmail: email)
                .environmentObject(session)
        }
    }

    @ViewBuilder
    private var codeFields: some View {
        if codeSent {
            AppTextField(label: "Verification code", text: $code, placeholder: "6-digit code")
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
        }

        // 主操作 = primary 实心；禁用换实色而非 .opacity()；
        // 提交中走 loading 态而非在 label 里塞 ProgressView（尺寸不再跳动）。
        AppButton(
            title: codeSent ? "Sign in" : "Send code",
            variant: .primary,
            size: .large,
            fullWidth: true,
            isEnabled: !codeSubmitDisabled,
            isLoading: isSubmitting
        ) {
            Task { await submitCode() }
        }

        if codeSent {
            AppButton(
                title: resendRemaining > 0 ? "Send a new code in \(resendRemaining)s" : "Send a new code",
                variant: .ghost,
                size: .medium,
                fullWidth: true,
                isEnabled: !isSubmitting && resendRemaining == 0
            ) {
                Task { await sendCode() }
            }
        }
    }

    @ViewBuilder
    private var passwordFields: some View {
        AppSecureField(label: "Password", text: $password, submitLabel: .go) {
            Task { await submitPassword() }
        }

        AppButton(
            title: "Sign in",
            variant: .primary,
            size: .large,
            fullWidth: true,
            isEnabled: !passwordSubmitDisabled,
            isLoading: isSubmitting
        ) {
            Task { await submitPassword() }
        }

        AppButton(title: "Forgot password?", variant: .ghost, size: .medium, fullWidth: true) {
            showingForgotPassword = true
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorMessage {
            Text(errorMessage)
                .appText(AppType.label, color: AppColor.dangerText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let message {
            Text(message)
                .appText(AppType.label, color: AppColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var modeSwitch: some View {
        AppButton(
            title: mode == .code ? "Sign in with password" : "Sign in with a code",
            variant: .ghost,
            size: .medium,
            fullWidth: true,
            isEnabled: !isSubmitting
        ) {
            withAnimation(AppMotion.standard) {
                mode = mode == .code ? .password : .code
                errorMessage = nil
                message = nil
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var codeSubmitDisabled: Bool {
        isSubmitting || trimmedEmail.isEmpty ||
            (codeSent && code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var passwordSubmitDisabled: Bool {
        isSubmitting || trimmedEmail.isEmpty || password.isEmpty
    }

    private func submitCode() async {
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
            lastSentAt = Date()
            now = Date()
            message = "Code sent."
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
            // 新账号进入主界面后由 AppShellView 引导设置密码，
            // 这里不拦在登录页 —— 设密码是可跳过的。
            try await session.verifyLoginCode(email: email, code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func submitPassword() async {
        guard !passwordSubmitDisabled else { return }
        isSubmitting = true
        errorMessage = nil
        message = nil
        do {
            try await session.loginWithPassword(email: email, password: password)
        } catch {
            // 后端对「未注册」「密码错」「未设过密码」返回同一句话（防枚举），
            // 因此这里补一句提示，避免从没设过密码的用户卡死在这一屏。
            errorMessage = "\(error.localizedDescription)\nIf you never set a password, sign in with a code instead."
        }
        isSubmitting = false
    }
}

/// 忘记密码：邮箱 → 验证码 → 新密码。
/// 重置成功后后端会撤销全部旧 session，所以这里只关闭并提示重新登录。
struct ForgotPasswordView: View {
    let initialEmail: String

    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var codeSent = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var errorMessage: String?

    init(initialEmail: String) {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                Text("We'll email you a code, then you can choose a new password.")
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpace.lg) {
                        AppTextField(label: "Email", text: $email, placeholder: "")
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)

                        if codeSent {
                            AppTextField(label: "Verification code", text: $code, placeholder: "6-digit code")
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)

                            AppSecureField(
                                label: "New password",
                                text: $password,
                                helper: "At least 8 characters."
                            )
                        }

                        AppButton(
                            title: codeSent ? "Reset password" : "Send code",
                            variant: .primary,
                            size: .large,
                            fullWidth: true,
                            isEnabled: !submitDisabled,
                            isLoading: isSubmitting
                        ) {
                            Task { await submit() }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .appText(AppType.label, color: AppColor.dangerText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let message {
                            Text(message)
                                .appText(AppType.label, color: AppColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .appNavBar("Reset password", dismiss: .close, onDismiss: { dismiss() })
        }
    }

    private var submitDisabled: Bool {
        if isSubmitting { return true }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if codeSent {
            return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.count < 8
        }
        return false
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        message = nil
        do {
            if codeSent {
                try await session.resetPassword(email: email, code: code, password: password)
                dismiss()
            } else {
                try await session.requestPasswordResetCode(email: email)
                codeSent = true
                // 后端对未注册邮箱静默成功（防枚举），文案也不能暴露差别。
                message = "If that address has an account, a code is on its way."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
