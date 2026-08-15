import SwiftUI

struct CardsHierarchyView: View {
    var body: some View {
        NavigationStack {
            CardsRootPage()
        }
        .tint(AppColor.primary)
    }
}

private struct CardsRootPage: View {
    @EnvironmentObject private var dataStore: AppDataStore

    @State private var subjects: [AppSubject] = []
    @State private var setsBySubjectID: [String: [AppSet]] = [:]
    @State private var cards: [ReviewCard] = []
    @State private var subjectMetadata: [String: SubjectPresentation] = [:]
    @State private var searchText = ""
    @State private var selectedSubject: AppSubject?
    @State private var activeSheet: CardsSheet?
    @State private var deletingSubject: AppSubject?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredSubjects: [AppSubject] {
        let query = searchText.normalizedQuery
        guard !query.isEmpty else {
            return subjects
        }

        return subjects.filter { subject in
            subject.name.normalizedQuery.contains(query)
                || subjectDescription(subject).normalizedQuery.contains(query)
                || (setsBySubjectID[subject.id] ?? []).contains { $0.name.normalizedQuery.contains(query) }
                || cards.contains { card in
                    card.subjectID == subject.id
                        && (card.frontText.normalizedQuery.contains(query)
                            || card.answerText.normalizedQuery.contains(query)
                            || card.set.name.normalizedQuery.contains(query))
                }
        }
    }

    var body: some View {
        CardsManagementPage(
            title: "Cards",
            subtitle: "Manage subjects, sets, and cards",
            trailing: {
                rootCreationMenu
            }
        ) {
            CardsSearchField(text: $searchText, prompt: "Search subjects, sets, cards...")

            CardsSectionTitle("Subjects")
                .padding(.top, AppSpace.sm)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredSubjects.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No subjects yet" : "No matching subjects",
                    message: searchText.isEmpty ? "Create your first English learning subject." : "Try another subject, set, or card keyword."
                )
                .padding(.top, AppSpace.sm)
            } else {
                LazyVStack(spacing: AppLayout.cardGap) {
                    ForEach(filteredSubjects) { subject in
                        CardsSubjectRow(
                            subject: subject,
                            initial: subjectInitial(subject, metadata: subjectMetadata[subject.id]),
                            description: subjectDisplayDescription(subject, metadata: subjectMetadata[subject.id]),
                            setCount: setsBySubjectID[subject.id]?.count ?? 0,
                            tint: subjectTint(subject, metadata: subjectMetadata[subject.id]),
                            onOpen: {
                                selectedSubject = subject
                            },
                            onEdit: {
                                activeSheet = .editSubject(subject)
                            },
                            onDelete: {
                                deletingSubject = subject
                            }
                        )
                    }
                }

            }
        }
        .navigationDestination(item: $selectedSubject) { subject in
            SubjectSetsPage(subject: subject)
        }
        .task {
            await loadData()
        }
        .onReceive(dataStore.$subjects) { _ in
            applyCachedLibrary()
        }
        .onReceive(dataStore.$sets) { _ in
            applyCachedLibrary()
        }
        .onReceive(dataStore.$cards) { _ in
            applyCachedLibrary()
        }
        .refreshable {
            await loadData(force: true)
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addSubject:
                SubjectEditPage(subject: nil, metadata: nil) {
                    await loadData(force: true)
                }
            case .editSubject(let subject):
                SubjectEditPage(subject: subject, metadata: subjectMetadata[subject.id]) {
                    await loadData(force: true)
                }
            case .addSet(let subject):
                SetEditPage(subjects: subjects, fixedSubject: subject, set: nil, metadata: nil) {
                    await loadData(force: true)
                }
            case .editSet(let subject, let set):
                SetEditPage(subjects: subjects, fixedSubject: subject, set: set, metadata: CardsMetadataStore.setMetadata()[set.id]) {
                    await loadData(force: true)
                }
            case .addCard(let subject, let set):
                CardEditPage(card: nil, subjects: subjects, fixedSubject: subject, fixedSet: set) {
                    await loadData(force: true)
                }
            case .editCard(let card, let subject):
                CardEditPage(card: card, subjects: subjects, fixedSubject: subject, fixedSet: nil) {
                    await loadData(force: true)
                }
            }
        }
        .confirmationDialog(
            "Delete subject?",
            isPresented: Binding(
                get: { deletingSubject != nil },
                set: { if !$0 { deletingSubject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Subject", role: .destructive) {
                guard let subject = deletingSubject else {
                    return
                }
                Task {
                    await delete(subject)
                }
            }
        } message: {
            Text("Deleting this subject will also affect all sets and cards under it.")
        }
    }

    private var rootCreationMenu: some View {
        Menu {
            Button {
                activeSheet = .addSubject
            } label: {
                Label("Add Subject", systemImage: "folder.badge.plus")
            }

            Button {
                activeSheet = .addSet(nil)
            } label: {
                Label("Add Set", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(subjects.isEmpty)

            Button {
                activeSheet = .addCard(nil, nil)
            } label: {
                Label("Add Card", systemImage: "plus.rectangle.on.rectangle")
            }
            .disabled(subjects.isEmpty)
        } label: {
            CardsIconButton(systemName: AppIcon.add, tint: AppColor.primary)
        }
        .accessibilityLabel("Create")
    }

    private func loadData(force: Bool = false) async {
        if !force {
            applyCachedLibrary()
        }

        isLoading = true
        errorMessage = nil
        do {
            let library = try await dataStore.refreshLibrary(force: force)

            let setMap = Dictionary(grouping: library.sets, by: \.subjectID)

            subjects = library.subjects
            cards = library.cards
            setsBySubjectID = setMap
            subjectMetadata = CardsMetadataStore.subjectMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyCachedLibrary() {
        guard let cached = dataStore.cachedLibrary else {
            return
        }

        subjects = cached.subjects
        cards = cached.cards
        setsBySubjectID = Dictionary(grouping: cached.sets, by: \.subjectID)
        subjectMetadata = CardsMetadataStore.subjectMetadata()
    }

    private func delete(_ subject: AppSubject) async {
        do {
            try await APIClient.shared.deleteSubject(subjectID: subject.id)
            dataStore.invalidateAfterSubjectMutation()
            deletingSubject = nil
            await loadData(force: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SubjectSetsPage: View {
    let subject: AppSubject

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var sets: [AppSet] = []
    @State private var cards: [ReviewCard] = []
    @State private var setMetadata: [String: SetPresentation] = [:]
    @State private var searchText = ""
    @State private var selectedSet: AppSet?
    @State private var activeSheet: CardsSheet?
    @State private var deletingSet: AppSet?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredSets: [AppSet] {
        let query = searchText.normalizedQuery
        guard !query.isEmpty else {
            return sets
        }

        return sets.filter { set in
            set.name.normalizedQuery.contains(query)
                || setDescription(set, subject: subject).normalizedQuery.contains(query)
                || cards.contains { card in
                    card.set.id == set.id
                        && (card.frontText.normalizedQuery.contains(query)
                            || card.answerText.normalizedQuery.contains(query))
                }
        }
    }

    var body: some View {
        CardsManagementPage(
            title: subject.name,
            subtitle: "\(sets.count) sets · \(subject.cardCount) cards",
            onBack: dismiss.callAsFunction,
            trailing: {
                subjectCreationMenu
            }
        ) {
            CardsSearchField(text: $searchText, prompt: "Search sets or cards...")

            CardsSectionTitle("Sets")
                .padding(.top, AppSpace.sm)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredSets.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No sets yet" : "No matching sets",
                    message: searchText.isEmpty ? "Create a set under this subject." : "Try another set or card keyword."
                )
                .padding(.top, AppSpace.sm)
            } else {
                LazyVStack(spacing: AppLayout.cardGap) {
                    ForEach(filteredSets) { set in
                        CardsSetRow(
                            set: set,
                            description: setDisplayDescription(set, subject: subject, metadata: setMetadata[set.id]),
                            onOpen: {
                                selectedSet = set
                            },
                            onEdit: {
                                activeSheet = .editSet(subject, set)
                            },
                            onDelete: {
                                deletingSet = set
                            }
                        )
                    }
                }

            }
        }
        .navigationDestination(item: $selectedSet) { set in
            SetCardsPage(subject: subject, set: set)
        }
        .task {
            await loadData()
        }
        .onReceive(dataStore.$sets) { _ in
            applyCachedSubjectData()
        }
        .onReceive(dataStore.$cards) { _ in
            applyCachedSubjectData()
        }
        .refreshable {
            await loadData(force: true)
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addSet(_):
                SetEditPage(subjects: [subject], fixedSubject: subject, set: nil, metadata: nil) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .editSet(_, let set):
                SetEditPage(subjects: [subject], fixedSubject: subject, set: set, metadata: setMetadata[set.id]) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .addCard(_, let set):
                CardEditPage(card: nil, subjects: [subject], fixedSubject: subject, fixedSet: set) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .editCard(let card, _):
                CardEditPage(card: card, subjects: [subject], fixedSubject: subject, fixedSet: nil) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .addSubject, .editSubject:
                EmptyView()
            }
        }
        .confirmationDialog(
            "Delete set?",
            isPresented: Binding(
                get: { deletingSet != nil },
                set: { if !$0 { deletingSet = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Set", role: .destructive) {
                guard let set = deletingSet else {
                    return
                }
                Task {
                    await delete(set)
                }
            }
        } message: {
            Text("Deleting this set will also affect all cards under it.")
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var subjectCreationMenu: some View {
        Menu {
            Button {
                activeSheet = .addSet(subject)
            } label: {
                Label("Add Set", systemImage: "rectangle.stack.badge.plus")
            }

            Button {
                activeSheet = .addCard(subject, nil)
            } label: {
                Label("Add Card", systemImage: "plus.rectangle.on.rectangle")
            }
        } label: {
            CardsIconButton(systemName: AppIcon.add, tint: AppColor.primary)
        }
        .accessibilityLabel("Create")
    }

    private func loadData(force: Bool = false) async {
        if !force {
            applyCachedSubjectData()
        }

        isLoading = true
        errorMessage = nil
        do {
            async let loadedSets = dataStore.refreshSets(subjectID: subject.id, force: force)
            async let loadedCards = dataStore.refreshCards(subjectID: subject.id, force: force)
            sets = try await loadedSets
            cards = try await loadedCards
            setMetadata = CardsMetadataStore.setMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyCachedSubjectData() {
        if let cachedSets = dataStore.cachedSets(subjectID: subject.id) {
            sets = cachedSets
        }
        if let cachedCards = dataStore.cachedCards(subjectID: subject.id) {
            cards = cachedCards
        }
        setMetadata = CardsMetadataStore.setMetadata()
    }

    private func delete(_ set: AppSet) async {
        do {
            try await APIClient.shared.deleteSet(subjectID: subject.id, setID: set.id)
            dataStore.invalidateAfterSetMutation()
            deletingSet = nil
            await loadData(force: true)
            await dataStore.warmLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetCardsPage: View {
    let subject: AppSubject
    let set: AppSet

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var cards: [ReviewCard] = []
    @State private var searchText = ""
    @State private var activeSheet: CardsSheet?
    @State private var deletingCard: ReviewCard?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredCards: [ReviewCard] {
        let query = searchText.normalizedQuery
        guard !query.isEmpty else {
            return cards
        }

        return cards.filter { card in
            card.frontText.normalizedQuery.contains(query)
                || card.answerText.normalizedQuery.contains(query)
                || card.set.name.normalizedQuery.contains(query)
        }
    }

    var body: some View {
        CardsManagementPage(
            title: set.name,
            subtitle: "\(set.cardCount) cards · \(set.dueCount) due",
            onBack: dismiss.callAsFunction,
            trailing: {
                setCreationMenu
            }
        ) {
            CardsSearchField(text: $searchText, prompt: "Search cards...")

            CardsSectionTitle("Cards")
                .padding(.top, AppSpace.sm)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredCards.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No cards yet" : "No matching cards",
                    message: searchText.isEmpty ? "Add your first card to this set." : "Try another prompt, answer, or set keyword."
                )
                .padding(.top, AppSpace.sm)
            } else {
                LazyVStack(spacing: AppLayout.cardGap) {
                    ForEach(filteredCards) { card in
                        CardsCardRow(
                            card: card,
                            onEdit: {
                                activeSheet = .editCard(card, subject)
                            },
                            onDelete: {
                                deletingCard = card
                            }
                        )
                    }
                }

            }
        }
        .task {
            await loadData()
        }
        .onReceive(dataStore.$cards) { _ in
            applyCachedSetData()
        }
        .refreshable {
            await loadData(force: true)
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addCard(_, _):
                CardEditPage(card: nil, subjects: [subject], fixedSubject: subject, fixedSet: set) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .editCard(let card, _):
                CardEditPage(card: card, subjects: [subject], fixedSubject: subject, fixedSet: nil) {
                    await loadData(force: true)
                    await dataStore.warmLibrary()
                }
            case .addSubject, .editSubject, .addSet, .editSet:
                EmptyView()
            }
        }
        .confirmationDialog(
            "Delete card?",
            isPresented: Binding(
                get: { deletingCard != nil },
                set: { if !$0 { deletingCard = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Card", role: .destructive) {
                guard let card = deletingCard else {
                    return
                }
                Task {
                    await delete(card)
                }
            }
        } message: {
            Text("This card will be removed from review.")
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var setCreationMenu: some View {
        Menu {
            Button {
                activeSheet = .addCard(subject, set)
            } label: {
                Label("Add Card", systemImage: "plus.rectangle.on.rectangle")
            }
        } label: {
            CardsIconButton(systemName: AppIcon.add, tint: AppColor.primary)
        }
        .accessibilityLabel("Create")
    }

    private func loadData(force: Bool = false) async {
        if !force {
            applyCachedSetData()
        }

        isLoading = true
        errorMessage = nil
        do {
            cards = try await dataStore.refreshCards(subjectID: subject.id, setIDs: [set.id], force: force)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyCachedSetData() {
        if let cachedCards = dataStore.cachedCards(subjectID: subject.id, setIDs: [set.id]) {
            cards = cachedCards
        }
    }

    private func delete(_ card: ReviewCard) async {
        do {
            try await APIClient.shared.deleteCard(card)
            dataStore.invalidateAfterCardMutation(cardID: card.id)
            deletingCard = nil
            await loadData(force: true)
            await dataStore.warmLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CardsSheet: Identifiable {
    case addSubject
    case editSubject(AppSubject)
    case addSet(AppSubject?)
    case editSet(AppSubject, AppSet)
    case addCard(AppSubject?, AppSet?)
    case editCard(ReviewCard, AppSubject?)

    var id: String {
        switch self {
        case .addSubject:
            return "add-subject"
        case .editSubject(let subject):
            return "edit-subject-\(subject.id)"
        case .addSet(let subject):
            return "add-set-\(subject?.id ?? "any")"
        case .editSet(_, let set):
            return "edit-set-\(set.id)"
        case .addCard(let subject, let set):
            return "add-card-\(subject?.id ?? "any")-\(set?.id ?? "any")"
        case .editCard(let card, _):
            return "edit-card-\(card.id)"
        }
    }
}

private struct CardsManagementPage<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)?
    let trailing: () -> Trailing
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailing = trailing
        self.content = content
    }

    // 导航样式按「本屏可否返回」自动分流，三个调用点无需改动：
    //   onBack == nil  → Tab 根屏（CardsRootPage）→ 样式 B 大标题头
    //   onBack != nil  → 被 push 的屏（SubjectSetsPage / SetCardsPage）→ 样式 A 原生导航栏
    // 样式 A 下 NavigationStack 已自带返回键，故不再自绘；subtitle 降为内容首行，信息不丢。
    var body: some View {
        if onBack == nil {
            AppScreen {
                AppLargeHeader(title: title, subtitle: subtitle, trailing: trailing)
                content()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        } else {
            AppScreen {
                Text(LocalizedStringKey(subtitle))
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(2)

                content()
            }
            .appNavBar(title, trailing: trailing)
        }
    }
}

/// Menu 的 label 必须是普通 View（不能是 Button），所以这里不能直接用 AppIconButton。
/// 视觉与 AppIconButton(.plain) 保持一致：36pt 圆 + border 描边，外层热区 44。
private struct CardsIconButton: View {
    let systemName: String
    var tint: Color = AppColor.iconDefault

    var body: some View {
        Circle()
            .fill(AppColor.surface)
            .overlay { Circle().strokeBorder(AppColor.border, lineWidth: AppLayout.hairline) }
            .frame(width: AppLayout.navIconButton, height: AppLayout.navIconButton)
            .overlay {
                Image(systemName: systemName)
                    .font(AppIcon.font(AppLayout.iconMD))
                    .foregroundStyle(tint)
            }
            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
            .contentShape(Circle())
    }
}

private struct CardsSearchField: View {
    @Binding var text: String
    let prompt: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpace.sm) {
            Image(systemName: AppIcon.search)
                .font(AppIcon.font(AppLayout.iconSM))
                .foregroundStyle(AppColor.iconMuted)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(LocalizedStringKey(prompt))
                        .appText(AppType.body, color: AppColor.textPlaceholder)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .appText(AppType.body)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal, AppSpace.lg)
        .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeightMedium)
        .background(isFocused ? AppColor.surface : AppColor.surfaceSunken, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isFocused ? AppColor.focusRing : AppColor.borderStrong,
                lineWidth: isFocused ? AppLayout.focusRingWidth : AppLayout.hairline
            )
        }
        .animation(AppMotion.instant, value: isFocused)
    }
}

private struct CardsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        AppSectionHeader(title: title)
    }
}

private struct CardsLoadState: View {
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
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
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CardsEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        AppCard(padding: 0) {
            AppEmptyState(title: title, message: message)
        }
    }
}

private struct CardsSubjectRow: View {
    let subject: AppSubject
    let initial: String
    let description: String
    let setCount: Int
    let tint: AppColor.SubjectAccent
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpace.md) {
            InitialBadge(text: initial, tint: tint)

            VStack(alignment: .leading, spacing: AppSpace.xs) {
                Text(subject.name)
                    .appText(AppType.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(description)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(2)

                Text("\(setCount) sets · \(subject.cardCount) cards")
                    .appText(AppType.label, color: tint.text)   // .text 而非 .fill —— 保证 AA
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpace.sm)

            CardsRowMenu(
                editTitle: "Edit Subject",
                deleteTitle: "Delete Subject",
                onEdit: onEdit,
                onDelete: onDelete
            )

            Image(systemName: AppIcon.disclose)
                .font(AppIcon.font(AppLayout.iconSM))
                .foregroundStyle(AppColor.neutral400)
        }
        .cardsRowSurface()
        .contentShape(AppRadius.shape(AppRadius.lg))
        .onTapGesture {
            onOpen()
        }
    }
}

private struct CardsSetRow: View {
    let set: AppSet
    let description: String
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: AppSpace.md) {
            AppTypeBadge(icon: AppIcon.typeSet)

            VStack(alignment: .leading, spacing: AppSpace.xs) {
                Text(set.name)
                    .appText(AppType.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(description)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(1)

                Text("\(set.cardCount) cards · \(set.dueCount) due")
                    .appText(AppType.label, color: AppColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: AppSpace.sm)

            CardsRowMenu(
                editTitle: "Edit Set",
                deleteTitle: "Delete Set",
                onEdit: onEdit,
                onDelete: onDelete
            )

            Image(systemName: AppIcon.disclose)
                .font(AppIcon.font(AppLayout.iconSM))
                .foregroundStyle(AppColor.neutral400)
        }
        .cardsRowSurface()
        .contentShape(AppRadius.shape(AppRadius.lg))
        .onTapGesture {
            onOpen()
        }
    }
}

private struct CardsCardRow: View {
    let card: ReviewCard
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpace.md) {
            AppTypeBadge(icon: AppIcon.typeCard)

            VStack(alignment: .leading, spacing: AppSpace.sm) {
                Text(card.answerText)
                    .appText(AppType.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(card.frontText)
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .lineLimit(2)

                Text(cardMetadata(card))
                    .appText(AppType.caption, color: AppColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            CardsRowMenu(
                editTitle: "Edit Card",
                deleteTitle: "Delete Card",
                onEdit: onEdit,
                onDelete: onDelete
            )
        }
        .cardsRowSurface()
    }
}

private struct InitialBadge: View {
    let text: String
    let tint: AppColor.SubjectAccent

    var body: some View {
        Text(text)
            .appText(text.count > 1 ? AppType.caption : AppType.headline, color: tint.text)
            .frame(width: AppLayout.avatarMD, height: AppLayout.avatarMD)
            .background(tint.soft, in: Circle())   // 实色浅底，不再用 .opacity(0.13)
    }
}

private struct CardsRowMenu: View {
    let editTitle: String
    let deleteTitle: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label(editTitle, systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(deleteTitle, systemImage: "trash")
            }
        } label: {
            Image(systemName: AppIcon.more)
                .font(AppIcon.font(AppLayout.iconMD))
                .foregroundStyle(AppColor.iconMuted)
                .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }
}

private struct SubjectEditPage: View {
    let subject: AppSubject?
    let metadata: SubjectPresentation?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var name: String
    @State private var description: String
    @State private var initial: String
    @State private var accent: CardsAccentChoice
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(subject: AppSubject?, metadata: SubjectPresentation?, onDone: @escaping () async -> Void) {
        self.subject = subject
        self.metadata = metadata
        self.onDone = onDone
        _name = State(initialValue: subject?.name ?? "")
        _description = State(initialValue: metadata?.description ?? subject.map(subjectDescription) ?? "")
        _initial = State(initialValue: metadata?.initial ?? subject?.name.initialLetter ?? "")
        _accent = State(initialValue: metadata.flatMap { CardsAccentChoice(rawValue: $0.accent) } ?? .indigo)
    }

    private var canSave: Bool {
        !name.trimmed.isEmpty && !isSaving
    }

    var body: some View {
        CardsEditPageScaffold(
            title: "Subject",
            subtitle: "Create or edit a learning subject",
            canSave: canSave,
            onBack: dismiss.callAsFunction,
            onSave: {
                await save()
            }
        ) {
            CardsFormSection {
                CardsLabeledTextField(title: "Subject name", text: $name, prompt: "")
                CardsLabeledTextArea(title: "Description", text: $description, prompt: "", minHeight: 92)
            }

            CardsFormSection {
                CardsLabeledTextField(title: "Icon / initial", text: $initial, prompt: "")
                CardsAccentPicker(selection: $accent)
            }

            if let errorMessage {
                CardsFormError(message: errorMessage)
            }

            if subject != nil {
                CardsDangerZone(
                    title: "Delete Subject",
                    message: "Deleting this subject will also affect all sets and cards under it.",
                    actionTitle: "Delete Subject"
                ) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete subject?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Subject", role: .destructive) {
                Task {
                    await deleteSubject()
                }
            }
        } message: {
            Text("Deleting this subject will also affect all sets and cards under it.")
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let savedSubject: AppSubject
            if let subject {
                savedSubject = try await APIClient.shared.updateSubject(subjectID: subject.id, name: name.trimmed)
            } else {
                savedSubject = try await APIClient.shared.createSubject(name: name.trimmed)
            }

            CardsMetadataStore.saveSubjectMetadata(
                SubjectPresentation(
                    description: description.trimmed,
                    initial: normalizedInitial(fallback: savedSubject.name.initialLetter),
                    accent: accent.rawValue
                ),
                for: savedSubject.id
            )
            dataStore.invalidateAfterSubjectMutation()
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteSubject() async {
        guard let subject else {
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try await APIClient.shared.deleteSubject(subjectID: subject.id)
            CardsMetadataStore.removeSubjectMetadata(subject.id)
            dataStore.invalidateAfterSubjectMutation()
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func normalizedInitial(fallback: String) -> String {
        let value = initial.trimmed
        guard let first = value.first else {
            return fallback
        }
        return String(first).uppercased()
    }
}

private struct SetEditPage: View {
    let subjects: [AppSubject]
    let fixedSubject: AppSubject?
    let set: AppSet?
    let metadata: SetPresentation?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var selectedSubjectID: String
    @State private var name: String
    @State private var description: String
    @State private var defaultMode: SetDefaultReviewMode
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(subjects: [AppSubject], fixedSubject: AppSubject?, set: AppSet?, metadata: SetPresentation?, onDone: @escaping () async -> Void) {
        self.subjects = subjects
        self.fixedSubject = fixedSubject
        self.set = set
        self.metadata = metadata
        self.onDone = onDone
        _selectedSubjectID = State(initialValue: fixedSubject?.id ?? set?.subjectID ?? subjects.first?.id ?? "")
        _name = State(initialValue: set?.name ?? "")
        _description = State(initialValue: metadata?.description ?? set.map { setDescription($0, subject: fixedSubject ?? subjects.first ?? AppSubject(id: "", name: "Subject", cardCount: 0, dueCount: 0)) } ?? "")
        _defaultMode = State(initialValue: metadata.flatMap { SetDefaultReviewMode(rawValue: $0.defaultMode) } ?? .review)
    }

    private var isEditing: Bool {
        return self.set != nil
    }

    private var canSave: Bool {
        !selectedSubjectID.isEmpty && !name.trimmed.isEmpty && !isSaving
    }

    var body: some View {
        CardsEditPageScaffold(
            title: "Set",
            subtitle: "Create or edit a set under a subject",
            canSave: canSave,
            onBack: dismiss.callAsFunction,
            onSave: {
                await save()
            }
        ) {
            CardsFormSection {
                CardsLabeledTextField(title: "Set name", text: $name, prompt: "")

                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    CardsFieldLabel("Parent Subject")
                    Picker("Parent Subject", selection: $selectedSubjectID) {
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(subject.id)
                        }
                    }
                    .disabled(fixedSubject != nil || isEditing)
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CardsLabeledTextArea(title: "Description", text: $description, prompt: "", minHeight: 88)
            }

            CardsFormSection {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    CardsFieldLabel("Default review mode")
                    Picker("Default review mode", selection: $defaultMode) {
                        ForEach(SetDefaultReviewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if let errorMessage {
                CardsFormError(message: errorMessage)
            }

            if set != nil {
                CardsDangerZone(
                    title: "Delete Set",
                    message: "Deleting this set will also affect all cards under it.",
                    actionTitle: "Delete Set"
                ) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete set?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Set", role: .destructive) {
                Task {
                    await deleteSet()
                }
            }
        } message: {
            Text("Deleting this set will also affect all cards under it.")
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let savedSet: AppSet
            if let set {
                savedSet = try await APIClient.shared.updateSet(subjectID: set.subjectID, setID: set.id, name: name.trimmed)
            } else {
                savedSet = try await APIClient.shared.createSet(subjectID: selectedSubjectID, name: name.trimmed)
            }

            CardsMetadataStore.saveSetMetadata(
                SetPresentation(description: description.trimmed, defaultMode: defaultMode.rawValue),
                for: savedSet.id
            )
            dataStore.invalidateAfterSetMutation()
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteSet() async {
        guard let set else {
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try await APIClient.shared.deleteSet(subjectID: set.subjectID, setID: set.id)
            CardsMetadataStore.removeSetMetadata(set.id)
            dataStore.invalidateAfterSetMutation()
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

private struct CardEditPage: View {
    let card: ReviewCard?
    let subjects: [AppSubject]
    let fixedSubject: AppSubject?
    let fixedSet: AppSet?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var selectedSubjectID: String
    @State private var availableSets: [AppSet] = []
    @State private var selectedSetID: String
    @State private var cardType: CardsCardType
    @State private var frontText: String
    @State private var answerText: String
    @State private var grammarPhraseText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(card: ReviewCard?, subjects: [AppSubject], fixedSubject: AppSubject?, fixedSet: AppSet?, onDone: @escaping () async -> Void) {
        self.card = card
        self.subjects = subjects
        self.fixedSubject = fixedSubject
        self.fixedSet = fixedSet
        self.onDone = onDone

        let initialSubjectID = fixedSubject?.id ?? card?.subjectID ?? subjects.first?.id ?? ""
        let initialSetID = fixedSet?.id ?? card?.set.id ?? ""
        _selectedSubjectID = State(initialValue: initialSubjectID)
        _selectedSetID = State(initialValue: initialSetID)
        _cardType = State(initialValue: CardsCardType(normalizing: card?.cardType))
        _frontText = State(initialValue: card?.frontText ?? "")
        _answerText = State(initialValue: card?.answerText ?? "")
        _grammarPhraseText = State(initialValue: card?.grammarPhrases
            .map(\.text)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: "\n") ?? "")
    }

    private var canSave: Bool {
        !selectedSubjectID.isEmpty
            && !selectedSetID.isEmpty
            && !frontText.trimmed.isEmpty
            && !answerText.trimmed.isEmpty
            && !isSaving
    }

    var body: some View {
        CardsEditPageScaffold(
            title: "Card",
            subtitle: "Create or edit one flashcard",
            canSave: canSave,
            onBack: dismiss.callAsFunction,
            onSave: {
                await save()
            }
        ) {
            CardsFormSection {
                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    CardsFieldLabel("Subject")
                    Picker("Subject", selection: $selectedSubjectID) {
                        Text("Select subject").tag("")
                        ForEach(subjects) { subject in
                            Text(subject.name).tag(subject.id)
                        }
                    }
                    .disabled(fixedSubject != nil)
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: selectedSubjectID) { _, _ in
                        Task {
                            await loadSets(resetSelection: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    CardsFieldLabel("Set")
                    Picker("Set", selection: $selectedSetID) {
                        Text("Select set").tag("")
                        ForEach(availableSets) { set in
                            Text(set.name).tag(set.id)
                        }
                    }
                    .disabled(fixedSet != nil || availableSets.isEmpty)
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: AppSpace.sm) {
                    CardsFieldLabel("Card type")
                    Picker("Card type", selection: $cardType) {
                        ForEach(CardsCardType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            CardsFormSection {
                CardsLabeledTextArea(title: "Front", text: $frontText,
                                     prompt: "", minHeight: 126)
                CardsLabeledTextArea(title: "Answer", text: $answerText,
                                     prompt: "", minHeight: 126)
            }

            CardsFormSection {
                CardsLabeledTextArea(
                    title: "Grammar / Phrases",
                    text: $grammarPhraseText,
                    prompt: "",
                    minHeight: 168
                )
            }

            if let errorMessage {
                CardsFormError(message: errorMessage)
            }

            if card != nil {
                CardsDangerZone(
                    title: "Delete Card",
                    message: "This card will be removed from review.",
                    actionTitle: "Delete Card"
                ) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .task {
            await loadSets(resetSelection: false)
        }
        .confirmationDialog("Delete card?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                Task {
                    await deleteCard()
                }
            }
        } message: {
            Text("This card will be removed from review.")
        }
    }

    private func loadSets(resetSelection: Bool) async {
        guard !selectedSubjectID.isEmpty else {
            availableSets = []
            selectedSetID = ""
            return
        }

        do {
            availableSets = try await dataStore.refreshSets(subjectID: selectedSubjectID, force: false)
            if let fixedSet {
                selectedSetID = fixedSet.id
            } else if resetSelection || !availableSets.contains(where: { $0.id == selectedSetID }) {
                selectedSetID = availableSets.first?.id ?? ""
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
            cardType: cardType.rawValue,
            direction: CardDirection.detected(fromFront: frontText.trimmed).rawValue,
            frontText: frontText.trimmed,
            answerText: answerText.trimmed,
            grammarPhrases: grammarPhraseText
                .components(separatedBy: .newlines)
                .map(\.trimmed)
                .filter { !$0.isEmpty }
                .map { GrammarPhrasePayload(text: $0, note: "") }
        )

        do {
            if let card {
                _ = try await APIClient.shared.updateCard(cardID: card.id, payload: payload)
            } else {
                _ = try await APIClient.shared.createCard(payload)
            }
            dataStore.invalidateAfterCardMutation(cardID: card?.id)
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteCard() async {
        guard let card else {
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try await APIClient.shared.deleteCard(card)
            dataStore.invalidateAfterCardMutation(cardID: card.id)
            dismiss()
            await onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

}

private struct CardsEditPageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let canSave: Bool
    let onBack: () -> Void
    let onSave: () async -> Void
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        canSave: Bool,
        onBack: @escaping () -> Void,
        onSave: @escaping () async -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.canSave = canSave
        self.onBack = onBack
        self.onSave = onSave
        self.content = content
    }

    var body: some View {
        // 样式 A：编辑页是可返回的屏 → 原生导航栏 + inline 标题 + 右侧主操作。
        // 改造前是「圆形返回 + 34pt 大标题 + 副标题」，那是 Tab 根屏才用的样式 B，
        // 用在可返回的屏上正是 #1「三套导航并存」的根源。
        // 编辑页由 .fullScreenCover 呈现，没有 NavigationStack 祖先 —— 必须自带一个，
        // 否则 .toolbar 不会渲染（标题与 Save 会整个消失）。
        // 又因为是 present 而非 push，dismiss 用 .close（xmark）而不是返回箭头。
        NavigationStack {
            AppScreen {
                Text(LocalizedStringKey(subtitle))
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: AppLayout.cardGap) {
                    content()
                }
            }
            .appNavBar(title, dismiss: .close, onDismiss: onBack) {
                // 主操作 = primary 实心。灰色只属于 disabled（#4 / #5）。
                AppButton(
                    title: "Save",
                    variant: .primary,
                    size: .small,
                    isEnabled: canSave
                ) {
                    Task { await onSave() }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct CardsFormSection<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpace.lg) {
                content()
            }
        }
    }
}

private struct CardsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .appText(AppType.label, color: AppColor.textTertiary)
    }
}

private struct CardsLabeledTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        AppTextField(label: title, text: $text, placeholder: prompt)
    }
}

private struct CardsLabeledTextArea: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let minHeight: CGFloat

    var body: some View {
        AppTextArea(label: title, text: $text, placeholder: prompt, minHeight: minHeight)
    }
}

private struct CardsAccentPicker: View {
    @Binding var selection: CardsAccentChoice

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.sm) {
            CardsFieldLabel("Accent color")

            // 色圆视觉 32pt，热区外扩至 44（改造前整个可点区域只有 32×32，低于 HIG 下限）。
            HStack(spacing: AppSpace.xs) {
                ForEach(CardsAccentChoice.allCases) { accent in
                    Button {
                        selection = accent
                    } label: {
                        Circle()
                            .fill(accent.palette.fill)
                            .frame(width: AppLayout.avatarSM, height: AppLayout.avatarSM)
                            .overlay {
                                if selection == accent {
                                    Image(systemName: AppIcon.confirm)
                                        .font(AppIcon.font(AppLayout.iconSM))
                                        .foregroundStyle(accent.palette.onFill)
                                }
                            }
                            // 选中环走中性最深色，而非再引入一个强调色
                            .overlay {
                                Circle().strokeBorder(
                                    selection == accent ? AppColor.textPrimary : Color.clear,
                                    lineWidth: AppLayout.focusRingWidth
                                )
                            }
                            .frame(width: AppLayout.minHitTarget, height: AppLayout.minHitTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(AppPressableStyle())
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(selection == accent ? .isSelected : [])
                }
            }
            // 抵消热区外扩带来的视觉左缩进，让色圆与上方标签对齐
            .padding(.horizontal, -(AppLayout.minHitTarget - AppLayout.avatarSM) / 2)
        }
    }
}

private struct CardsDangerZone: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpace.md) {
                Text("Danger Zone")
                    .appText(AppType.label, color: AppColor.dangerText)

                Text(LocalizedStringKey(message))
                    .appText(AppType.body, color: AppColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                AppButton(
                    title: actionTitle,
                    variant: .destructive,
                    size: .medium,
                    fullWidth: true,
                    action: action
                )
                .padding(.top, AppSpace.xs)
            }
        }
    }
}

private struct CardsFormError: View {
    let message: String

    var body: some View {
        Text(LocalizedStringKey(message))
            .appText(AppType.label, color: AppColor.dangerText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpace.md)
            .background(AppColor.dangerSoft, in: AppRadius.shape(AppRadius.md))
    }
}

private enum CardsAccentChoice: String, CaseIterable, Identifiable, Codable {
    case indigo
    case green
    case amber
    case sky
    case purple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: return "Indigo"
        case .green: return "Green"
        case .amber: return "Amber"
        case .sky: return "Sky"
        case .purple: return "Purple"
        }
    }

    /// Subject 身份色板。见 AppColor.subjectAccents —— 它是分类色，不是品牌主色，
    /// 只允许用于 subject 自身的标识，禁止用于导航 / 按钮 / 选中态。
    var palette: AppColor.SubjectAccent {
        AppColor.subjectAccent(rawValue)
    }

    var color: Color { palette.fill }
}

private enum SetDefaultReviewMode: String, CaseIterable, Identifiable, Codable {
    case review
    case test

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: return "Review"
        case .test: return "Test"
        }
    }
}

private enum CardsCardType: String, CaseIterable, Identifiable {
    case word = "word"
    case sentence = "sentence"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: return "Word"
        case .sentence: return "Sentence"
        }
    }

    /// 兼容历史值：早期的 speaking_expression / grammar 语义上都是整句，并入 sentence。
    /// 与后端 service.NormalizeCardType 行为一致。
    init(normalizing raw: String?) {
        self = CardsCardType(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces)) ?? .sentence
    }
}

private struct SubjectPresentation: Codable {
    var description: String
    var initial: String
    var accent: String
}

private struct SetPresentation: Codable {
    var description: String
    var defaultMode: String
}

private enum CardsMetadataStore {
    private static let subjectKey = "cards.subject.presentation"
    private static let setKey = "cards.set.presentation"

    static func subjectMetadata() -> [String: SubjectPresentation] {
        load([String: SubjectPresentation].self, key: subjectKey) ?? [:]
    }

    static func saveSubjectMetadata(_ metadata: SubjectPresentation, for subjectID: String) {
        var values = subjectMetadata()
        values[subjectID] = metadata
        save(values, key: subjectKey)
    }

    static func removeSubjectMetadata(_ subjectID: String) {
        var values = subjectMetadata()
        values.removeValue(forKey: subjectID)
        save(values, key: subjectKey)
    }

    static func setMetadata() -> [String: SetPresentation] {
        load([String: SetPresentation].self, key: setKey) ?? [:]
    }

    static func saveSetMetadata(_ metadata: SetPresentation, for setID: String) {
        var values = setMetadata()
        values[setID] = metadata
        save(values, key: setKey)
    }

    static func removeSetMetadata(_ setID: String) {
        var values = setMetadata()
        values.removeValue(forKey: setID)
        save(values, key: setKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct CardsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.018 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: configuration.isPressed)
    }
}

private extension View {
    /// 行卡容器。高度由内容决定（原先 96/100/112 三个写死值），
    /// 表面 / 圆角 / 描边 / 阴影统一走 appSurface(.card)。
    func cardsRowSurface() -> some View {
        self
            .padding(AppLayout.cardPadding)
            .frame(maxWidth: .infinity, minHeight: AppLayout.minHitTarget, alignment: .leading)
            .appSurface(.card)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedQuery: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var initialLetter: String {
        guard let first else {
            return "?"
        }
        return String(first).uppercased()
    }
}

// 返回身份色板条目而非裸 Color：调用方才能按用途取 fill / text / soft。
// 直接拿 fill 当文字色是原代码的 AA 缺陷（green 3.77:1 / amber 3.64:1 / sky 4.10:1）。
private func rowTint(for subject: AppSubject) -> AppColor.SubjectAccent {
    let palette = AppColor.subjectAccents
    return palette[abs(subject.id.hashValue) % palette.count]
}

private func rowTint(for set: AppSet) -> AppColor.SubjectAccent {
    let palette = AppColor.subjectAccents
    return palette[abs(set.id.hashValue) % palette.count]
}

private func subjectInitial(_ subject: AppSubject, metadata: SubjectPresentation?) -> String {
    guard let initial = metadata?.initial.trimmed, !initial.isEmpty else {
        return subject.name.initialLetter
    }
    return String(initial.prefix(1)).uppercased()
}

private func subjectTint(_ subject: AppSubject, metadata: SubjectPresentation?) -> AppColor.SubjectAccent {
    guard let accent = metadata?.accent, let choice = CardsAccentChoice(rawValue: accent) else {
        return rowTint(for: subject)
    }
    return choice.palette
}

private func subjectDisplayDescription(_ subject: AppSubject, metadata: SubjectPresentation?) -> String {
    guard let description = metadata?.description.trimmed, !description.isEmpty else {
        return subjectDescription(subject)
    }
    return description
}

private func setDisplayDescription(_ set: AppSet, subject: AppSubject, metadata: SetPresentation?) -> String {
    guard let description = metadata?.description.trimmed, !description.isEmpty else {
        return setDescription(set, subject: subject)
    }
    return description
}

private func subjectDescription(_ subject: AppSubject) -> String {
    switch subject.name.normalizedQuery {
    case "speaking":
        return "Polite requests, meetings, daily output"
    case "grammar":
        return "Patterns, clauses, prepositions"
    case "long sentences":
        return "Reading and sentence analysis"
    default:
        return "English learning cards"
    }
}

private func setDescription(_ set: AppSet, subject: AppSubject) -> String {
    switch set.name.normalizedQuery {
    case "polite requests":
        return "Softer ways to ask, follow up, and confirm"
    case "meeting phrases", "meeting expressions":
        return "Standups, syncs, blockers, alignment"
    case "daily output":
        return "Common speaking patterns for daily work"
    default:
        return "\(subject.name) practice set"
    }
}

private func cardMetadata(_ card: ReviewCard) -> String {
    let subjectName = card.subjectName ?? "English"
    return "\(subjectName) · \(card.set.name)"
}
