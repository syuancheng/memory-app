import SwiftUI

/// 设置或修改密码。
///
/// 密码是可选的快捷登录方式 —— 验证码始终可用 —— 所以这一屏永远可以跳过，
/// 不存在「注册没走完」的中间状态。
struct SetPasswordView: View {
    /// 注册后主动弹出时为 true，显示「稍后再说」；从设置里进入时为 false。
    var isOnboarding: Bool = false

    @EnvironmentObject private var session: AuthSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var title: String {
        session.hasPassword ? "Change password" : "Set a password"
    }

    private var mismatch: Bool {
        !confirmation.isEmpty && confirmation != password
    }

    private var submitDisabled: Bool {
        isSubmitting || password.count < 8 || confirmation != password
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                Text(isOnboarding
                     ? "You're signed in. Add a password if you'd rather not wait for a code each time."
                     : "You can always sign in with a code instead.")
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpace.lg) {
                        AppSecureField(
                            label: "New password",
                            text: $password,
                            helper: "At least 8 characters."
                        )

                        AppSecureField(
                            label: "Confirm password",
                            text: $confirmation,
                            errorText: mismatch ? "Passwords don't match." : nil
                        )

                        AppButton(
                            title: "Save password",
                            variant: .primary,
                            size: .large,
                            fullWidth: true,
                            isEnabled: !submitDisabled,
                            isLoading: isSubmitting
                        ) {
                            Task { await save() }
                        }

                        if isOnboarding {
                            AppButton(title: "Maybe later", variant: .ghost, size: .medium, fullWidth: true) {
                                session.shouldOfferPasswordSetup = false
                                dismiss()
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .appText(AppType.label, color: AppColor.dangerText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .appNavBar(title, dismiss: .close, onDismiss: {
                if isOnboarding { session.shouldOfferPasswordSetup = false }
                dismiss()
            })
        }
        .interactiveDismissDisabled(false)
    }

    private func save() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await session.setPassword(password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
