import SwiftUI

struct MeView: View {
    var onClose: (() -> Void)?

    @State private var summary: MeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage(Theme.storageKey) private var selectedTheme = AppThemeChoice.forest.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 40)
                    } else if let summary {
                        learningStatistics(summary)
                        profileCard(summary)
                        settingsCard
                    } else {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(AppSurface.coral)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                }
                .padding(24)
            }
            .background(AppSurface.background.ignoresSafeArea())
            .navigationTitle("Me")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .task {
            await loadSummary()
        }
    }

    private func learningStatistics(_ summary: MeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Learning statistics", icon: "chart.bar.fill", tint: AppSurface.purple)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                StatTile(title: "Today", value: "\(summary.reviewedToday)", note: "reviewed")
                StatTile(title: "Due", value: "\(summary.dueCount)", note: "waiting")
                StatTile(title: "Cards", value: "\(summary.totalCards)", note: "total")
                StatTile(title: "Mastered", value: "\(summary.masteredCount)", note: "done")
            }
        }
        .padding(18)
        .appPanel()
    }

    private func profileCard(_ summary: MeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Personal profile", icon: "person.crop.circle.fill", tint: AppSurface.green)

            HStack(spacing: 14) {
                Text(initial(summary.user.name))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(AppSurface.dark)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.user.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppSurface.text)
                    Text(summary.user.email)
                        .font(.system(size: 13))
                        .foregroundStyle(AppSurface.muted)
                    Text("\(summary.totalReviewed) total reviews")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppSurface.green)
                }

                Spacer()
            }
        }
        .padding(18)
        .appPanel()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("System settings", icon: "gearshape.fill", tint: AppSurface.sky)

            ForEach(AppThemeChoice.allCases) { theme in
                Button {
                    selectedTheme = theme.rawValue
                } label: {
                    ThemeOptionRow(theme: theme, isSelected: selectedTheme == theme.rawValue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .appPanel()
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppSurface.text)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(AppSurface.accent)
            Text("Could not load profile")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppSurface.text)
            Button("Try again") {
                Task {
                    await loadSummary()
                }
            }
            .buttonStyle(CompletionButtonStyle())
            .padding(.horizontal, 34)
            .padding(.top, 8)
        }
        .padding(24)
    }

    private func loadSummary() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await APIClient.shared.getMeSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func initial(_ name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "S"
        }
        return String(first).uppercased()
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppSurface.muted)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppSurface.text)
                .monospacedDigit()
            Text(note)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppSurface.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppSurface.cardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppSurface.line, lineWidth: 1)
        )
    }
}

private struct ThemeOptionRow: View {
    let theme: AppThemeChoice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -4) {
                Circle()
                    .fill(accent)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(soft)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(warning)
                    .frame(width: 18, height: 18)
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppSurface.text)
                Text(theme.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppSurface.muted)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? AppSurface.accent : AppSurface.muted.opacity(0.36))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(isSelected ? AppSurface.accentSoft : AppSurface.cardSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? AppSurface.accent.opacity(0.14) : AppSurface.line, lineWidth: 1)
        )
    }

    private var accent: Color {
        switch theme {
        case .forest: return Color(hex: 0x2F6F5E)
        case .ink: return Color(hex: 0x315F74)
        case .plum: return Color(hex: 0x7B5267)
        }
    }

    private var soft: Color {
        switch theme {
        case .forest: return Color(hex: 0xE8F2EE)
        case .ink: return Color(hex: 0xE5F0F4)
        case .plum: return Color(hex: 0xF0E5EA)
        }
    }

    private var warning: Color {
        switch theme {
        case .forest: return Color(hex: 0xD84A3A)
        case .ink: return Color(hex: 0xB96150)
        case .plum: return Color(hex: 0xC05B4B)
        }
    }
}

private extension View {
    func appPanel() -> some View {
        self
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppSurface.line, lineWidth: 1)
            )
            .shadow(color: AppSurface.shadow.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}
