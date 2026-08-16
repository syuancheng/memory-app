import SwiftUI

enum StudyMode: String, Hashable {
    case review
    case learn
    case test

    var title: String {
        switch self {
        case .review: return "Review"
        case .learn: return "Learn"
        case .test: return "Test"
        }
    }

    var actionTitle: String {
        switch self {
        case .review: return "Review"
        case .learn: return "Learn"
        case .test: return "Test"
        }
    }

    var subjectPrompt: String {
        switch self {
        case .review, .test:
            return "Choose a subject"
        case .learn:
            return "Choose what to learn"
        }
    }
}

extension StudyMode: Identifiable {
    var id: String { rawValue }
}

struct StudySessionConfig: Hashable {
    let mode: StudyMode
    let subject: AppSubject
    let selectedSetIDs: [String]
}

struct SubjectPickerView: View {
    let subjects: [AppSubject]
    var mode: StudyMode = .review

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubject: AppSubject?
    @State private var sessionConfig: StudySessionConfig?

    var body: some View {
        ZStack {
            if let sessionConfig {
                ReviewSessionView(
                    mode: sessionConfig.mode,
                    subject: sessionConfig.subject,
                    setIDs: sessionConfig.selectedSetIDs
                ) {
                    dismiss()
                }
            } else {
                NavigationStack {
                    // 本屏由 .fullScreenCover 呈现 → dismiss 用 .close
                    StudySelectionPage(title: mode.title, dismissStyle: .close, onBack: dismiss.callAsFunction) {
                        Text(mode.subjectPrompt)
                            .appText(AppType.title2)

                        LazyVStack(spacing: AppLayout.cardGap) {
                            ForEach(subjects) { subject in
                                Button {
                                    selectedSubject = subject
                                } label: {
                                    StudySelectionRow(
                                        title: subject.name,
                                        subtitle: mode == .learn ? "\(subject.cardCount) cards" : "\(subject.dueCount) due · \(subject.cardCount) cards",
                                        count: mode == .learn ? subject.cardCount : subject.dueCount,
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(StudySelectionPressStyle())
                            }
                        }
                    }
                    .navigationDestination(item: $selectedSubject) { subject in
                        SetPickerView(subject: subject, mode: mode) { config in
                            sessionConfig = config
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

struct StudySelectionPage<Content: View>: View {
    let title: String
    /// present 出来的屏用 .close（xmark）；push 出来的屏用 .back（系统箭头）
    var dismissStyle: AppNavDismiss = .back
    let onBack: () -> Void
    @ViewBuilder let content: Content

    // 样式 A：这两屏都是可返回的，用原生导航栏。
    // 改造前是「自绘圆形返回 + 20pt 居中标题 + 隐藏原生栏」——第三套导航的最后一处。
    var body: some View {
        AppScreen {
            content
        }
        .appNavBar(title, dismiss: dismissStyle, onDismiss: onBack)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct StudySelectionRow: View {
    let title: String
    let subtitle: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpace.md) {
            if isSelected {
                Image(systemName: AppIcon.confirm)
                    .font(AppIcon.font(AppLayout.iconSM))
                    .foregroundStyle(AppColor.onPrimary)
                    .frame(width: AppLayout.avatarSM, height: AppLayout.avatarSM)
                    .background(AppColor.primary, in: Circle())
            }

            VStack(alignment: .leading, spacing: AppSpace.xs / 2) {
                Text(title)
                    .appText(AppType.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpace.md)

            Text("\(count)")
                .appText(AppType.title2, color: isSelected ? AppColor.primaryOnSoft : AppColor.textSecondary)
                .monospacedDigit()
                .minimumScaleFactor(0.78)
                .lineLimit(1)
        }
        .padding(.horizontal, AppLayout.rowPaddingH)
        .padding(.vertical, AppLayout.rowPaddingV)
        .frame(maxWidth: .infinity, minHeight: AppLayout.rowMinHeight, alignment: .leading)
        .background(isSelected ? AppColor.primarySoft : AppColor.surface, in: AppRadius.shape(AppRadius.lg))
        .overlay {
            AppRadius.shape(AppRadius.lg).strokeBorder(
                isSelected ? AppColor.primary : AppColor.border,
                lineWidth: AppLayout.hairline
            )
        }
        .contentShape(AppRadius.shape(AppRadius.lg))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 行卡按压反馈。统一走 AppPressableStyle 的缩放曲线，不再叠 .brightness。
struct StudySelectionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AppMotion.pressScale : 1)
            .animation(AppMotion.instant, value: configuration.isPressed)
    }
}
