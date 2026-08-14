import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var dataStore: AppDataStore

    @State private var subjects: [AppSubject] = []
    @State private var summary: MeSummary?
    @State private var showingSubjects = false
    @State private var showingMessages = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var dueCount: Int {
        summary?.dueCount ?? subjects.reduce(0) { $0 + $1.dueCount }
    }

    private var reviewedToday: Int {
        summary?.reviewedToday ?? 0
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                homeHeader
                learningFocus
                loadState
            }
            // Tab 根屏用「样式 B · 大标题头」，本身没有导航栏内容，故隐藏原生栏。
            // 注意：这是 Tab 根屏专属；任何 push/present 出来的屏都必须保留原生栏。
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingMessages) {
                MessageCenterView()
            }
        }
        .fullScreenCover(isPresented: $showingSubjects) {
            SubjectPickerView(subjects: subjects, mode: .review)
        }
        .task {
            await loadHomeData()
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
        .onChange(of: showingSubjects) { _, isPresented in
            if !isPresented {
                Task {
                    await loadHomeData(force: true)
                }
            }
        }
    }

    private var homeHeader: some View {
        AppLargeHeader(title: "Today", subtitle: "AI flashcards for active recall") {
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

    /// 两张卡属于同一个「今日焦点」语义单元，用 cardGap 收紧；
    /// 与大标题之间的间距由 AppScreen 的 xxl 统一提供（原先是硬编码 .padding(.top, 74)）。
    private var learningFocus: some View {
        VStack(spacing: AppLayout.cardGap) {
            dueSummaryCard
            startLearningCard
        }
    }

    private var dueSummaryCard: some View {
        AppCard {
            HStack(alignment: .center, spacing: AppSpace.lg) {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    Text("Due today")
                        .appText(AppType.label, color: AppColor.textTertiary)

                    HStack(alignment: .firstTextBaseline, spacing: AppSpace.sm) {
                        Text("\(dueCount)")
                            .appText(AppType.title1)
                            .monospacedDigit()
                            .minimumScaleFactor(0.74)

                        Text(dueCount == 1 ? "card waiting" : "cards waiting")
                            .appText(AppType.body, color: AppColor.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }

                Spacer(minLength: AppSpace.sm)

                Text("\(reviewedToday) done today")
                    .appText(AppType.label, color: AppColor.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, AppSpace.md)
                    .frame(height: AppLayout.buttonHeightSmall)
                    .background(AppColor.surfaceSunken, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var startLearningCard: some View {
        Button {
            showingSubjects = true
        } label: {
            AppCard(variant: .inverse, padding: AppSpace.xl) {
                HStack(alignment: .bottom, spacing: AppSpace.lg) {
                    VStack(alignment: .leading, spacing: AppSpace.sm) {
                        Text("Start learning")
                            .appText(AppType.label, color: AppColor.primaryOnInverse)

                        Text("Review your English cards")
                            .appText(AppType.title2, color: AppColor.textOnInverse)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Default: due cards · short session · review mode")
                            .appText(AppType.body, color: AppColor.textOnInverseSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, AppSpace.xs)
                    }

                    Spacer(minLength: AppSpace.sm)

                    Image(systemName: "arrow.right")
                        .font(AppIcon.font(AppLayout.iconMD))
                        .foregroundStyle(AppColor.onButtonOnInverse)
                        .frame(width: AppLayout.avatarMD, height: AppLayout.avatarMD)
                        .background(AppColor.buttonOnInverse, in: Circle())
                }
            }
        }
        .buttonStyle(AppPressableStyle())
        .accessibilityLabel("Start learning: review your English cards")
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
                Text(title)
                    .appText(AppType.headline)

                Text(subtitle)
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
