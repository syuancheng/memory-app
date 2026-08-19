import SwiftUI

private struct HomeHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeView: View {
    @EnvironmentObject private var dataStore: AppDataStore
    @Environment(\.locale) private var locale

    @State private var subjects: [AppSubject] = []
    @State private var summary: MeSummary?
    @State private var activeStudyMode: StudyMode?
    @State private var showingMessages = false
    @State private var showingLearnReviewReminder = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var headerHeight: CGFloat = 0
    @State private var quoteSentence: String?
    @State private var learningPreferences: LearningPreferences?

    /// 黄金分割比例：按钮区顶部落在屏幕高度的 61.8% 处，比正中间更贴近单手热区。
    private let goldenRatio: CGFloat = 0.618
    /// 句子太长会在这块空档里挤成一坨，超过这个字符数就宁可不放。
    private let maxQuoteSentenceLength = 70

    private var reviewDueCount: Int {
        summary?.reviewDueCount ?? subjects.reduce(0) { $0 + $1.dueCount }
    }

    private var newCardCount: Int {
        summary?.newCount ?? 0
    }

    /// 今天真正会出现在 Review session 里的卡数——new_plus_review 模式下复习不设上限，
    /// fixed_total 模式下和新卡共享每日总量上限。跟后端 buildDailyQueue 的口径保持一致。
    private var todayReviewCount: Int {
        guard let prefs = learningPreferences, prefs.limitMode == .fixedTotal else {
            return reviewDueCount
        }
        return min(reviewDueCount, prefs.totalCardsPerDay)
    }

    /// 今天真正会出现在 Learn session 里的新卡数——受「每日新卡上限」或
    /// 「每日总量上限减去今天复习占用」限制，而不是账号里全部新卡的总数。
    private var todayNewCardCount: Int {
        guard let prefs = learningPreferences else {
            return newCardCount
        }
        switch prefs.limitMode {
        case .newPlusReview:
            return min(newCardCount, prefs.newCardsPerDay)
        case .fixedTotal:
            let remaining = max(0, prefs.totalCardsPerDay - todayReviewCount)
            return min(newCardCount, remaining)
        }
    }

    private var reviewReminderTitle: String {
        todayReviewCount == 1 ? "1 card waiting for review" : "\(todayReviewCount) cards waiting for review"
    }

    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd E")
        return formatter.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let goldenGap = max(AppSpace.xxl, geometry.size.height * goldenRatio - headerHeight)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        homeHeader
                            .background {
                                GeometryReader { headerGeometry in
                                    Color.clear.preference(key: HomeHeaderHeightKey.self, value: headerGeometry.size.height)
                                }
                            }

                        quoteSentenceView
                            .frame(height: goldenGap)

                        VStack(alignment: .leading, spacing: AppLayout.cardGap) {
                            startLearningSection
                            loadState
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppLayout.screenMargin)
                    .padding(.top, AppSpace.lg)
                    .padding(.bottom, AppSpace.giant)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(HomeHeaderHeightKey.self) { headerHeight = $0 }
            }
            .background(AppColor.surfaceBase.ignoresSafeArea())
            // Tab 根屏用「样式 B · 大标题头」，本身没有导航栏内容，故隐藏原生栏。
            // 注意：这是 Tab 根屏专属；任何 push/present 出来的屏都必须保留原生栏。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingMessages) {
                MessageCenterView()
            }
        }
        .fullScreenCover(item: $activeStudyMode) { mode in
            SubjectPickerView(subjects: subjects, mode: mode)
        }
        .task {
            await loadHomeData()
        }
        .task {
            await loadQuoteSentence()
        }
        .task {
            await loadLearningPreferences()
        }
        .onReceive(dataStore.$subjects) { loadedSubjects in
            if !loadedSubjects.isEmpty {
                subjects = loadedSubjects
            }
        }
        .onReceive(dataStore.$summary) { loadedSummary in
            if let loadedSummary {
                summary = loadedSummary
            }
        }
        .onChange(of: activeStudyMode) { _, mode in
            if mode == nil {
                Task {
                    await loadHomeData(force: true)
                    await loadLearningPreferences()
                }
            }
        }
        .alert(reviewReminderTitle, isPresented: $showingLearnReviewReminder) {
            Button("Review now") {
                activeStudyMode = .review
            }

            Button("Still learn") {
                activeStudyMode = .learn
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reviewing due cards first keeps your memory schedule accurate.")
        }
    }

    private var homeHeader: some View {
        AppLargeHeader(title: todayTitle, subtitle: "Every big goal begins with a small step.", titleStyle: AppType.title1) {
            // badge 恒显，与改造前行为一致（尚无未读态数据源，不在本次视觉重构范围内）
            AppIconButton(
                icon: "bell",
                style: .plain,
                badge: true
            ) {
                showingMessages = true
            }
            .accessibilityLabel("Messages")
        }
    }

    @ViewBuilder
    private var quoteSentenceView: some View {
        if let quoteSentence {
            VStack {
                Spacer(minLength: 0)

                Text(quoteSentence)
                    .appText(AppType.headline, color: AppColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpace.xl)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
        }
    }

    private var startLearningSection: some View {
        HStack(spacing: AppSpace.md) {
            HomeStudyActionButton(
                title: "Review",
                subtitle: todayReviewCount == 1 ? "1 card due" : "\(todayReviewCount) cards due",
                icon: "arrow.clockwise",
                style: .filled
            ) {
                activeStudyMode = .review
            }

            HomeStudyActionButton(
                title: "Learn",
                subtitle: todayNewCardCount == 1 ? "1 new card" : "\(todayNewCardCount) new cards",
                icon: "plus",
                style: .light
            ) {
                if todayReviewCount > 0 {
                    showingLearnReviewReminder = true
                } else {
                    activeStudyMode = .learn
                }
            }
        }
        .accessibilityElement(children: .contain)
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
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadHomeData(force: Bool = false) async {
        if !force {
            if !dataStore.subjects.isEmpty {
                subjects = dataStore.subjects
            }
            if let cachedSummary = dataStore.cachedSummary {
                summary = cachedSummary
            }
        }

        isLoading = true
        errorMessage = nil
        do {
            let homeData = try await dataStore.refreshHomeData(force: force)
            subjects = homeData.subjects
            summary = homeData.summary
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadQuoteSentence() async {
        do {
            let cards = try await APIClient.shared.listDueCards(subjectID: "", setIDs: [], limit: 20)
            let candidates = cards
                .map { $0.englishSentence.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= maxQuoteSentenceLength }
            quoteSentence = candidates.randomElement()
        } catch {
            quoteSentence = nil
        }
    }

    private func loadLearningPreferences() async {
        learningPreferences = try? await APIClient.shared.getLearningPreferences()
    }
}

private struct HomeStudyActionButton: View {
    enum Style {
        case filled
        case light
    }

    let title: String
    let subtitle: String
    let icon: String
    let style: Style
    let action: () -> Void

    private var foreground: Color {
        switch style {
        case .filled:
            return AppColor.textOnInverse
        case .light:
            return AppColor.textPrimary
        }
    }

    private var secondaryForeground: Color {
        switch style {
        case .filled:
            return AppColor.textOnInverseSecondary
        case .light:
            return AppColor.textTertiary
        }
    }

    private var background: Color {
        switch style {
        case .filled:
            return AppColor.primary
        case .light:
            return AppColor.buttonOnInverse
        }
    }

    private var iconForeground: Color {
        switch style {
        case .filled:
            return AppColor.onButtonOnInverse
        case .light:
            return AppColor.primary
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpace.md) {
                HStack {
                    Image(systemName: icon)
                        .font(AppIcon.font(AppLayout.iconSM))
                        .foregroundStyle(iconForeground)
                        .frame(width: AppLayout.buttonHeightSmall, height: AppLayout.buttonHeightSmall)
                        .background(iconBackground, in: Circle())

                    Spacer(minLength: AppSpace.sm)

                    Image(systemName: "arrow.right")
                        .font(AppIcon.font(AppLayout.iconSM))
                        .foregroundStyle(secondaryForeground)
                }

                VStack(alignment: .leading, spacing: AppSpace.xs) {
                    Text(title)
                        .appText(AppType.headline, color: foreground)
                        .lineLimit(1)

                    Text(subtitle)
                        .appText(AppType.caption, color: secondaryForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .padding(AppSpace.md)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .background(background, in: AppRadius.shape(AppRadius.lg))
            .overlay {
                AppRadius.shape(AppRadius.lg)
                    .strokeBorder(borderColor, lineWidth: AppLayout.hairline)
            }
        }
        .buttonStyle(AppPressableStyle())
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private var iconBackground: Color {
        switch style {
        case .filled:
            return AppColor.buttonOnInverse.opacity(0.16)
        case .light:
            return AppColor.primarySoft
        }
    }

    private var borderColor: Color {
        switch style {
        case .filled:
            return AppColor.buttonOnInverse.opacity(0.14)
        case .light:
            return AppColor.border
        }
    }
}

struct CardsView: View {
    @State private var cards: [ReviewCard] = []
    @State private var subjects: [AppSubject] = []
    @State private var searchText = ""
    @State private var editorContext: CardEditorContext?
    @State private var showingCreateSet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredCards: [ReviewCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return cards
        }
        return cards.filter { card in
            card.frontText.lowercased().contains(query)
                || card.answerText.lowercased().contains(query)
                || (card.subjectName ?? "").lowercased().contains(query)
                || card.set.name.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .appText(AppType.label, color: AppColor.dangerText)
                        .listRowSeparator(.hidden)
                }

                ForEach(filteredCards) { card in
                    Button {
                        editorContext = CardEditorContext(card: card)
                    } label: {
                        CardListRow(card: card)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await delete(card)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editorContext = CardEditorContext(card: card)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(AppColor.primary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColor.surfaceBase)
            .navigationTitle("Cards")
            .searchable(text: $searchText, prompt: "Search cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    creationMenu
                }
            }
            .overlay {
                if !isLoading && filteredCards.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No cards yet" : "No matching cards",
                        systemImage: "rectangle.stack",
                        description: Text(searchText.isEmpty ? "Use the plus button to add your first English card." : "Try a different word, answer, subject, or set.")
                    )
                }
            }
            .task {
                await loadCards()
            }
            .refreshable {
                await loadCards()
            }
            .sheet(item: $editorContext) { context in
                CardEditorView(card: context.card, subjects: subjects) {
                    editorContext = nil
                    Task {
                        await loadCards()
                    }
                }
            }
            .sheet(isPresented: $showingCreateSet) {
                CreateSetView {
                    showingCreateSet = false
                    Task {
                        await loadCards()
                    }
                }
            }
        }
    }

    private var creationMenu: some View {
        Menu {
            Button {
                editorContext = CardEditorContext(card: nil)
            } label: {
                Label("Add Card", systemImage: "rectangle.stack.badge.plus")
            }

            Button {
                showingCreateSet = true
            } label: {
                Label("Create Set", systemImage: "folder.badge.plus")
            }

            Button {} label: {
                Label("Import Cards", systemImage: "tray.and.arrow.down")
            }
            .disabled(true)

            Button {} label: {
                Label("AI Create Card", systemImage: "sparkles")
            }
            .disabled(true)
        } label: {
            Image(systemName: AppIcon.add)
                .font(AppIcon.font(AppLayout.iconMD))
        }
        .accessibilityLabel("Create")
    }

    private func loadCards() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedSubjects = APIClient.shared.listSubjects()
            async let loadedCards = APIClient.shared.listCards()
            subjects = try await loadedSubjects
            cards = try await loadedCards
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ card: ReviewCard) async {
        do {
            try await APIClient.shared.deleteCard(card)
            cards.removeAll { $0.id == card.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AIView: View {
    // 图标一律 outline —— fill 只保留给"选中/激活"语义（见 AppIcon 约定）。
    // 这里不再逐项配色：这些是并列的待建功能，不存在需要区分的语义，
    // 上色只会制造五个假的强调点。统一走中性图标容器。
    private let features: [(String, String, String)] = [
        ("AI Chat", "Ask questions while reviewing English expressions.", "message"),
        ("AI Create", "Turn notes or examples into cards.", "rectangle.stack.badge.plus"),
        ("AI Improve", "Rewrite prompts and answers for clarity.", "wand.and.stars"),
        ("AI Explain", "Explain grammar, phrases, and usage context.", "text.bubble"),
        ("AI Split", "Break long text into reviewable cards.", "square.split.2x2")
    ]

    var body: some View {
        NavigationStack {
            AppScreen {
                AppLargeHeader(title: "AI", subtitle: "Smart English learning tools are coming here.")

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpace.md) {
                        Image(systemName: "wand.and.sparkles")
                            .font(AppIcon.font(AppLayout.iconLG))
                            .foregroundStyle(AppColor.primaryOnSoft)
                            .frame(width: AppLayout.avatarMD, height: AppLayout.avatarMD)
                            .background(AppColor.primarySoft, in: AppRadius.shape(AppRadius.md))

                        Text("Future AI workspace")
                            .appText(AppType.title2)

                        Text("This tab is reserved for AI-assisted learning. Real AI logic is intentionally not enabled yet.")
                            .appText(AppType.body, color: AppColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: AppLayout.cardGap) {
                    ForEach(features, id: \.0) { feature in
                        FeatureRow(title: feature.0, subtitle: feature.1, icon: feature.2)
                    }
                }
            }
            // Tab 根屏 = 样式 B
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct MessageCenterView: View {
    var body: some View {
        ZStack {
            AppColor.surfaceBase
                .ignoresSafeArea()

            AppEmptyState(
                icon: "bell",
                title: "No messages",
                message: "Review reminders, import results, AI task updates, sync issues, and system messages will appear here."
            )
            .padding(.horizontal, AppLayout.screenMargin)
        }
        // 样式 A：本屏由 navigationDestination push 出来，用原生导航栏
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct CardListRow: View {
    let card: ReviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.sm) {
            HStack(spacing: AppSpace.sm) {
                Text(card.subjectName ?? "English")
                    .appText(AppType.caption, color: AppColor.primaryOnSoft)
                    .padding(.horizontal, AppSpace.sm)
                    .padding(.vertical, AppSpace.xs)
                    .background(AppColor.primarySoft, in: Capsule())

                Text("\(card.answerTokens.count) terms")
                    .appText(AppType.caption, color: AppColor.textTertiary)

                Spacer()
            }

            Text(card.frontText)
                .appText(AppType.headline)
                .lineLimit(2)

            Text(card.answerText)
                .appText(AppType.body, color: AppColor.textTertiary)
                .lineLimit(2)

            Text(card.set.name)
                .appText(AppType.caption, color: AppColor.textSecondary)
                .padding(.horizontal, AppSpace.sm)
                .padding(.vertical, AppSpace.xs)
                .background(AppColor.surfaceSunken, in: Capsule())
        }
        .padding(.vertical, AppSpace.md)
    }
}

private struct CardEditorContext: Identifiable {
    let id = UUID()
    let card: ReviewCard?
}

private struct CardEditorView: View {
    let card: ReviewCard?
    let subjects: [AppSubject]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubjectID = ""
    @State private var sets: [AppSet] = []
    @State private var selectedSetID = ""
    @State private var frontText = ""
    @State private var answerText = ""
    @State private var phrases: [GrammarPhrasePayload] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        card != nil
    }

    private var canSave: Bool {
        !selectedSubjectID.isEmpty
            && !selectedSetID.isEmpty
            && !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .appText(AppType.body, color: AppColor.dangerText)
                    }
                }

                Section("Card") {
                    TextField("Prompt", text: $frontText, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Answer", text: $answerText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Set") {
                    Picker("Subject", selection: $selectedSubjectID) {
                        Text("Select subject").tag("")
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(subject.id)
                        }
                    }
                    .onChange(of: selectedSubjectID) { _, _ in
                        Task {
                            await loadSets()
                        }
                    }

                    if sets.isEmpty {
                        Text("Create a set first, or use an existing set.")
                            .appText(AppType.label, color: AppColor.textTertiary)
                    } else {
                        Picker("Set", selection: $selectedSetID) {
                            Text("Select set").tag("")
                            ForEach(sets) { set in
                                Text(set.name).tag(set.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    ForEach(phrases.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: AppSpace.sm) {
                            TextField("Phrase", text: phraseTextBinding(index))
                            TextField("Note", text: phraseNoteBinding(index))
                        }
                    }
                    .onDelete { offsets in
                        phrases.remove(atOffsets: offsets)
                    }

                    Button {
                        phrases.append(GrammarPhrasePayload(text: "", note: ""))
                    } label: {
                        Label("Add phrase hint", systemImage: "plus")
                    }
                } header: {
                    Text("Phrase hints")
                }
            }
            .navigationTitle(isEditing ? "Edit Card" : "Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .task {
                configureInitialState()
                await loadSets()
            }
        }
    }

    private func configureInitialState() {
        guard selectedSubjectID.isEmpty else {
            return
        }
        if let card {
            selectedSubjectID = card.subjectID
            selectedSetID = card.set.id
            frontText = card.frontText
            answerText = card.answerText
            phrases = card.grammarPhrases.map { GrammarPhrasePayload(text: $0.text, note: $0.note) }
        } else {
            selectedSubjectID = subjects.first?.id ?? ""
            phrases = [GrammarPhrasePayload(text: "", note: "")]
        }
    }

    private func loadSets() async {
        guard !selectedSubjectID.isEmpty else {
            sets = []
            selectedSetID = ""
            return
        }
        do {
            sets = try await APIClient.shared.listSets(subjectID: selectedSubjectID)
            if !sets.contains(where: { $0.id == selectedSetID }) {
                selectedSetID = sets.first?.id ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard canSave else {
            return
        }
        isSaving = true
        errorMessage = nil
        let payload = CardPayload(
            setID: selectedSetID,
            cardType: card?.cardType ?? "sentence",
            direction: card?.direction ?? "zh_to_en",
            frontText: frontText,
            answerText: answerText,
            grammarPhrases: phrases
                .map { GrammarPhrasePayload(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.text.isEmpty || !$0.note.isEmpty }
        )
        do {
            if let card {
                _ = try await APIClient.shared.updateCard(cardID: card.id, payload: payload)
            } else {
                _ = try await APIClient.shared.createCard(payload)
            }
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func phraseTextBinding(_ index: Int) -> Binding<String> {
        Binding {
            phrases[index].text
        } set: { newValue in
            phrases[index].text = newValue
        }
    }

    private func phraseNoteBinding(_ index: Int) -> Binding<String> {
        Binding {
            phrases[index].note
        } set: { newValue in
            phrases[index].note = newValue
        }
    }
}

private struct CreateSetView: View {
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var setName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .appText(AppType.body, color: AppColor.dangerText)
                    }
                }

                Section("Set") {
                    TextField("Set name", text: $setName)
                }
            }
            .navigationTitle("Create Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            _ = try await APIClient.shared.createSubject(name: setName)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct FeatureRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: AppSpace.md) {
            Image(systemName: icon)
                .font(AppIcon.font(AppLayout.iconMD))
                .foregroundStyle(AppColor.iconDefault)
                .frame(width: AppLayout.avatarSM, height: AppLayout.avatarSM)
                .background(AppColor.iconContainerBase, in: AppRadius.shape(AppRadius.sm))

            VStack(alignment: .leading, spacing: AppSpace.xs / 2) {
                Text(LocalizedStringKey(title))
                    .appText(AppType.headline)

                Text(LocalizedStringKey(subtitle))
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: AppSpace.sm)
        }
        .padding(AppLayout.cardPadding)
        .appSurface(.card)
    }
}

// AppSurface 已迁至 DesignSystem/LegacyBridge.swift（兼容层，指向 AppColor）。
// ScalePressStyle 已由 AppPressableStyle 取代（Components.swift）。
