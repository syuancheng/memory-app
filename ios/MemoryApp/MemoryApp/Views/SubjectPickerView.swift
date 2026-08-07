import SwiftUI

enum StudyMode: String, Hashable {
    case review
    case test

    var title: String {
        switch self {
        case .review: return "Review"
        case .test: return "Test"
        }
    }

    var actionTitle: String {
        switch self {
        case .review: return "Review"
        case .test: return "Test"
        }
    }
}

struct StudySessionConfig: Hashable {
    let mode: StudyMode
    let subject: AppSubject
    let selectedTagIDs: [String]
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
                    tagIDs: sessionConfig.selectedTagIDs
                ) {
                    dismiss()
                }
            } else {
                NavigationStack {
                    StudySelectionPage(title: mode.title, onBack: dismiss.callAsFunction) {
                        Text("Choose a subject")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppSurface.text)
                            .padding(.bottom, 18)

                        LazyVStack(spacing: 12) {
                            ForEach(subjects) { subject in
                                Button {
                                    selectedSubject = subject
                                } label: {
                                    StudySelectionRow(
                                        title: subject.name,
                                        subtitle: "\(subject.dueCount) due · \(subject.cardCount) cards",
                                        count: subject.dueCount,
                                        isSelected: false
                                    )
                                }
                                .buttonStyle(StudySelectionPressStyle())
                            }
                        }
                    }
                    .navigationDestination(item: $selectedSubject) { subject in
                        TagPickerView(subject: subject, mode: mode) { config in
                            sessionConfig = config
                        }
                    }
                }
            }
        }
    }
}

struct StudySelectionPage<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    StudySelectionHeader(title: title, onBack: onBack)
                        .padding(.bottom, 26)

                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct StudySelectionHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppSurface.text)

            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppSurface.text)
                        .frame(width: 44, height: 44)
                        .background(AppSurface.cardSubtle)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(AppSurface.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
            }
        }
        .frame(height: 44)
    }
}

struct StudySelectionRow: View {
    let title: String
    let subtitle: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppSurface.accent)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppSurface.muted)
            }

            Spacer(minLength: 12)

            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isSelected ? AppSurface.accent : AppSurface.textSecondary)
                .monospacedDigit()
                .minimumScaleFactor(0.78)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(isSelected ? AppSurface.accentSoft : AppSurface.cardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isSelected ? AppSurface.accent.opacity(0.34) : AppSurface.line, lineWidth: 1)
        )
        .shadow(color: AppSurface.shadow.opacity(isSelected ? 0.08 : 0.045), radius: 16, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct StudyPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.62))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(AppSurface.dark.opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.32))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: AppSurface.dark.opacity(isEnabled ? 0.14 : 0), radius: 18, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

struct StudySelectionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.018 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: configuration.isPressed)
    }
}
