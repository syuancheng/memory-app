import SwiftUI

struct MeView: View {
    var onClose: (() -> Void)?

    @State private var summary: MeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppSurface.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        userHeader
                        achievementsSection
                        profileSection
                        settingsSection
                        loadState
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .navigationDestination(for: MeDestination.self) { destination in
                switch destination {
                case .achievements:
                    MonthlyAchievementsPage(summary: summary)
                case .account:
                    AccountPage(summary: summary)
                case .connectedAccounts:
                    ConnectedAccountsPage()
                case .learningPreferences:
                    LearningPreferencesPage()
                case .notifications:
                    NotificationsPage()
                case .appearance:
                    AppearancePage()
                case .privacyData:
                    PrivacyDataPage()
                case .about:
                    AboutPage()
                case .accountEdit(let kind):
                    AccountEditPlaceholderPage(kind: kind)
                case .document(let document):
                    LocalDocumentPage(document: document)
                }
            }
        }
        .task {
            await loadSummary()
        }
    }

    private var userHeader: some View {
        HStack(spacing: 16) {
            Text(initial(profileName))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(AppSurface.dark)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: 3)
                )
                .shadow(color: AppSurface.shadow.opacity(0.08), radius: 18, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 5) {
                Text(profileName)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                Text(profileEmail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppSurface.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                Spacer()

                NavigationLink(value: MeDestination.achievements) {
                    Text("View all")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppSurface.accent)
                }
                .buttonStyle(.plain)
            }

            ActivityCalendarPreview(records: activityRecords)
        }
    }

    private var profileSection: some View {
        MeGroupedSection(title: "Profile") {
            NavigationLink(value: MeDestination.account) {
                MeSettingsRow(title: "Account")
            }
            .buttonStyle(.plain)

            MeSeparator()

            NavigationLink(value: MeDestination.connectedAccounts) {
                MeSettingsRow(title: "Connected Accounts")
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsSection: some View {
        MeGroupedSection(title: "Settings") {
            NavigationLink(value: MeDestination.learningPreferences) {
                MeSettingsRow(title: "Learning Preferences")
            }
            .buttonStyle(.plain)

            MeSeparator()

            NavigationLink(value: MeDestination.notifications) {
                MeSettingsRow(title: "Notifications")
            }
            .buttonStyle(.plain)

            MeSeparator()

            NavigationLink(value: MeDestination.appearance) {
                MeSettingsRow(title: "Appearance")
            }
            .buttonStyle(.plain)

            MeSeparator()

            NavigationLink(value: MeDestination.privacyData) {
                MeSettingsRow(title: "Privacy & Data")
            }
            .buttonStyle(.plain)

            MeSeparator()

            NavigationLink(value: MeDestination.about) {
                MeSettingsRow(title: "About")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var loadState: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.top, 4)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(AppSurface.coral)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private var profileName: String {
        let name = summary?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Demo User" : name
    }

    private var profileEmail: String {
        let email = summary?.user.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "demo@example.com" : email
    }

    private var activityRecords: [DailyLearningRecord] {
        makeActivityRecords(from: summary)
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
            return "D"
        }
        return String(first).uppercased()
    }
}

private struct MonthlyAchievementsPage: View {
    let summary: MeSummary?
    @State private var selectedRecord: DailyLearningRecord?

    private var records: [DailyLearningRecord] {
        makeActivityRecords(from: summary)
    }

    private var currentStreak: Int {
        streakCount(records: records)
    }

    private var totalLearningDays: Int {
        records.filter { $0.hasLearning }.count
    }

    var body: some View {
        MePageScaffold(title: "Achievements") {
            VStack(alignment: .leading, spacing: 18) {
                MeGroupedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 10) {
                            MeValueRow(title: "Current streak", value: "\(currentStreak) days")
                            MeSeparator()
                            MeValueRow(title: "Total learning days", value: "\(totalLearningDays) days")
                        }
                    }
                    .padding(16)
                }

                ActivityCalendarCard(records: records, selectedRecord: $selectedRecord)

                if let selectedRecord {
                    ActivityDayDetailCard(record: selectedRecord)
                }
            }
        }
    }
}

private struct AccountPage: View {
    let summary: MeSummary?

    @State private var showingDeleteConfirmation = false
    @State private var statusMessage: String?

    private var name: String {
        let name = summary?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Demo User" : name
    }

    private var email: String {
        let email = summary?.user.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "demo@example.com" : email
    }

    var body: some View {
        MePageScaffold(title: "Account") {
            VStack(alignment: .leading, spacing: 24) {
                MeGroupedSection(title: "Avatar") {
                    NavigationLink(value: MeDestination.accountEdit(.avatar)) {
                        AvatarSettingsRow(initial: name.initialLetter)
                    }
                    .buttonStyle(.plain)
                }

                MeGroupedSection(title: "Account Info") {
                    NavigationLink(value: MeDestination.accountEdit(.username)) {
                        MeValueRow(title: "Username", value: name, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    NavigationLink(value: MeDestination.accountEdit(.email)) {
                        MeValueRow(title: "Email", value: email, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    NavigationLink(value: MeDestination.accountEdit(.password)) {
                        MeValueRow(title: "Password", value: "Change", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                MeGroupedSection(title: "Account Actions") {
                    Button {
                        statusMessage = "Log out is coming later."
                    } label: {
                        MePlainActionRow(title: "Log Out")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        MePlainActionRow(title: "Delete Account", isDestructive: true)
                    }
                    .buttonStyle(.plain)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppSurface.muted)
                        .padding(.horizontal, 2)
                }
            }
        }
        .confirmationDialog("Delete account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                statusMessage = "Account deletion is coming later."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action may permanently remove your account and learning data.")
        }
    }
}

private struct ConnectedAccountsPage: View {
    @State private var statusMessage: String?

    var body: some View {
        MePageScaffold(title: "Connected Accounts") {
            VStack(alignment: .leading, spacing: 16) {
                MeGroupedSection {
                    Button {
                        statusMessage = "Google connection is coming later."
                    } label: {
                        MeValueRow(title: "Google", value: "Connect")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button {
                        statusMessage = "Facebook connection is coming later."
                    } label: {
                        MeValueRow(title: "Facebook", value: "Connect")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button {
                        statusMessage = "WeChat connection is coming later."
                    } label: {
                        MeValueRow(title: "WeChat", value: "Connect")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button {
                        statusMessage = "TikTok connection is coming later."
                    } label: {
                        MeValueRow(title: "TikTok", value: "Connect")
                    }
                    .buttonStyle(.plain)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppSurface.muted)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
}

private struct LearningPreferencesPage: View {
    var body: some View {
        MePageScaffold(title: "Learning Preferences") {
            MeGroupedSection {
                MeValueRow(title: "Default Review Mode", value: "Review")
                MeSeparator()
                MeValueRow(title: "Daily Goal", value: "20 cards")
                MeSeparator()
                MeValueRow(title: "New Cards Per Day", value: "10")
                MeSeparator()
                MeValueRow(title: "Default Card Direction", value: "Chinese -> English")
            }
        }
    }
}

private struct NotificationsPage: View {
    var body: some View {
        MePageScaffold(title: "Notifications") {
            MeGroupedSection {
                MeValueRow(title: "Review Reminders", value: "Coming later")
                MeSeparator()
                MeValueRow(title: "Reminder Time", value: "8:00 PM")
                MeSeparator()
                MeValueRow(title: "App Messages", value: "Coming later")
            }
        }
    }
}

private struct AppearancePage: View {
    @AppStorage("meFontSizeChoice") private var fontSizeChoice = FontSizeChoice.medium.rawValue

    var body: some View {
        MePageScaffold(title: "Appearance") {
            VStack(alignment: .leading, spacing: 14) {
                MeGroupedSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font Size")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppSurface.text)

                        Picker("Font Size", selection: $fontSizeChoice) {
                            ForEach(FontSizeChoice.allCases) { choice in
                                Text(choice.title).tag(choice.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 10)
                }

                Text("Font size is saved here for now and will apply globally later.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.muted)
                    .padding(.horizontal, 2)
            }
        }
    }
}

private struct PrivacyDataPage: View {
    @State private var statusMessage: String?

    var body: some View {
        MePageScaffold(title: "Privacy & Data") {
            VStack(alignment: .leading, spacing: 16) {
                MeGroupedSection {
                    NavigationLink(value: MeDestination.document(.privacy)) {
                        MeSettingsRow(title: "Privacy Policy")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    NavigationLink(value: MeDestination.document(.terms)) {
                        MeSettingsRow(title: "Terms of Service")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button {
                        statusMessage = "Export data is coming later."
                    } label: {
                        MeValueRow(title: "Export Data", value: "Coming later")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    Button {
                        statusMessage = "Clear local cache is coming later."
                    } label: {
                        MeValueRow(title: "Clear Local Cache", value: "Coming later")
                    }
                    .buttonStyle(.plain)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppSurface.muted)
                        .padding(.horizontal, 2)
                }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        MePageScaffold(title: "About") {
            MeGroupedSection {
                MeValueRow(title: "App Name", value: "MemoryApp")
                MeSeparator()
                MeValueRow(title: "App Version", value: appVersion)
                MeSeparator()
                MeValueRow(title: "Build Number", value: buildNumber)
                MeSeparator()
                MeValueRow(title: "Contact / Feedback", value: "Coming later")
                MeSeparator()
                NavigationLink(value: MeDestination.document(.privacy)) {
                    MeSettingsRow(title: "Privacy Policy")
                }
                .buttonStyle(.plain)
                MeSeparator()
                NavigationLink(value: MeDestination.document(.terms)) {
                    MeSettingsRow(title: "Terms of Service")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

private struct AccountEditPlaceholderPage: View {
    let kind: AccountEditKind

    @State private var value = ""

    var body: some View {
        MePageScaffold(title: kind.title) {
            VStack(alignment: .leading, spacing: 16) {
                MeGroupedSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(kind.fieldTitle)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppSurface.text)

                        if kind == .avatar {
                            Text("Avatar editing is coming later.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppSurface.muted)
                        } else {
                            TextField(kind.placeholder, text: $value)
                                .textInputAutocapitalization(kind == .email ? .never : .words)
                                .autocorrectionDisabled(kind == .email)
                                .textContentType(kind.textContentType)
                                .font(.system(size: 16, weight: .regular))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 52)
                                .background(AppSurface.cardSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(AppSurface.line, lineWidth: 1)
                                )

                            Text("Account editing is coming later.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppSurface.muted)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Button("Save") {}
                    .buttonStyle(CompletionButtonStyle())
                    .disabled(true)
                    .opacity(0.48)
            }
        }
    }
}

private struct LocalDocumentPage: View {
    let document: LocalDocument

    var body: some View {
        MePageScaffold(title: document.title) {
            MeGroupedSection {
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppSurface.text)

                    Text(document.body)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppSurface.muted)
                        .lineSpacing(5)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct MePageScaffold<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                content()
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct MeGroupedSection<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppSurface.muted)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppSurface.line, lineWidth: 1)
            )
        }
    }
}

private struct MeSettingsRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppSurface.text)

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppSurface.muted.opacity(0.45))
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

private struct MeValueRow: View {
    let title: String
    let value: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppSurface.text)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(AppSurface.muted)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppSurface.muted.opacity(0.45))
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

private struct AvatarSettingsRow: View {
    let initial: String

    var body: some View {
        HStack(spacing: 12) {
            Text("Avatar")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppSurface.text)

            Spacer(minLength: 12)

            Text(initial)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppSurface.dark)
                .clipShape(Circle())

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppSurface.muted.opacity(0.45))
        }
        .frame(minHeight: 60)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

private struct MePlainActionRow: View {
    let title: String
    var isDestructive = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isDestructive ? AppSurface.coral : AppSurface.text)

            Spacer()
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

private struct MeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AppSurface.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private struct ActivityCalendarPreview: View {
    let records: [DailyLearningRecord]

    var body: some View {
        MeGroupedSection {
            VStack(alignment: .leading, spacing: 16) {
                ActivityHeatmapGrid(records: records)

                HeatmapLegend()
            }
            .padding(16)
        }
    }
}

private struct ActivityCalendarCard: View {
    let records: [DailyLearningRecord]
    @Binding var selectedRecord: DailyLearningRecord?

    var body: some View {
        MeGroupedSection {
            VStack(alignment: .leading, spacing: 16) {
                MonthlyCheckInCalendarGrid(
                    records: records,
                    selectedRecord: $selectedRecord
                )
            }
            .padding(16)
        }
    }
}

private struct ActivityHeatmapGrid: View {
    let records: [DailyLearningRecord]

    private var weeks: [[HeatmapDayCell]] {
        heatmapWeeks(records: records, weekCount: 16)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                VStack(spacing: 4) {
                    ForEach(weeks[weekIndex]) { cell in
                        HeatmapSquare(cell: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeatmapSquare: View {
    let cell: HeatmapDayCell

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(cell.fillColor)
            .frame(width: 10, height: 10)
    }
}

private struct HeatmapLegend: View {
    private let levels: [ActivityLevel] = [.none, .veryLow, .low, .medium, .high]

    var body: some View {
        HStack(spacing: 6) {
            Text("Less")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppSurface.muted)

            HStack(spacing: 4) {
                ForEach(levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(level.heatmapColor)
                        .frame(width: 10, height: 10)
                }
            }

            Text("More")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppSurface.muted)
        }
    }
}

private struct MonthlyCheckInCalendarGrid: View {
    let records: [DailyLearningRecord]
    @Binding var selectedRecord: DailyLearningRecord?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var cells: [CalendarDayCell] {
        monthCells(for: Date(), records: records)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppSurface.muted.opacity(0.45))
                    .frame(width: 32, height: 32)

                Spacer()

                Text(monthTitle(for: Date()))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppSurface.muted.opacity(0.45))
                    .frame(width: 32, height: 32)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppSurface.muted.opacity(0.74))
                        .frame(height: 20)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(cells) { cell in
                    CalendarDateCell(
                        cell: cell,
                        isSelected: selectedRecord?.dateKey == cell.record?.dateKey
                    ) {
                        if let record = cell.record, record.hasLearning {
                            selectedRecord = record
                        }
                    }
                }
            }
        }
    }
}

private struct CalendarDateCell: View {
    let cell: CalendarDayCell
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack {
                Circle()
                    .fill(cell.record?.level.calendarTint ?? Color.clear)
                    .frame(width: 36, height: 36)

                Circle()
                    .stroke(isSelected ? AppSurface.accent.opacity(0.42) : Color.clear, lineWidth: 1.5)
                    .frame(width: 38, height: 38)

                VStack(spacing: 0) {
                    Text(cell.dayText)
                        .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(cell.date == nil ? Color.clear : AppSurface.text)
                        .monospacedDigit()

                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(cell.record?.level.checkColor ?? Color.clear)
                        .frame(height: 9)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cell.record?.hasLearning != true)
    }
}

private struct ActivityDayDetailCard: View {
    let record: DailyLearningRecord

    var body: some View {
        MeGroupedSection {
            VStack(alignment: .leading, spacing: 14) {
                Text(dayDetailTitle(for: record.date))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                VStack(spacing: 10) {
                    MeValueRow(title: "Learning time", value: "\(record.minutes) min")
                    MeSeparator()
                    MeValueRow(title: "Cards reviewed", value: "\(record.reviewed)")
                    MeSeparator()
                    MeValueRow(title: "Cards mastered", value: "\(record.mastered)")
                    MeSeparator()
                    MeValueRow(title: "New cards added", value: "\(record.newCards)")
                }
            }
            .padding(16)
        }
    }
}

private struct DailyLearningRecord: Identifiable, Hashable {
    var id: String { dateKey }
    let date: Date
    let minutes: Int
    let reviewed: Int
    let mastered: Int
    let newCards: Int

    var hasLearning: Bool {
        minutes > 0 || reviewed > 0 || mastered > 0 || newCards > 0
    }

    var level: ActivityLevel {
        ActivityLevel(minutes: minutes)
    }

    var dateKey: String {
        dayKey(for: date)
    }
}

private struct CalendarDayCell: Identifiable {
    var id: String
    let date: Date?
    let dayText: String
    let record: DailyLearningRecord?
}

private struct HeatmapDayCell: Identifiable {
    var id: String
    let record: DailyLearningRecord?
    let isFuture: Bool

    var fillColor: Color {
        guard !isFuture else {
            return Color.clear
        }
        return record?.level.heatmapColor ?? ActivityLevel.none.heatmapColor
    }
}

private enum ActivityLevel: Hashable {
    case none
    case veryLow
    case low
    case medium
    case high

    init(minutes: Int) {
        switch minutes {
        case ..<1:
            self = .none
        case 1..<5:
            self = .veryLow
        case 5..<15:
            self = .low
        case 15..<30:
            self = .medium
        default:
            self = .high
        }
    }

    var heatmapColor: Color {
        switch self {
        case .none:
            return Color(hex: 0xF1F3F7)
        case .veryLow:
            return AppSurface.accent.opacity(0.18)
        case .low:
            return AppSurface.accent.opacity(0.34)
        case .medium:
            return AppSurface.accent.opacity(0.58)
        case .high:
            return AppSurface.accent
        }
    }

    var checkColor: Color {
        switch self {
        case .none:
            return .clear
        case .veryLow:
            return AppSurface.accent.opacity(0.34)
        case .low:
            return AppSurface.accent.opacity(0.52)
        case .medium:
            return AppSurface.accent.opacity(0.74)
        case .high:
            return AppSurface.accent
        }
    }

    var calendarTint: Color {
        switch self {
        case .none:
            return .clear
        case .veryLow:
            return AppSurface.accent.opacity(0.05)
        case .low:
            return AppSurface.accent.opacity(0.08)
        case .medium:
            return AppSurface.accent.opacity(0.12)
        case .high:
            return AppSurface.accent.opacity(0.17)
        }
    }
}

private enum MeDestination: Hashable {
    case achievements
    case account
    case connectedAccounts
    case learningPreferences
    case notifications
    case appearance
    case privacyData
    case about
    case accountEdit(AccountEditKind)
    case document(LocalDocument)
}

private enum AccountEditKind: Hashable {
    case avatar
    case username
    case email
    case password

    var title: String {
        switch self {
        case .avatar: return "Avatar"
        case .username: return "Username"
        case .email: return "Email"
        case .password: return "Password"
        }
    }

    var fieldTitle: String {
        switch self {
        case .avatar: return "Avatar"
        case .username: return "Username"
        case .email: return "Email"
        case .password: return "New Password"
        }
    }

    var placeholder: String {
        switch self {
        case .avatar: return ""
        case .username: return "Demo User"
        case .email: return "demo@example.com"
        case .password: return "Enter a new password"
        }
    }

    var textContentType: UITextContentType? {
        switch self {
        case .avatar: return nil
        case .username: return .username
        case .email: return .emailAddress
        case .password: return .newPassword
        }
    }
}

private enum FontSizeChoice: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

private enum LocalDocument: Hashable {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Service"
        }
    }

    var body: String {
        switch self {
        case .privacy:
            return "This is a local placeholder for the privacy policy. The official privacy policy will appear here when it is available."
        case .terms:
            return "This is a local placeholder for the terms of service. The official terms will appear here when they are available."
        }
    }
}

private func makeActivityRecords(from summary: MeSummary?) -> [DailyLearningRecord] {
    let calendar = Calendar.current
    if let summary, !summary.recentActivity.isEmpty {
        let parsedRecords = summary.recentActivity.compactMap { activity -> DailyLearningRecord? in
            guard let date = parseAPIDate(activity.date) else {
                return nil
            }
            let reviewed = activity.count
            let minutes = reviewed > 0 ? max(2, reviewed * 2) : 0
            return DailyLearningRecord(
                date: date,
                minutes: minutes,
                reviewed: reviewed,
                mastered: max(0, reviewed / 8),
                newCards: calendar.isDate(date, inSameDayAs: Date()) ? 8 : 0
            )
        }

        if !parsedRecords.isEmpty {
            return parsedRecords
        }
    }

    return sampleActivityRecords()
}

private func sampleActivityRecords() -> [DailyLearningRecord] {
    [
        makeRecord(day: 1, minutes: 4, reviewed: 6, mastered: 0, newCards: 2),
        makeRecord(day: 2, minutes: 12, reviewed: 14, mastered: 1, newCards: 0),
        makeRecord(day: 4, minutes: 18, reviewed: 22, mastered: 2, newCards: 3),
        makeRecord(day: 5, minutes: 8, reviewed: 10, mastered: 1, newCards: 0),
        makeRecord(day: 6, minutes: 34, reviewed: 36, mastered: 4, newCards: 4),
        makeRecord(day: 7, minutes: 28, reviewed: 31, mastered: 4, newCards: 8),
        makeRecord(day: 10, minutes: 6, reviewed: 8, mastered: 0, newCards: 0),
        makeRecord(day: 11, minutes: 16, reviewed: 20, mastered: 2, newCards: 1),
        makeRecord(day: 12, minutes: 22, reviewed: 25, mastered: 3, newCards: 0),
        makeRecord(day: 13, minutes: 3, reviewed: 5, mastered: 0, newCards: 0),
        makeRecord(day: 16, minutes: 40, reviewed: 42, mastered: 5, newCards: 2),
        makeRecord(day: 18, minutes: 11, reviewed: 13, mastered: 1, newCards: 0),
        makeRecord(day: 21, minutes: 24, reviewed: 26, mastered: 3, newCards: 0),
        makeRecord(day: 25, minutes: 7, reviewed: 9, mastered: 1, newCards: 0),
        makeRecord(day: 28, minutes: 31, reviewed: 33, mastered: 4, newCards: 3)
    ]
}

private func makeRecord(day: Int, minutes: Int, reviewed: Int, mastered: Int, newCards: Int) -> DailyLearningRecord {
    let calendar = Calendar.current
    let now = Date()
    let components = calendar.dateComponents([.year, .month], from: now)
    let date = calendar.date(from: DateComponents(year: components.year, month: components.month, day: day)) ?? now
    return DailyLearningRecord(date: date, minutes: minutes, reviewed: reviewed, mastered: mastered, newCards: newCards)
}

private func monthCells(for date: Date, records: [DailyLearningRecord]) -> [CalendarDayCell] {
    let calendar = Calendar.current
    guard
        let monthInterval = calendar.dateInterval(of: .month, for: date),
        let dayRange = calendar.range(of: .day, in: .month, for: date)
    else {
        return []
    }

    let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
    let leadingBlankCount = max(0, firstWeekday - 1)
    let recordsByDay = Dictionary(uniqueKeysWithValues: records.map { ($0.dateKey, $0) })

    var cells: [CalendarDayCell] = (0..<leadingBlankCount).map { index in
        CalendarDayCell(id: "blank-\(index)", date: nil, dayText: "", record: nil)
    }

    for day in dayRange {
        guard let cellDate = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else {
            continue
        }
        let record = recordsByDay[dayKey(for: cellDate)]
        cells.append(
            CalendarDayCell(
                id: dayKey(for: cellDate),
                date: cellDate,
                dayText: "\(day)",
                record: record
            )
        )
    }

    return cells
}

private func heatmapWeeks(records: [DailyLearningRecord], weekCount: Int) -> [[HeatmapDayCell]] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let currentWeekday = calendar.component(.weekday, from: today)
    let currentWeekStart = calendar.date(byAdding: .day, value: -(currentWeekday - 1), to: today) ?? today
    let recordsByDay = Dictionary(uniqueKeysWithValues: records.map { ($0.dateKey, $0) })

    return (0..<weekCount).map { weekOffset in
        let weekStartOffset = (weekOffset - (weekCount - 1)) * 7
        let weekStart = calendar.date(byAdding: .day, value: weekStartOffset, to: currentWeekStart) ?? currentWeekStart

        return (0..<7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
            let key = dayKey(for: date)
            return HeatmapDayCell(
                id: key,
                record: recordsByDay[key],
                isFuture: date > today
            )
        }
    }
}

private func streakCount(records: [DailyLearningRecord]) -> Int {
    let calendar = Calendar.current
    let activeDays = Set(records.filter(\.hasLearning).map(\.dateKey))
    var cursor = calendar.startOfDay(for: Date())
    var count = 0

    while activeDays.contains(dayKey(for: cursor)) {
        count += 1
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
            break
        }
        cursor = previousDay
    }

    return count
}

private func monthTitle(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: date)
}

private func dayDetailTitle(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMMM d"
    return formatter.string(from: date)
}

private func dayKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func parseAPIDate(_ value: String) -> Date? {
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = Calendar(identifier: .gregorian)
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.dateFormat = "yyyy-MM-dd"
    if let date = dayFormatter.date(from: value) {
        return date
    }

    let isoFormatter = ISO8601DateFormatter()
    return isoFormatter.date(from: value)
}

private extension String {
    var initialLetter: String {
        guard let first = trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "D"
        }
        return String(first).uppercased()
    }
}
