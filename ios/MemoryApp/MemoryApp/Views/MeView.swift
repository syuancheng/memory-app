import SwiftUI

struct MeView: View {
    var onClose: (() -> Void)?

    @State private var summary: MeSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAchievements = false

    var body: some View {
        NavigationStack {
            AppScreen {
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

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader(title: "Profile")

            AppGroupedList {
                NavigationLink(value: MeDestination.account) {
                    AppListRow(title: "Account", icon: "person")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.connectedAccounts) {
                    AppListRow(title: "Connected Accounts", icon: "link")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.mcpAccess) {
                    AppListRow(title: "Connect ChatGPT", icon: "sparkles")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppSectionHeader(title: "Settings")

            AppGroupedList {
                NavigationLink(value: MeDestination.learningPreferences) {
                    AppListRow(title: "Learning Preferences", icon: "slider.horizontal.3")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.notifications) {
                    AppListRow(title: "Notifications", icon: "bell")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.appearance) {
                    AppListRow(title: "Appearance", icon: "textformat.size")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.privacyData) {
                    AppListRow(title: "Privacy & Data", icon: "lock.shield")
                }
                .buttonStyle(.plain)

                AppRowSeparator()

                NavigationLink(value: MeDestination.about) {
                    AppListRow(title: "About", icon: "info.circle")
                }
                .buttonStyle(.plain)
            }
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
            VStack(alignment: .leading, spacing: AppSpace.lg) {
                MeGroupedSection {
                    MeValueRow(title: "Current streak", value: "\(currentStreak) days")
                    MeSeparator()
                    MeValueRow(title: "Total learning days", value: "\(totalLearningDays) days")
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
        return name.isEmpty ? "Demo User" : name
    }

    private var email: String {
        let email = summary?.user.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "demo@example.com" : email
    }

    private var isAppleAccount: Bool {
        summary?.user.provider == "apple"
    }

    var body: some View {
        MePageScaffold(title: "Account") {
            VStack(alignment: .leading, spacing: AppSpace.xxl) {
                // Avatar 尚无后端支持。此前点进去是一个永远保存不了的页面，
                // 现在明确标注而不是给一个假的可点入口。
                MeGroupedSection(title: "Avatar") {
                    MeValueRow(title: "Avatar", value: "Coming soon")
                }

                MeGroupedSection(title: "Account Info") {
                    if isAppleAccount {
                        MeValueRow(title: "Apple Account", value: "Signed in with Apple")
                        MeSeparator()
                    }

                    NavigationLink(value: MeDestination.accountEdit(.username)) {
                        MeValueRow(title: "Username", value: name, showsChevron: true)
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    // 换邮箱需要「验证新地址 + 迁移 identity」的完整流程，尚未实现。
                    MeValueRow(title: "Email", value: email)

                    MeSeparator()

                    Button {
                        showingPasswordSheet = true
                    } label: {
                        MeValueRow(
                            title: "Password",
                            value: session.hasPassword ? "Change" : "Set",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                MeGroupedSection(title: "Account Actions") {
                    Button {
                        Task {
                            await session.logout()
                        }
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
/// 存在的理由：MCP 的静态 MEMORY_MCP_TOKEN 一律映射到 demo 用户，
/// 通过它创建的卡片进不了自己的账号。个人令牌把 token 绑定到当前登录用户。
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
        MePageScaffold(title: "Connect ChatGPT") {
            AppCard {
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

            AppCard {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    Text("Recommended setup")
                        .appText(AppType.headline)
                    Text("In ChatGPT, create a custom MCP connector, paste the server URL, select OAuth, then sign in on the Cardly authorization page. If ChatGPT asks for Advanced OAuth settings, use the fields below.")
                        .appText(AppType.body, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AppCard {
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
            Text(title)
                .appText(AppType.label, color: AppColor.textTertiary)
            Text(value)
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
            AppCard {
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

                    AppGroupedList {
                        ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                            if index > 0 { AppRowSeparator(inset: AppLayout.separatorInsetPlain) }
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
        MePageScaffold(title: "Connected Accounts") {
            VStack(alignment: .leading, spacing: AppSpace.lg) {
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
                        .appText(AppType.label, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: AppSpace.md) {
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpace.md) {
                        Text("Font Size")
                            .appText(AppType.label, color: AppColor.textTertiary)

                        Picker("Font Size", selection: $fontSizeChoice) {
                            ForEach(FontSizeChoice.allCases) { choice in
                                Text(choice.title).tag(choice.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Text("Font size is saved here for now and will apply globally later.")
                    .appText(AppType.label, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PrivacyDataPage: View {
    @State private var statusMessage: String?

    var body: some View {
        MePageScaffold(title: "Privacy & Data") {
            VStack(alignment: .leading, spacing: AppSpace.lg) {
                MeGroupedSection {
                    NavigationLink(value: MeDestination.document(.privacy)) {
                        AppListRow(title: "Privacy Policy")
                    }
                    .buttonStyle(.plain)

                    MeSeparator()

                    NavigationLink(value: MeDestination.document(.terms)) {
                        AppListRow(title: "Terms of Service")
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
                        .appText(AppType.label, color: AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        MePageScaffold(title: "About") {
            MeGroupedSection {
                MeValueRow(title: "App Name", value: "Cardly")
                MeSeparator()
                MeValueRow(title: "App Version", value: appVersion)
                MeSeparator()
                MeValueRow(title: "Build Number", value: buildNumber)
                MeSeparator()
                MeValueRow(title: "Contact / Feedback", value: "Coming later")
                MeSeparator()
                NavigationLink(value: MeDestination.document(.privacy)) {
                    AppListRow(title: "Privacy Policy")
                }
                .buttonStyle(.plain)
                MeSeparator()
                NavigationLink(value: MeDestination.document(.terms)) {
                    AppListRow(title: "Terms of Service")
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

/// 改用户名。用户名纯展示：不唯一、不参与登录，因此没有可用性检查。
///
/// 这一屏此前是个占位页 —— 输入框能打字，但 Save 写死 isEnabled: false，
/// 因为后端根本没有对应端点。现在接 PATCH /account。
private struct AccountEditPage: View {
    let kind: AccountEditKind

    @EnvironmentObject private var session: AuthSessionStore
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
        MePageScaffold(title: kind.title) {
            AppCard {
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
        MePageScaffold(title: document.title) {
            // 同 Username 页：自由内容用 AppCard，避免零内边距落进圆角裁切区。
            AppCard {
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

private struct MePageScaffold<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        AppScreen {
            content()
        }
        // 样式 A：可返回的屏一律用原生导航栏（inline 标题 + 系统返回）。
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// 分组容器。**不加内水平边距** —— 由行组件自带（AppListRow 为 16）。
/// ⚠️ 改造前此处是 28pt 圆角 + 零内边距，内容紧贴 x=0 落进圆角曲线被 clipShape 裁切，
///    这正是 Username 页 "Username" 与 "Account editing is coming later." 被切的原因。
///    需要自带边距的自由内容请改用 AppCard（它有 cardPadding 16）。
private struct MeGroupedSection<Content: View>: View {
    let title: String?
    let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                AppSectionHeader(title: title)
            }

            AppGroupedList {
                content()
            }
        }
    }
}

private struct MeValueRow: View {
    let title: String
    let value: String
    var showsChevron = false

    var body: some View {
        AppListRow(
            title: title,
            accessory: showsChevron ? .valueWithDisclosure(value) : .value(value)
        )
    }
}

private struct AvatarSettingsRow: View {
    let initial: String

    var body: some View {
        HStack(spacing: AppSpace.md) {
            Text("Avatar")
                .appText(AppType.headline)

            Spacer(minLength: AppSpace.md)

            Text(initial)
                .appText(AppType.label, color: AppColor.textOnInverse)
                .frame(width: AppLayout.avatarSM, height: AppLayout.avatarSM)
                .background(AppColor.surfaceInverse, in: Circle())

            Image(systemName: AppIcon.disclose)
                .font(AppIcon.font(AppLayout.iconSM))
                .foregroundStyle(AppColor.neutral400)
        }
        .padding(.horizontal, AppLayout.rowPaddingH)
        .padding(.vertical, AppLayout.rowPaddingV)
        .frame(minHeight: AppLayout.rowMinHeight)
        .contentShape(Rectangle())
    }
}

private struct MePlainActionRow: View {
    let title: String
    var isDestructive = false

    var body: some View {
        AppListRow(title: title, accessory: .none, isDestructive: isDestructive)
    }
}

/// Me 子页的行多为无图标的 MeValueRow，故缩进用 separatorInsetPlain(16)。
/// 有图标的行（Profile / Settings 分组）直接用 AppRowSeparator()，缩进 56。
private struct MeSeparator: View {
    var body: some View {
        AppRowSeparator(inset: AppLayout.separatorInsetPlain)
    }
}

private struct ActivityCalendarPreview: View {
    let records: [DailyLearningRecord]

    /// 无任何学习分钟数 = 空数据
    private var isEmpty: Bool {
        records.allSatisfy { $0.minutes <= 0 }
    }

    var body: some View {
        AppCard {
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
        MeGroupedSection {
            VStack(alignment: .leading, spacing: AppSpace.lg) {
                MonthlyCheckInCalendarGrid(
                    records: records,
                    selectedRecord: $selectedRecord
                )
            }
            .padding(AppLayout.cardPadding)
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
        MeGroupedSection {
            VStack(alignment: .leading, spacing: AppSpace.md) {
                Text(dayDetailTitle(for: record.date))
                    .appText(AppType.headline)

                VStack(spacing: AppSpace.sm) {
                    MeValueRow(title: "Learning time", value: "\(record.minutes) min")
                    MeSeparator()
                    MeValueRow(title: "Cards reviewed", value: "\(record.reviewed)")
                    MeSeparator()
                    MeValueRow(title: "Cards mastered", value: "\(record.mastered)")
                    MeSeparator()
                    MeValueRow(title: "New cards added", value: "\(record.newCards)")
                }
            }
            .padding(AppLayout.cardPadding)
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
