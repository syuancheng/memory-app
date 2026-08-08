import SwiftUI

struct HomeView: View {
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
            ZStack {
                AppSurface.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        homeHeader
                        learningFocus
                        loadState
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
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
        .onChange(of: showingSubjects) { _, isPresented in
            if !isPresented {
                Task {
                    await loadHomeData()
                }
            }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                Text("AI flashcards for active recall")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppSurface.muted)
            }

            Spacer(minLength: 16)

            Button {
                showingMessages = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppSurface.text)
                        .frame(width: 44, height: 44)
                        .background(AppSurface.cardSubtle)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(AppSurface.line, lineWidth: 1)
                        )

                    Circle()
                        .fill(AppSurface.coral)
                        .frame(width: 9, height: 9)
                        .offset(x: -7, y: 7)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Messages")
        }
    }

    private var learningFocus: some View {
        VStack(spacing: 20) {
            dueSummaryCard
            startLearningCard
        }
        .padding(.top, 74)
    }

    private var dueSummaryCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DUE TODAY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppSurface.purple)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(dueCount)")
                        .font(.system(size: dueCount >= 100 ? 38 : 44, weight: .bold))
                        .foregroundStyle(AppSurface.text)
                        .monospacedDigit()
                        .minimumScaleFactor(0.74)

                    Text(dueCount == 1 ? "card waiting" : "cards waiting")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppSurface.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer(minLength: 8)

            Text("\(reviewedToday) done today")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppSurface.purple)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: AppSurface.shadow.opacity(0.06), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(AppSurface.purpleSoft)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color(hex: 0xEDE9FE), lineWidth: 1)
        )
        .shadow(color: AppSurface.shadow.opacity(0.07), radius: 14, x: 0, y: 10)
    }

    private var startLearningCard: some View {
        Button {
            showingSubjects = true
        } label: {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("START LEARNING")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppSurface.indigoLight)

                    Text("Review your\nEnglish cards")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Default: due cards · short session · review mode")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppSurface.slateLight)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppSurface.dark)
                    .frame(width: 52, height: 52)
                    .background(.white)
                    .clipShape(Circle())
            }
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 194, alignment: .leading)
            .background(AppSurface.dark)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .shadow(color: AppSurface.dark.opacity(0.16), radius: 24, x: 0, y: 16)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Start learning")
    }

    @ViewBuilder
    private var loadState: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(AppSurface.accent)
                Spacer()
            }
            .padding(.top, 20)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(AppSurface.coral)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    private func loadHomeData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedSubjects = APIClient.shared.listSubjects()
            async let loadedSummary = APIClient.shared.getMeSummary()
            subjects = try await loadedSubjects
            summary = try await loadedSummary
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
                || card.tags.contains { $0.name.lowercased().contains(query) }
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
                        .font(.footnote)
                        .foregroundStyle(AppSurface.coral)
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
                        .tint(AppSurface.accent)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppSurface.background)
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
                        description: Text(searchText.isEmpty ? "Use the plus button to add your first English card." : "Try a different word, answer, subject, or tag.")
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
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
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
    private let features: [(String, String, String, Color)] = [
        ("AI Chat", "Ask questions while reviewing English expressions.", "message.fill", AppSurface.purple),
        ("AI Create", "Turn notes or examples into cards.", "rectangle.stack.badge.plus", AppSurface.sky),
        ("AI Improve", "Rewrite prompts and answers for clarity.", "wand.and.stars", AppSurface.rose),
        ("AI Explain", "Explain grammar, phrases, and usage context.", "text.bubble.fill", AppSurface.green),
        ("AI Split", "Break long text into reviewable cards.", "square.split.2x2.fill", AppSurface.amber)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(AppSurface.text)

                        Text("Smart English learning tools are coming here.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppSurface.muted)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppSurface.rose)
                            .frame(width: 58, height: 58)
                            .background(AppSurface.roseSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text("Future AI workspace")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppSurface.text)

                        Text("This tab is reserved for AI-assisted learning. Real AI logic is intentionally not enabled yet.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppSurface.muted)
                            .lineSpacing(3)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(AppSurface.line, lineWidth: 1)
                    )
                    .shadow(color: AppSurface.shadow.opacity(0.06), radius: 18, x: 0, y: 10)

                    VStack(spacing: 12) {
                        ForEach(features, id: \.0) { feature in
                            FeatureRow(title: feature.0, subtitle: feature.1, icon: feature.2, tint: feature.3)
                        }
                    }
                }
                .padding(24)
            }
            .background(AppSurface.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct MessageCenterView: View {
    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppSurface.accent)
                    .frame(width: 72, height: 72)
                    .background(AppSurface.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("No messages")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppSurface.text)

                Text("Review reminders, import results, AI task updates, sync issues, and system messages will appear here.")
                    .font(.system(size: 15))
                    .foregroundStyle(AppSurface.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
            }
            .padding(24)
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct CardListRow: View {
    let card: ReviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(card.subjectName ?? "English")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppSurface.sky)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppSurface.skySoft)
                    .clipShape(Capsule())

                Text("\(card.answerTokens.count) terms")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppSurface.muted)

                Spacer()
            }

            Text(card.frontText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppSurface.text)
                .lineLimit(2)

            Text(card.answerText)
                .font(.system(size: 14))
                .foregroundStyle(AppSurface.muted)
                .lineLimit(2)

            if !card.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(card.tags) { tag in
                            Text(tag.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppSurface.textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(AppSurface.cardSubtle)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
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
    @State private var tags: [AppTag] = []
    @State private var selectedTagIDs: Set<String> = []
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
            && !selectedTagIDs.isEmpty
            && !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(AppSurface.coral)
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
                            await loadTags()
                        }
                    }

                    if tags.isEmpty {
                        Text("Create a set and tag on the web app first, or use an existing set with tags.")
                            .font(.footnote)
                            .foregroundStyle(AppSurface.muted)
                    } else {
                        ForEach(tags) { tag in
                            Toggle(tag.name, isOn: tagBinding(tag.id))
                        }
                    }
                }

                Section {
                    ForEach(phrases.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
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
                await loadTags()
            }
        }
    }

    private func configureInitialState() {
        guard selectedSubjectID.isEmpty else {
            return
        }
        if let card {
            selectedSubjectID = card.subjectID
            selectedTagIDs = Set(card.tags.map(\.id))
            frontText = card.frontText
            answerText = card.answerText
            phrases = card.grammarPhrases.map { GrammarPhrasePayload(text: $0.text, note: $0.note) }
        } else {
            selectedSubjectID = subjects.first?.id ?? ""
            phrases = [GrammarPhrasePayload(text: "", note: "")]
        }
    }

    private func loadTags() async {
        guard !selectedSubjectID.isEmpty else {
            tags = []
            selectedTagIDs = []
            return
        }
        do {
            tags = try await APIClient.shared.listTags(subjectID: selectedSubjectID)
            selectedTagIDs = selectedTagIDs.filter { tagID in
                tags.contains { $0.id == tagID }
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
            subjectID: selectedSubjectID,
            tagIDs: Array(selectedTagIDs),
            cardType: card?.cardType ?? "speaking_expression",
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

    private func tagBinding(_ tagID: String) -> Binding<Bool> {
        Binding {
            selectedTagIDs.contains(tagID)
        } set: { isSelected in
            if isSelected {
                selectedTagIDs.insert(tagID)
            } else {
                selectedTagIDs.remove(tagID)
            }
        }
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
                            .foregroundStyle(AppSurface.coral)
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
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppSurface.text)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.muted)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppSurface.line, lineWidth: 1)
        )
    }
}

private struct ScalePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

enum AppSurface {
    static let background = Color(hex: 0xFBFBFC)
    static let cardSubtle = Color(hex: 0xF4F5F7)
    static let grouped = Color(hex: 0xF1F2F5)
    static let floating = Color(hex: 0xFFFFFF)
    static let text = Color(hex: 0x111827)
    static let textSecondary = Color(hex: 0x374151)
    static let muted = Color(hex: 0x6B7280)
    static let line = Color(hex: 0xE7E8EC)
    static let shadow = Color(hex: 0x171C2E)
    static let dark = Color(hex: 0x111827)
    static let accent = Color(hex: 0x4F46E5)
    static let accentSoft = Color(hex: 0xEEF2FF)
    static let iconAccent = Color(hex: 0x3F6D84)
    static let iconSoft = Color(hex: 0xE9EEF2)
    static let purple = Color(hex: 0x7C3AED)
    static let purpleSoft = Color(hex: 0xF7F3FF)
    static let indigoLight = Color(hex: 0xA5B4FC)
    static let slateLight = Color(hex: 0xCBD5E1)
    static let coral = Color(hex: 0xFF6B6B)
    static let sky = Color(hex: 0x0284C7)
    static let skySoft = Color(hex: 0xE0F2FE)
    static let rose = Color(hex: 0xE11D48)
    static let roseSoft = Color(hex: 0xFFF1F2)
    static let green = Color(hex: 0x059669)
    static let amber = Color(hex: 0xB7791F)
}
