import SwiftUI
import UserNotifications

struct MeView: View {
    var onClose: (() -> Void)?

    @EnvironmentObject private var dataStore: AppDataStore

    @State private var summary: MeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAchievements = false

    var body: some View {
        NavigationStack {
            MeScreen {
                pageTitle
                userHeader
                achievementsSection
                profileSection
                settingsSection
                loadState
            }
            // Tab 根屏 = 样式 B（大标题头），无导航栏内容。
            // onClose 存在时说明本视图被 present 出来，此时降级为样式 A（原生返回）。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(onClose == nil ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onClose) {
                            Image(systemName: AppIcon.back)
                        }
                        .accessibilityLabel("Back")
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
                case .mcpAccess:
                    MCPAccessPage()
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
                    AccountEditPage(kind: kind, initialValue: summary?.user.name ?? "")
                case .document(let document):
                    LocalDocumentPage(document: document)
                }
            }
        }
        .task {
            await loadSummary()
        }
        .onReceive(dataStore.$summary) { loadedSummary in
            if let loadedSummary {
                summary = loadedSummary
            }
        }
    }

    private var pageTitle: some View {
        AppLargeHeader(title: "Me")
    }

    private var userHeader: some View {
        HStack(spacing: AppSpace.lg) {
            Text(initial(profileName))
                .appText(AppType.title2, color: AppColor.textOnInverse)
                .frame(width: AppLayout.avatarLG, height: AppLayout.avatarLG)
                .background(AppColor.surfaceInverse, in: Circle())

            VStack(alignment: .leading, spacing: AppSpace.xs) {
                Text(profileName)
                    .appText(AppType.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(profileEmail)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        // MeScreen 的统一间距（14）是为卡片之间调的；头像区到第一张卡需要更多留白，
        // 这里补 12 使其接近参考稿的 28。
        .padding(.bottom, AppSpace.md)
        .accessibilityElement(children: .combine)
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "View all" 回到 SectionHeader 尾部。改造中一度挪到卡片下方，
            // 模拟器实测：它孤立地挂在左下，与上方卡片和下方分组都没有归属关系。
            AppSectionHeader(title: "Achievements", actionTitle: "View all") {
                showingAchievements = true
            }

            ActivityCalendarPreview(records: activityRecords)
        }
        .navigationDestination(isPresented: $showingAchievements) {
            MonthlyAchievementsPage(summary: summary)
        }
    }

    // 参考稿的入口卡没有分组小标题，靠卡片边界分组；每个入口配一枚柔和着色的图标容器。
    private var profileSection: some View {
        SettingsSection {
            NavigationRow(
                title: "Account",
                icon: "person",
                tint: .violet,
                destination: MeDestination.account
            )

            MeRowDivider()

            NavigationRow(
                title: "Connected Accounts",
                icon: "link",
                tint: .blue,
                destination: MeDestination.connectedAccounts
            )

            MeRowDivider()

            NavigationRow(
                title: "Connect ChatGPT",
                icon: "sparkles",
                tint: .teal,
                destination: MeDestination.mcpAccess
            )
        }
    }

    private var settingsSection: some View {
        SettingsSection {
            NavigationRow(
                title: "Learning Preferences",
                icon: "slider.horizontal.3",
                tint: .violet,
                destination: MeDestination.learningPreferences
            )

            MeRowDivider()

            NavigationRow(
                title: "Notifications",
                icon: "bell",
                tint: .amber,
                destination: MeDestination.notifications
            )

            MeRowDivider()

            NavigationRow(
                title: "Appearance",
                icon: "textformat.size",
                tint: .teal,
                destination: MeDestination.appearance
            )

            MeRowDivider()

            NavigationRow(
                title: "Privacy & Data",
                icon: "lock.shield",
                tint: .blue,
                destination: MeDestination.privacyData
            )

            MeRowDivider()

            NavigationRow(
                title: "About",
                icon: "info.circle",
                tint: .rose,
                destination: MeDestination.about
            )
        }
    }

    @ViewBuilder
    private var loadState: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(AppColor.primary)
                Spacer()
            }
        }

        if let errorMessage {
            Text(errorMessage)
                .appText(AppType.label, color: AppColor.dangerText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var profileName: String {
        let name = summary?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Cardly User" : name
    }

    private var profileEmail: String {
        let email = summary?.user.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "No email" : email
    }

    private var activityRecords: [DailyLearningRecord] {
        makeActivityRecords(from: summary)
    }

    private func loadSummary() async {
        if let cachedSummary = dataStore.cachedSummary {
            summary = cachedSummary
        }

        isLoading = true
        errorMessage = nil
        do {
            summary = try await dataStore.refreshSummary(force: false)
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

    /// 直接读后端算好的连续打卡天数，不再本地按活动记录重算——现在 streak 的
    /// 口径是"有没有打卡"，不是"有没有活动"，两者不再等价，本地无法重新推导。
    private var currentStreak: Int {
        summary?.currentStreak ?? 0
    }

    private var totalLearningDays: Int {
        records.filter { $0.hasLearning }.count
    }

    var body: some View {
        SettingsPage(title: "Achievements") {
            SettingsSection {
                ValueRow(title: "Current streak", value: "\(currentStreak) days")
                MeRowDivider()
                ValueRow(title: "Total learning days", value: "\(totalLearningDays) days")
            }

            ActivityCalendarCard(records: records, selectedRecord: $selectedRecord)

            if let selectedRecord {
                ActivityDayDetailCard(record: selectedRecord)
            }
        }
    }
}

private struct AccountPage: View {
    @EnvironmentObject private var session: AuthSessionStore

    let summary: MeSummary?

    @State private var showingDeleteConfirmation = false
    @State private var showingPasswordSheet = false
    @State private var statusMessage: String?
    @State private var deleteCode = ""
    @State private var deleteCodeRequested = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var name: String {
        let name = summary?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Cardly User" : name
    }

    private var email: String {
        let email = summary?.user.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "No email" : email
    }

    private var isAppleAccount: Bool {
        summary?.user.provider == "apple"
    }

    var body: some View {
        SettingsPage(title: "Account") {
            VStack(alignment: .leading, spacing: MeTheme.cardGap) {
                // Avatar 尚无后端支持。此前点进去是一个永远保存不了的页面，
                // 现在明确标注而不是给一个假的可点入口。
                SettingsSection {
                    ValueRow(title: "Avatar", value: "Coming soon")
                }

                SettingsSection {
                    if isAppleAccount {
                        ValueRow(title: "Apple Account", value: "Signed in with Apple")
                        MeRowDivider()
                    }

                    NavigationRow(
                        title: "Username",
                        value: name,
                        destination: MeDestination.accountEdit(.username)
                    )

                    MeRowDivider()

                    // 换邮箱需要「验证新地址 + 迁移 identity」的完整流程，尚未实现。
                    ValueRow(title: "Email", value: email)

                    MeRowDivider()

                    ActionRow(
                        title: "Password",
                        value: session.hasPassword ? "Change" : "Set",
                        showsChevron: true
                    ) {
                        showingPasswordSheet = true
                    }
                }

                SettingsSection {
                    ActionRow(title: "Log Out") {
                        Task {
                            await session.logout()
                        }
                    }

                    MeRowDivider()

                    ActionRow(title: "Delete Account", isDestructive: true) {
                        showingDeleteConfirmation = true
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .appText(AppType.label, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .appText(AppType.label, color: AppColor.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingPasswordSheet) {
            SetPasswordView()
                .environmentObject(session)
        }
        .confirmationDialog("Delete account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button(isAppleAccount ? "Delete Account" : "Send Delete Code", role: .destructive) {
                Task {
                    if isAppleAccount {
                        await deleteAccount()
                    } else {
                        await requestDeleteCode()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action may permanently remove your account and learning data.")
        }
        .sheet(isPresented: $deleteCodeRequested) {
            DeleteAccountCodeSheet(
                email: email,
                code: $deleteCode,
                isWorking: isWorking,
                onCancel: {
                    deleteCodeRequested = false
                    deleteCode = ""
                },
                onDelete: {
                    Task {
                        await deleteAccount()
                    }
                }
            )
            .presentationDetents([.height(300)])
        }
    }

    private func requestDeleteCode() async {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        do {
            try await session.requestDeleteAccountCode()
            deleteCode = ""
            deleteCodeRequested = true
            statusMessage = "Delete code sent to \(email)."
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func deleteAccount() async {
        isWorking = true
        errorMessage = nil
        do {
            try await session.deleteAccount(email: email, code: deleteCode)
            deleteCodeRequested = false
            deleteCode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

private struct DeleteAccountCodeSheet: View {
    let email: String
    @Binding var code: String
    let isWorking: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            AppColor.surfaceBase
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppSpace.lg) {
                Text("Delete Account")
                    .appText(AppType.title2)

                Text("Enter the verification code sent to \(email).")
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                AppTextField(label: "Verification code", text: $code, placeholder: "6-digit code")
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)

                HStack(spacing: AppSpace.md) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Delete")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(AppLayout.screenMargin)
        }
    }
}

/// MCP 个人访问令牌管理。
///
/// 个人令牌把 token 绑定到当前登录用户，确保 MCP 工具只操作自己的数据。
private struct MCPAccessPage: View {
    private let mcpServerURL = ProcessInfo.processInfo.environment["MEMORY_MCP_SERVER_URL"] ?? "https://mcp.siyuancheng.com/mcp"
    private let chatGPTURL = URL(string: "https://chatgpt.com/")
    private let oauthClientID = "recall-deck-chatgpt"
    private let oauthScopes = "recall.cards.read recall.cards.write"

    @State private var tokens: [MCPToken] = []
    @State private var freshToken: String?
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var revoking: MCPToken?
    @State private var copiedServerURL = false
    @State private var copiedOAuthSettings = false
    @State private var copiedToken = false
    @State private var showingAdvancedTokens = false

    private var mcpOrigin: String {
        guard let url = URL(string: mcpServerURL),
              let scheme = url.scheme,
              let host = url.host else {
            return "https://mcp.siyuancheng.com"
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private var authorizationURL: String {
        "\(mcpOrigin)/oauth/authorize"
    }

    private var tokenURL: String {
        "\(mcpOrigin)/oauth/token"
    }

    private var oauthSettingsText: String {
        """
        Server URL: \(mcpServerURL)
        Authentication: OAuth
        Registration method: User-Defined OAuth Client
        Authorization URL: \(authorizationURL)
        Token URL: \(tokenURL)
        OAuth Client ID: \(oauthClientID)
        OAuth Client Secret: leave empty
        Token endpoint auth method: none
        Scopes: \(oauthScopes)
        """
    }

    var body: some View {
        SettingsPage(title: "Connect ChatGPT") {
            MeCard(padding: MeTheme.cardPadding) {
                VStack(alignment: .leading, spacing: AppSpace.md) {
                    VStack(alignment: .leading, spacing: AppSpace.sm) {
                        Text("Use Cardly in ChatGPT")
                            .appText(AppType.headline)
                        Text("Add this MCP server URL in ChatGPT. Choose OAuth when asked to sign in, then authorize Cardly with your account.")
                            .appText(AppType.body, color: AppColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: AppSpace.xs) {
                        Text("MCP Server URL")
                            .appText(AppType.label, color: AppColor.textTertiary)
                        Text(mcpServerURL)
                            .appText(AppType.body)
                            .monospaced()
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AppSpace.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColor.surfaceSunken, in: AppRadius.shape(AppRadius.md))

                    HStack(spacing: AppSpace.sm) {
                        AppButton(
                            title: copiedServerURL ? "Copied" : "Copy URL",
                            icon: copiedServerURL ? "checkmark" : "doc.on.doc",
                            variant: .secondary,
                            size: .medium,
                            fullWidth: true
                        ) {
                            UIPasteboard.general.string = mcpServerURL
                            copiedServerURL = true
                        }

                        if let chatGPTURL {
                            AppButton(
                                title: "Open ChatGPT",
                                icon: "arrow.up.right",
                                variant: .primary,
                                size: .medium,
                                fullWidth: true
                            ) {
                                UIApplication.shared.open(chatGPTURL)
                            }
                        }
                    }
                }
            }

            MeCard(padding: MeTheme.cardPadding) {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    Text("Recommended setup")
                        .appText(AppType.headline)
                    Text("In ChatGPT, create a custom MCP connector, paste the server URL, select OAuth, then sign in on the Cardly authorization page. If ChatGPT asks for Advanced OAuth settings, use the fields below.")
                        .appText(AppType.body, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MeCard(padding: MeTheme.cardPadding) {
                VStack(alignment: .leading, spacing: AppSpace.md) {
                    VStack(alignment: .leading, spacing: AppSpace.sm) {
                        Text("Advanced OAuth settings")
                            .appText(AppType.headline)
                        Text("Use these only if ChatGPT does not discover OAuth automatically after you paste the Server URL.")
                            .appText(AppType.body, color: AppColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: AppSpace.sm) {
                        oauthSettingRow(title: "Registration method", value: "User-Defined OAuth Client")
                        oauthSettingRow(title: "Authorization URL", value: authorizationURL)
                        oauthSettingRow(title: "Token URL", value: tokenURL)
                        oauthSettingRow(title: "OAuth Client ID", value: oauthClientID)
                        oauthSettingRow(title: "OAuth Client Secret", value: "Leave empty")
                        oauthSettingRow(title: "Token endpoint auth method", value: "none")
                        oauthSettingRow(title: "Scopes", value: oauthScopes)
                    }

                    AppButton(
                        title: copiedOAuthSettings ? "Copied settings" : "Copy OAuth settings",
                        icon: copiedOAuthSettings ? "checkmark" : "doc.on.doc",
                        variant: .secondary,
                        size: .medium,
                        fullWidth: true
                    ) {
                        UIPasteboard.general.string = oauthSettingsText
                        copiedOAuthSettings = true
                    }
                }
            }

            AppButton(
                title: showingAdvancedTokens ? "Hide advanced token access" : "Advanced token access",
                icon: showingAdvancedTokens ? "chevron.up" : "chevron.down",
                variant: .ghost,
                size: .medium,
                fullWidth: true
            ) {
                withAnimation(AppMotion.standard) {
                    showingAdvancedTokens.toggle()
                }
            }

            if showingAdvancedTokens {
                advancedTokenSection
            }
        }
        .task { await load() }
    }

    private func oauthSettingRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpace.xs) {
            Text(LocalizedStringKey(title))
                .appText(AppType.label, color: AppColor.textTertiary)
            Text(LocalizedStringKey(value))
                .appText(AppType.body)
                .monospaced()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surfaceSunken, in: AppRadius.shape(AppRadius.md))
    }

    private var advancedTokenSection: some View {
        VStack(alignment: .leading, spacing: AppSpace.lg) {
            MeCard(padding: MeTheme.cardPadding) {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    Text("Personal access tokens")
                        .appText(AppType.headline)
                    Text("Use tokens only when a client cannot use OAuth. Tokens can read, create, and delete cards in your account.")
                        .appText(AppType.body, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // 明文只在创建时出现一次，用反相卡强调「现在不复制就再也拿不到」
            if let freshToken {
                AppCard(variant: .inverse) {
                    VStack(alignment: .leading, spacing: AppSpace.md) {
                        Text("Copy it now")
                            .appText(AppType.label, color: AppColor.primaryOnInverse)

                        Text(freshToken)
                            .appText(AppType.body, color: AppColor.textOnInverse)
                            .monospaced()
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        Text("This is the only time the token is shown.")
                            .appText(AppType.label, color: AppColor.textOnInverseSecondary)

                        AppButton(
                            title: copiedToken ? "Copied" : "Copy token",
                            variant: .secondary,
                            size: .medium,
                            fullWidth: true
                        ) {
                            UIPasteboard.general.string = freshToken
                            copiedToken = true
                        }
                    }
                }
            }

            AppButton(
                title: "Generate token",
                variant: .primary,
                size: .large,
                fullWidth: true,
                isEnabled: !isCreating,
                isLoading: isCreating
            ) {
                Task { await create() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .appText(AppType.label, color: AppColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                HStack { Spacer(); ProgressView().tint(AppColor.primary); Spacer() }
            } else if tokens.isEmpty {
                AppEmptyState(
                    title: "No tokens yet",
                    message: "Generate one to connect an MCP client.",
                    density: .compact
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    AppSectionHeader(title: "Active tokens")

                    MeCard {
                        ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                            if index > 0 { MeRowDivider() }
                            AppListRow(
                                title: token.name,
                                subtitle: subtitle(for: token),
                                accessory: .none,
                                isEnabled: revoking?.id != token.id
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await revoke(token) }
                                } label: {
                                    Label("Revoke", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Text("Swipe a token to revoke it.")
                        .appText(AppType.label, color: AppColor.textTertiary)
                        .padding(.top, AppSpace.sm)
                }
            }
        }
    }

    private func subtitle(for token: MCPToken) -> String {
        let created = shortDate(token.createdAt)
        guard let used = token.lastUsedAt else {
            return "Created \(created) · never used"
        }
        return "Created \(created) · last used \(shortDate(used))"
    }

    private func shortDate(_ raw: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            tokens = try await APIClient.shared.listMCPTokens()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        copiedToken = false
        do {
            let created = try await APIClient.shared.createMCPToken(name: "MCP client")
            freshToken = created.token
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }

    private func revoke(_ token: MCPToken) async {
        revoking = token
        errorMessage = nil
        do {
            try await APIClient.shared.revokeMCPToken(tokenID: token.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        revoking = nil
    }
}

private struct ConnectedAccountsPage: View {
    @State private var statusMessage: String?

    var body: some View {
        SettingsPage(title: "Connected Accounts") {
            SettingsSection(footer: statusMessage) {
                ActionRow(title: "Google", value: "Connect") {
                    statusMessage = "Google connection is coming later."
                }

                MeRowDivider()

                ActionRow(title: "Facebook", value: "Connect") {
                    statusMessage = "Facebook connection is coming later."
                }

                MeRowDivider()

                ActionRow(title: "WeChat", value: "Connect") {
                    statusMessage = "WeChat connection is coming later."
                }

                MeRowDivider()

                ActionRow(title: "TikTok", value: "Connect") {
                    statusMessage = "TikTok connection is coming later."
                }
            }
        }
    }
}

private struct LearningPreferencesPage: View {
    @State private var preferences = LearningPreferences(
        limitMode: .newPlusReview,
        newCardsPerDay: 20,
        totalCardsPerDay: 30,
        dailyReminderEnabled: false,
        dailyReminderTime: "20:00",
        defaultReviewMode: "Review",
        // 与后端下发的原文保持一致；箭头字形的美化在 Localizable.strings 的 value 里做。
        defaultCardDirection: "Chinese -> English"
    )
    @State private var reminderDate = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var statusMessage: String?

    var body: some View {
        SettingsPage(title: "Learning Preferences") {
            SettingsSection {
                PickerRow(title: "Daily limit mode", selection: $preferences.limitMode) {
                    ForEach(DailyLimitMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                MeRowDivider()

                // 数字直接键入，不用 +/− 步进器。
                if preferences.limitMode == .newPlusReview {
                    NumberFieldRow(title: "New Cards Per Day", value: $preferences.newCardsPerDay, range: 0...100)
                } else {
                    NumberFieldRow(title: "Total Cards Per Day", value: $preferences.totalCardsPerDay, range: 1...300)
                }
            }

            SettingsSection {
                ValueRow(title: "Default Review Mode", value: preferences.defaultReviewMode)
                MeRowDivider()
                ValueRow(title: "Default Card Direction", value: preferences.defaultCardDirection)
            }

            SettingsSection(footer: statusMessage) {
                ToggleRow(
                    title: "Daily Reminder",
                    subtitle: "Get a daily nudge to review your cards",
                    isOn: $preferences.dailyReminderEnabled
                )

                if preferences.dailyReminderEnabled {
                    MeRowDivider()
                    DatePicker(
                        "Reminder Time",
                        selection: $reminderDate,
                        displayedComponents: .hourAndMinute
                    )
                    .appText(MeTheme.rowLabel)
                    .padding(.horizontal, MeTheme.rowPaddingH)
                    .padding(.vertical, MeTheme.rowPaddingV)
                    .frame(minHeight: MeTheme.rowMinHeight)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving..." : "Save") {
                    Task {
                        await savePreferences()
                    }
                }
                .disabled(isLoading || isSaving)
            }
        }
        .task {
            await loadPreferences()
        }
        .onChange(of: reminderDate) { _, newValue in
            preferences.dailyReminderTime = Self.clockTimeString(from: newValue)
        }
    }

    private func loadPreferences() async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = nil
        do {
            let loaded = try await APIClient.shared.getLearningPreferences()
            preferences = loaded
            reminderDate = Self.date(fromClockTime: loaded.dailyReminderTime)
        } catch {
            statusMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func savePreferences() async {
        guard !isSaving else { return }
        isSaving = true
        statusMessage = nil
        preferences.dailyReminderTime = Self.clockTimeString(from: reminderDate)
        do {
            let saved = try await APIClient.shared.updateLearningPreferences(
                LearningPreferencesPayload(
                    limitMode: preferences.limitMode.rawValue,
                    newCardsPerDay: preferences.newCardsPerDay,
                    totalCardsPerDay: preferences.totalCardsPerDay,
                    dailyReminderEnabled: preferences.dailyReminderEnabled,
                    dailyReminderTime: preferences.dailyReminderTime
                )
            )
            preferences = saved
            reminderDate = Self.date(fromClockTime: saved.dailyReminderTime)
            await configureDailyReminder()
            statusMessage = "Saved."
        } catch {
            statusMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func configureDailyReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["cardly.daily-learning-reminder"])
        guard preferences.dailyReminderEnabled else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                statusMessage = "Notification permission was not granted."
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Cardly"
            content.body = "Time for today's English cards."
            content.sound = .default

            let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "cardly.daily-learning-reminder",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private static func date(fromClockTime value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 20
        components.minute = parts.dropFirst().first ?? 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func clockTimeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 20, components.minute ?? 0)
    }
}

private struct NotificationsPage: View {
    var body: some View {
        SettingsPage(title: "Notifications") {
            SettingsSection {
                ValueRow(title: "Review Reminders", value: "Coming later")
                MeRowDivider()
                ValueRow(title: "Reminder Time", value: "8:00 PM")
                MeRowDivider()
                ValueRow(title: "App Messages", value: "Coming later")
            }
        }
    }
}

private struct AppearancePage: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("meFontSizeChoice") private var fontSizeChoice = FontSizeChoice.medium.rawValue
    @AppStorage("reviewEnglishVoice") private var englishVoice = ReviewEnglishVoice.american.rawValue

    var body: some View {
        SettingsPage(title: "Appearance") {
            SettingsSection {
                LabeledPickerRow(title: "Language", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
            }

            SettingsSection {
                LabeledPickerRow(title: "Font Size", selection: $fontSizeChoice) {
                    ForEach(FontSizeChoice.allCases) { choice in
                        Text(LocalizedStringKey(choice.title)).tag(choice.rawValue)
                    }
                }
            }

            SettingsSection(footer: "Voice preference applies to answer audio during review.") {
                LabeledPickerRow(title: "English Voice", selection: $englishVoice) {
                    ForEach(ReviewEnglishVoice.allCases) { voice in
                        Text(LocalizedStringKey(voice.title)).tag(voice.rawValue)
                    }
                }
            }
        }
    }
}

private struct PrivacyDataPage: View {
    @State private var statusMessage: String?

    var body: some View {
        SettingsPage(title: "Privacy & Data") {
            SettingsSection(footer: statusMessage) {
                NavigationRow(title: "Privacy Policy", destination: MeDestination.document(.privacy))

                MeRowDivider()

                NavigationRow(title: "Terms of Service", destination: MeDestination.document(.terms))

                MeRowDivider()

                ActionRow(title: "Export Data", value: "Coming later") {
                    statusMessage = "Export data is coming later."
                }

                MeRowDivider()

                ActionRow(title: "Clear Local Cache", value: "Coming later") {
                    statusMessage = "Clear local cache is coming later."
                }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        SettingsPage(title: "About") {
            SettingsSection {
                ValueRow(title: "App Name", value: "Cardly")
                MeRowDivider()
                ValueRow(title: "App Version", value: appVersion)
                MeRowDivider()
                ValueRow(title: "Build Number", value: buildNumber)
                MeRowDivider()
                ValueRow(title: "Contact / Feedback", value: "Coming later")
            }

            SettingsSection {
                NavigationRow(title: "Privacy Policy", destination: MeDestination.document(.privacy))
                MeRowDivider()
                NavigationRow(title: "Terms of Service", destination: MeDestination.document(.terms))
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

/// 改用户名。用户名纯展示：不唯一、不参与登录，因此没有可用性检查。
///
/// 这一屏此前是个占位页 —— 输入框能打字，但 Save 写死 isEnabled: false，
/// 因为后端根本没有对应端点。现在接 PATCH /account。
private struct AccountEditPage: View {
    let kind: AccountEditKind

    @EnvironmentObject private var session: AuthSessionStore
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var value: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(kind: AccountEditKind, initialValue: String) {
        self.kind = kind
        _value = State(initialValue: initialValue)
    }

    private var trimmed: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !isSaving && !trimmed.isEmpty && trimmed != session.user?.name
    }

    var body: some View {
        SettingsPage(title: kind.title) {
            MeCard(padding: MeTheme.cardPadding) {
                AppTextField(
                    label: kind.fieldTitle,
                    text: $value,
                    placeholder: "",
                    helper: "Shown in the app. It doesn't affect how you sign in."
                )
                .textInputAutocapitalization(.words)
                .textContentType(kind.textContentType)
            }

            AppButton(
                title: "Save",
                variant: .primary,
                size: .large,
                fullWidth: true,
                isEnabled: canSave,
                isLoading: isSaving
            ) {
                Task { await save() }
            }

            if let errorMessage {
                Text(errorMessage)
                    .appText(AppType.label, color: AppColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await session.updateDisplayName(trimmed)
            dataStore.invalidateSummary()
            Task {
                _ = try? await dataStore.refreshSummary(force: true)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct LocalDocumentPage: View {
    let document: LocalDocument

    var body: some View {
        SettingsPage(title: document.title) {
            // 自由内容用带内边距的卡片，避免零内边距落进圆角裁切区。
            MeCard(padding: MeTheme.cardPadding) {
                VStack(alignment: .leading, spacing: AppSpace.md) {
                    Text(document.title)
                        .appText(AppType.title2)

                    Text(document.body)
                        .appText(AppType.body, color: AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MePageScaffold / MeGroupedSection / MeValueRow / MePlainActionRow / MeSeparator /
// AvatarSettingsRow 已随本次改版删除 —— 它们的职责整体迁移到 DesignSystem/MeSettingsKit.swift
// 的 SettingsPage / SettingsSection / ValueRow / ActionRow / MeRowDivider。

private struct ActivityCalendarPreview: View {
    let records: [DailyLearningRecord]

    /// 无任何学习分钟数 = 空数据
    private var isEmpty: Bool {
        records.allSatisfy { $0.minutes <= 0 }
    }

    var body: some View {
        MeCard(padding: MeTheme.cardPadding) {
            VStack(alignment: .leading, spacing: AppSpace.lg) {
                // 空数据时**网格照常绘制**（全部 heatLevel0），只是不显示图例。
                // 改造前空数据是一整块无差别的灰，读不出"没数据"还是"没加载出来"。
                ActivityHeatmapGrid(records: records)

                if isEmpty {
                    AppEmptyState(
                        title: "No activity yet",
                        message: "Review a few cards and your streak will show up here.",
                        density: .compact
                    )
                } else {
                    HeatmapLegend()
                }
            }
        }
    }
}

private struct ActivityCalendarCard: View {
    let records: [DailyLearningRecord]
    @Binding var selectedRecord: DailyLearningRecord?

    var body: some View {
        MeCard(padding: MeTheme.cardPadding) {
            MonthlyCheckInCalendarGrid(
                records: records,
                selectedRecord: $selectedRecord
            )
        }
    }
}

private struct ActivityHeatmapGrid: View {
    let records: [DailyLearningRecord]

    private var weeks: [[HeatmapDayCell]] {
        heatmapWeeks(records: records, weekCount: 16)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppLayout.heatCellGap) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                VStack(spacing: AppLayout.heatCellGap) {
                    ForEach(weeks[weekIndex]) { cell in
                        HeatmapSquare(cell: cell)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct HeatmapSquare: View {
    let cell: HeatmapDayCell

    var body: some View {
        RoundedRectangle(cornerRadius: AppSpace.xs / 2, style: .continuous)
            .fill(cell.fillColor)
            .frame(width: AppLayout.heatCell, height: AppLayout.heatCell)
    }
}

private struct HeatmapLegend: View {
    private let levels: [ActivityLevel] = [.none, .veryLow, .low, .medium, .high]

    var body: some View {
        HStack(spacing: AppSpace.sm) {
            Text("Less")
                .appText(AppType.caption, color: AppColor.textTertiary)

            HStack(spacing: AppLayout.heatCellGap) {
                ForEach(levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: AppSpace.xs / 2, style: .continuous)
                        .fill(level.heatmapColor)
                        .frame(width: AppLayout.heatCell, height: AppLayout.heatCell)
                }
            }

            Text("More")
                .appText(AppType.caption, color: AppColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity legend, less to more")
    }
}

private struct MonthlyCheckInCalendarGrid: View {
    let records: [DailyLearningRecord]
    @Binding var selectedRecord: DailyLearningRecord?

    /// 当前展示的月份。改造前这里写死 Date()，两个箭头只是 Image、没有 action，
    /// 是一个点了没反应的假控件。
    @State private var displayedMonth: Date = Date()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpace.xs), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var cells: [CalendarDayCell] {
        monthCells(for: displayedMonth, records: records)
    }

    /// 可翻阅范围 = 后端实际返回的活跃数据区间所覆盖的月份。
    /// 超出范围翻页只会看到整月空白，不如直接禁用。
    private var monthBounds: (earliest: Date, latest: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let latest = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let earliestRecord = records.map(\.date).min() ?? today
        let earliest = calendar.dateInterval(of: .month, for: earliestRecord)?.start ?? latest
        return (earliest, latest)
    }

    private var canGoBack: Bool {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start else { return false }
        return start > monthBounds.earliest
    }

    private var canGoForward: Bool {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .month, for: displayedMonth)?.start else { return false }
        return start < monthBounds.latest
    }

    private func step(_ months: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        displayedMonth = next
        selectedRecord = nil          // 换月后旧的选中日期已不在视野内
    }

    var body: some View {
        VStack(spacing: AppSpace.md) {
            HStack {
                monthStepButton(icon: AppIcon.back, enabled: canGoBack, label: "Previous month") { step(-1) }

                Spacer()

                Text(monthTitle(for: displayedMonth))
                    .appText(AppType.headline)
                    .monospacedDigit()

                Spacer()

                monthStepButton(icon: AppIcon.disclose, enabled: canGoForward, label: "Next month") { step(1) }
            }
            .animation(AppMotion.standard, value: displayedMonth)

            LazyVGrid(columns: columns, spacing: AppSpace.xs) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .appText(AppType.caption, color: AppColor.textTertiary)
                        .frame(height: AppSpace.xl)
                }
            }

            LazyVGrid(columns: columns, spacing: AppSpace.sm) {
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

    private func monthStepButton(icon: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppIcon.font(AppLayout.iconSM))
                .foregroundStyle(enabled ? AppColor.iconDefault : AppColor.disabledIcon)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
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
                    .stroke(isSelected ? AppColor.primary : Color.clear, lineWidth: AppLayout.focusRingWidth)
                    .frame(width: 38, height: 38)

                VStack(spacing: 0) {
                    Text(cell.dayText)
                        .font(.system(size: AppType.label.size, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(cell.date == nil ? Color.clear : AppColor.textPrimary)
                        .monospacedDigit()

                    Image(systemName: "checkmark")
                        .font(.system(size: AppSpace.sm, weight: .bold))
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
        MeCard {
            Text(dayDetailTitle(for: record.date))
                .appText(AppType.headline)
                .padding(.horizontal, MeTheme.rowPaddingH)
                .padding(.top, MeTheme.rowPaddingV)
                .padding(.bottom, AppSpace.sm)

            ValueRow(title: "Learning time", value: "\(record.minutes) min")
            MeRowDivider()
            ValueRow(title: "Cards reviewed", value: "\(record.reviewed)")
            MeRowDivider()
            ValueRow(title: "Cards mastered", value: "\(record.mastered)")
            MeRowDivider()
            ValueRow(title: "New cards added", value: "\(record.newCards)")
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

    /// 5 档实色阶，不再用 .opacity() —— 透明度叠在不同底色上会漂移，
    /// 且深色模式下会整体失真。取值见 AppColor.heatScale。
    var heatmapColor: Color {
        switch self {
        case .none:    return AppColor.heatLevel0
        case .veryLow: return AppColor.heatLevel1
        case .low:     return AppColor.heatLevel2
        case .medium:  return AppColor.heatLevel3
        case .high:    return AppColor.heatLevel4
        }
    }

    /// 与热力图共用同一套 5 档实色阶，保证同一数据在两处呈现一致。
    var checkColor: Color {
        switch self {
        case .none: return .clear
        default:    return heatmapColor
        }
    }

    /// 月历格底：始终比 check 浅一档，none 透明。
    var calendarTint: Color {
        switch self {
        case .none:    return .clear
        case .veryLow: return AppColor.heatLevel0
        case .low:     return AppColor.heatLevel1
        case .medium:  return AppColor.heatLevel1
        case .high:    return AppColor.heatLevel2
        }
    }
}

private enum MeDestination: Hashable {
    case achievements
    case account
    case connectedAccounts
    case mcpAccess
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
        // 输入框不放示例值 —— 示例会被误读为已填内容。
        // 字段含义由上方 label 承担。
        case .avatar: return ""
        case .username: return ""
        case .email: return ""
        case .password: return ""
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
