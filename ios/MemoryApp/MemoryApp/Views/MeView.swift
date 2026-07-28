import SwiftUI

struct MeView: View {
    let onClose: () -> Void

    @State private var summary: MeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage(Theme.storageKey) private var selectedTheme = AppThemeChoice.forest.rawValue

    var body: some View {
        ZStack {
            ScreenBackground()

            VStack(spacing: 0) {
                header

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let summary {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            profileCard(summary)
                            settingsCard
                            statsGrid(summary)
                            activityCard(summary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                } else {
                    Spacer()
                    emptyState
                    Spacer()
                }
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(AppFont.regular(13))
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .background(Theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding()
                }
            }
        }
        .task {
            await loadSummary()
        }
    }

    private var header: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.green)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.58))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Me")
                .font(AppFont.medium(18))
                .foregroundStyle(Theme.text)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func profileCard(_ summary: MeSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(initial(summary.user.name))
                    .font(AppFont.medium(28))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(
                            colors: [Theme.green, Theme.green2],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Theme.green.opacity(0.24), radius: 24, y: 10)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.user.name)
                        .font(AppFont.medium(23))
                        .foregroundStyle(Theme.text)
                    Text(summary.user.email)
                        .font(AppFont.regular(13))
                        .foregroundStyle(Theme.muted)
                    Text("\(summary.totalReviewed) total reviews")
                        .font(AppFont.medium(12))
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.greenSoft)
                        .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(18)
        .appCard()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Settings")
                    .font(AppFont.medium(17))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "paintpalette")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.green)
            }

            VStack(spacing: 8) {
                ForEach(AppThemeChoice.allCases) { theme in
                    Button {
                        selectedTheme = theme.rawValue
                    } label: {
                        ThemeOptionRow(theme: theme, isSelected: selectedTheme == theme.rawValue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .appCard()
    }

    private func statsGrid(_ summary: MeSummary) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            StatTile(title: "Today", value: "\(summary.reviewedToday)", note: "reviewed")
            StatTile(title: "Streak", value: "\(summary.currentStreak)", note: "days")
            StatTile(title: "Due", value: "\(summary.dueCount)", note: "waiting")
            StatTile(title: "Mastered", value: "\(summary.masteredCount)", note: "done")
        }
    }

    private func activityCard(_ summary: MeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent activity")
                    .font(AppFont.medium(17))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("28 days")
                    .font(AppFont.regular(12))
                    .foregroundStyle(Theme.muted)
            }

            ActivityGrid(days: summary.recentActivity)

            HStack(spacing: 6) {
                Text("Less")
                    .font(AppFont.regular(11))
                    .foregroundStyle(Theme.muted)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(activityColor(level: level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(AppFont.regular(11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(18)
        .appCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Theme.green.opacity(0.70))
            Text("Could not load profile")
                .font(AppFont.medium(20))
                .foregroundStyle(Theme.text)
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
                .font(AppFont.regular(12))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(AppFont.medium(28))
                .foregroundStyle(Theme.text)
            Text(note)
                .font(AppFont.regular(12))
                .foregroundStyle(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.paper.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.green.opacity(0.09), lineWidth: 1)
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
                    .font(AppFont.regular(14))
                    .foregroundStyle(Theme.text)
                Text(theme.subtitle)
                    .font(AppFont.regular(11))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? Theme.green : Theme.muted.opacity(0.36))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(isSelected ? Theme.greenSoft.opacity(0.82) : Color.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Theme.green.opacity(0.16) : Theme.line.opacity(0.70), lineWidth: 1)
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

private struct ActivityGrid: View {
    let days: [ActivityDay]

    private let rows = Array(repeating: GridItem(.fixed(14), spacing: 5), count: 7)

    var body: some View {
        LazyHGrid(rows: rows, spacing: 5) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(activityColor(count: day.count))
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Theme.green.opacity(day.count == 0 ? 0.08 : 0), lineWidth: 1)
                    )
                    .accessibilityLabel("\(day.date), \(day.count) reviews")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func activityColor(count: Int) -> Color {
    switch count {
    case 0:
        return Theme.line.opacity(0.74)
    case 1:
        return Theme.greenSoft
    case 2:
        return Theme.green.opacity(0.46)
    case 3...4:
        return Theme.green.opacity(0.74)
    default:
        return Theme.green
    }
}

private func activityColor(level: Int) -> Color {
    switch level {
    case 0: return activityColor(count: 0)
    case 1: return activityColor(count: 1)
    case 2: return activityColor(count: 2)
    case 3: return activityColor(count: 3)
    default: return activityColor(count: 5)
    }
}
