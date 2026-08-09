import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: AuthSessionStore

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var errorMessage: String?

    // 与后端 auth.SendCooldown / auth.CodeTTL 对应。
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
                        AppTextField(
                            label: "Email",
                            text: $email,
                            placeholder: ""
                        )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)

                        if codeSent {
                            AppTextField(
                                label: "Verification code",
                                text: $code,
                                placeholder: "6-digit code"
                            )
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        }

                        // 主操作 = primary 实心；禁用换实色而非 .opacity(0.55)；
                        // 提交中走 loading 态而非在 label 里塞 ProgressView（尺寸不再跳动）。
                        AppButton(
                            title: codeSent ? "Sign in" : "Send code",
                            variant: .primary,
                            size: .large,
                            fullWidth: true,
                            isEnabled: !isDisabled,
                            isLoading: isSubmitting
                        ) {
                            Task { await submit() }
                        }

                        if codeSent {
                            AppButton(
                                title: resendRemaining > 0
                                    ? "Send a new code in \(resendRemaining)s"
                                    : "Send a new code",
                                variant: .ghost,
                                size: .medium,
                                fullWidth: true,
                                isEnabled: !isSubmitting && resendRemaining == 0
                            ) {
                                Task { await sendCode() }
                            }
                        }

                        if let message {
                            Text(message)
                                .appText(AppType.label, color: AppColor.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .appText(AppType.label, color: AppColor.dangerText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }

                Spacer(minLength: AppSpace.giant)
            }
            .padding(.horizontal, AppLayout.screenMargin)
        }
        .onReceive(ticker) { now = $0 }
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
            try await session.verifyLoginCode(email: email, code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
