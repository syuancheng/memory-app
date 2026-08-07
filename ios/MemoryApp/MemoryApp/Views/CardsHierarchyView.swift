import SwiftUI

struct CardsHierarchyView: View {
    var body: some View {
        NavigationStack {
            CardsRootPage()
        }
        .tint(AppSurface.accent)
    }
}

private struct CardsRootPage: View {
    @State private var subjects: [AppSubject] = []
    @State private var tagsBySubjectID: [String: [AppTag]] = [:]
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
                || (tagsBySubjectID[subject.id] ?? []).contains { $0.name.normalizedQuery.contains(query) }
                || cards.contains { card in
                    card.subjectID == subject.id
                        && (card.frontText.normalizedQuery.contains(query)
                            || card.answerText.normalizedQuery.contains(query)
                            || card.tags.contains { $0.name.normalizedQuery.contains(query) })
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
                .padding(.top, 22)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredSubjects.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No subjects yet" : "No matching subjects",
                    message: searchText.isEmpty ? "Create your first English learning subject." : "Try another subject, set, or card keyword."
                )
                .padding(.top, 32)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(filteredSubjects) { subject in
                        CardsSubjectRow(
                            subject: subject,
                            initial: subjectInitial(subject, metadata: subjectMetadata[subject.id]),
                            description: subjectDisplayDescription(subject, metadata: subjectMetadata[subject.id]),
                            setCount: tagsBySubjectID[subject.id]?.count ?? 0,
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
                .padding(.top, 14)
            }
        }
        .navigationDestination(item: $selectedSubject) { subject in
            SubjectSetsPage(subject: subject)
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addSubject:
                SubjectEditPage(subject: nil, metadata: nil) {
                    await loadData()
                }
            case .editSubject(let subject):
                SubjectEditPage(subject: subject, metadata: subjectMetadata[subject.id]) {
                    await loadData()
                }
            case .addSet(let subject):
                SetEditPage(subjects: subjects, fixedSubject: subject, set: nil, metadata: nil) {
                    await loadData()
                }
            case .editSet(let subject, let set):
                SetEditPage(subjects: subjects, fixedSubject: subject, set: set, metadata: CardsMetadataStore.setMetadata()[set.id]) {
                    await loadData()
                }
            case .addCard(let subject, let set):
                CardEditPage(card: nil, subjects: subjects, fixedSubject: subject, fixedSet: set) {
                    await loadData()
                }
            case .editCard(let card, let subject):
                CardEditPage(card: card, subjects: subjects, fixedSubject: subject, fixedSet: nil) {
                    await loadData()
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
            CardsIconButton(systemName: "plus", tint: AppSurface.accent)
        }
        .accessibilityLabel("Create")
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedSubjects = APIClient.shared.listSubjects()
            async let loadedCards = APIClient.shared.listCards()
            let resolvedSubjects = try await loadedSubjects
            let resolvedCards = try await loadedCards

            var tagMap: [String: [AppTag]] = [:]
            for subject in resolvedSubjects {
                tagMap[subject.id] = try await APIClient.shared.listTags(subjectID: subject.id)
            }

            subjects = resolvedSubjects
            cards = resolvedCards
            tagsBySubjectID = tagMap
            subjectMetadata = CardsMetadataStore.subjectMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ subject: AppSubject) async {
        do {
            try await APIClient.shared.deleteSubject(subjectID: subject.id)
            deletingSubject = nil
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SubjectSetsPage: View {
    let subject: AppSubject

    @Environment(\.dismiss) private var dismiss
    @State private var sets: [AppTag] = []
    @State private var cards: [ReviewCard] = []
    @State private var setMetadata: [String: SetPresentation] = [:]
    @State private var searchText = ""
    @State private var selectedSet: AppTag?
    @State private var activeSheet: CardsSheet?
    @State private var deletingSet: AppTag?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredSets: [AppTag] {
        let query = searchText.normalizedQuery
        guard !query.isEmpty else {
            return sets
        }

        return sets.filter { set in
            set.name.normalizedQuery.contains(query)
                || setDescription(set, subject: subject).normalizedQuery.contains(query)
                || cards.contains { card in
                    card.tags.contains { $0.id == set.id }
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
                .padding(.top, 22)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredSets.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No sets yet" : "No matching sets",
                    message: searchText.isEmpty ? "Create a set under this subject." : "Try another set or card keyword."
                )
                .padding(.top, 32)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(filteredSets) { set in
                        CardsSetRow(
                            set: set,
                            description: setDisplayDescription(set, subject: subject, metadata: setMetadata[set.id]),
                            tint: setTint(set, metadata: setMetadata[set.id]),
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
                .padding(.top, 14)
            }
        }
        .navigationDestination(item: $selectedSet) { set in
            SetCardsPage(subject: subject, set: set)
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addSet(_):
                SetEditPage(subjects: [subject], fixedSubject: subject, set: nil, metadata: nil) {
                    await loadData()
                }
            case .editSet(_, let set):
                SetEditPage(subjects: [subject], fixedSubject: subject, set: set, metadata: setMetadata[set.id]) {
                    await loadData()
                }
            case .addCard(_, let set):
                CardEditPage(card: nil, subjects: [subject], fixedSubject: subject, fixedSet: set) {
                    await loadData()
                }
            case .editCard(let card, _):
                CardEditPage(card: card, subjects: [subject], fixedSubject: subject, fixedSet: nil) {
                    await loadData()
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
            CardsIconButton(systemName: "plus", tint: AppSurface.accent)
        }
        .accessibilityLabel("Create")
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let loadedSets = APIClient.shared.listTags(subjectID: subject.id)
            async let loadedCards = APIClient.shared.listCards(subjectID: subject.id)
            sets = try await loadedSets
            cards = try await loadedCards
            setMetadata = CardsMetadataStore.setMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ set: AppTag) async {
        do {
            try await APIClient.shared.deleteTag(subjectID: subject.id, tagID: set.id)
            deletingSet = nil
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetCardsPage: View {
    let subject: AppSubject
    let set: AppTag

    @Environment(\.dismiss) private var dismiss
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
                || card.tags.contains { $0.name.normalizedQuery.contains(query) }
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
                .padding(.top, 22)

            CardsLoadState(isLoading: isLoading, errorMessage: errorMessage)

            if !isLoading && filteredCards.isEmpty {
                CardsEmptyState(
                    title: searchText.isEmpty ? "No cards yet" : "No matching cards",
                    message: searchText.isEmpty ? "Add your first card to this set." : "Try another prompt, answer, or tag keyword."
                )
                .padding(.top, 32)
            } else {
                LazyVStack(spacing: 16) {
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
                .padding(.top, 14)
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .fullScreenCover(item: $activeSheet) { sheet in
            switch sheet {
            case .addCard(_, _):
                CardEditPage(card: nil, subjects: [subject], fixedSubject: subject, fixedSet: set) {
                    await loadData()
                }
            case .editCard(let card, _):
                CardEditPage(card: card, subjects: [subject], fixedSubject: subject, fixedSet: nil) {
                    await loadData()
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
            CardsIconButton(systemName: "plus", tint: AppSurface.accent)
        }
        .accessibilityLabel("Create")
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            cards = try await APIClient.shared.listCards(subjectID: subject.id, tagIDs: [set.id])
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ card: ReviewCard) async {
        do {
            try await APIClient.shared.deleteCard(card)
            deletingCard = nil
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CardsSheet: Identifiable {
    case addSubject
    case editSubject(AppSubject)
    case addSet(AppSubject?)
    case editSet(AppSubject, AppTag)
    case addCard(AppSubject?, AppTag?)
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

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    CardsManagementHeader(title: title, subtitle: subtitle, onBack: onBack, trailing: trailing)
                        .padding(.bottom, 26)

                    content()
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

private struct CardsManagementHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var onBack: (() -> Void)?
    let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    CardsIconButton(systemName: "chevron.left", tint: AppSurface.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(AppSurface.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 12)

            trailing()
        }
        .frame(minHeight: 62, alignment: .top)
    }
}

private struct CardsIconButton: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(.white)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(AppSurface.line, lineWidth: 1)
            )
            .shadow(color: AppSurface.shadow.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}

private struct CardsSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppSurface.muted)

            TextField(prompt, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(AppSurface.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(AppSurface.cardSubtle)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(AppSurface.line, lineWidth: 1)
        )
    }
}

private struct CardsSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(AppSurface.text)
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
                    .tint(AppSurface.accent)
                Spacer()
            }
            .padding(.top, 20)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundStyle(AppSurface.coral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
        }
    }
}

private struct CardsEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppSurface.text)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(AppSurface.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppSurface.line, lineWidth: 1)
        )
        .shadow(color: AppSurface.shadow.opacity(0.04), radius: 14, x: 0, y: 8)
    }
}

private struct CardsSubjectRow: View {
    let subject: AppSubject
    let initial: String
    let description: String
    let setCount: Int
    let tint: Color
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            InitialBadge(text: initial, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.muted)
                    .lineLimit(2)

                Text("\(setCount) sets · \(subject.cardCount) cards")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            CardsRowMenu(
                editTitle: "Edit Subject",
                deleteTitle: "Delete Subject",
                onEdit: onEdit,
                onDelete: onDelete
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppSurface.slateLight)
        }
        .cardsRowSurface(minHeight: 96)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            onOpen()
        }
    }
}

private struct CardsSetRow: View {
    let set: AppTag
    let description: String
    let tint: Color
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            InitialBadge(text: "Set", tint: tint)

            VStack(alignment: .leading, spacing: 5) {
                Text(set.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.muted)
                    .lineLimit(1)

                Text("\(set.cardCount) cards · \(set.dueCount) due")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            CardsRowMenu(
                editTitle: "Edit Set",
                deleteTitle: "Delete Set",
                onEdit: onEdit,
                onDelete: onDelete
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppSurface.slateLight)
        }
        .cardsRowSurface(minHeight: 100)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Text(card.answerText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppSurface.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                CardsRowMenu(
                    editTitle: "Edit Card",
                    deleteTitle: "Delete Card",
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }

            Text(card.frontText)
                .font(.system(size: 13))
                .foregroundStyle(AppSurface.muted)
                .lineLimit(2)

            HStack(alignment: .center, spacing: 8) {
                Text(cardMetadata(card))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 8)
            }
        }
        .cardsRowSurface(minHeight: 112)
    }
}

private struct InitialBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: text.count > 1 ? 12 : 16, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.13))
            .clipShape(Circle())
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppSurface.muted)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SubjectEditPage: View {
    let subject: AppSubject?
    let metadata: SubjectPresentation?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
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
                CardsLabeledTextField(title: "Subject name", text: $name, prompt: "Speaking")
                CardsLabeledTextArea(title: "Description", text: $description, prompt: "Polite requests, meetings, daily output", minHeight: 92)
            }

            CardsFormSection {
                CardsLabeledTextField(title: "Icon / initial", text: $initial, prompt: "S")
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
    let set: AppTag?
    let metadata: SetPresentation?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubjectID: String
    @State private var name: String
    @State private var description: String
    @State private var defaultMode: SetDefaultReviewMode
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(subjects: [AppSubject], fixedSubject: AppSubject?, set: AppTag?, metadata: SetPresentation?, onDone: @escaping () async -> Void) {
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
                CardsLabeledTextField(title: "Set name", text: $name, prompt: "Polite Requests")

                VStack(alignment: .leading, spacing: 10) {
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

                CardsLabeledTextArea(title: "Description", text: $description, prompt: "Softer ways to ask, follow up, and confirm", minHeight: 88)
            }

            CardsFormSection {
                VStack(alignment: .leading, spacing: 10) {
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
            let savedSet: AppTag
            if let set {
                savedSet = try await APIClient.shared.updateTag(subjectID: set.subjectID, tagID: set.id, name: name.trimmed)
            } else {
                savedSet = try await APIClient.shared.createTag(subjectID: selectedSubjectID, name: name.trimmed)
            }

            CardsMetadataStore.saveSetMetadata(
                SetPresentation(description: description.trimmed, defaultMode: defaultMode.rawValue),
                for: savedSet.id
            )
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
            try await APIClient.shared.deleteTag(subjectID: set.subjectID, tagID: set.id)
            CardsMetadataStore.removeSetMetadata(set.id)
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
    let fixedSet: AppTag?
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubjectID: String
    @State private var availableSets: [AppTag] = []
    @State private var selectedSetID: String
    @State private var cardType: CardsCardType
    @State private var frontText: String
    @State private var answerText: String
    @State private var grammarPhraseText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    init(card: ReviewCard?, subjects: [AppSubject], fixedSubject: AppSubject?, fixedSet: AppTag?, onDone: @escaping () async -> Void) {
        self.card = card
        self.subjects = subjects
        self.fixedSubject = fixedSubject
        self.fixedSet = fixedSet
        self.onDone = onDone

        let initialSubjectID = fixedSubject?.id ?? card?.subjectID ?? subjects.first?.id ?? ""
        let initialSetID = fixedSet?.id ?? card?.tags.first?.id ?? ""
        _selectedSubjectID = State(initialValue: initialSubjectID)
        _selectedSetID = State(initialValue: initialSetID)
        _cardType = State(initialValue: CardsCardType(rawValue: card?.cardType ?? "") ?? .speaking)
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
                VStack(alignment: .leading, spacing: 10) {
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

                VStack(alignment: .leading, spacing: 10) {
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

                VStack(alignment: .leading, spacing: 10) {
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
                CardsLabeledTextArea(title: "Front / Prompt", text: $frontText, prompt: "有没有可能明天之前拿到？", minHeight: 126)
                CardsLabeledTextArea(title: "Answer", text: $answerText, prompt: "Any chance of getting it by tomorrow?", minHeight: 126)
            }

            CardsFormSection {
                CardsLabeledTextArea(
                    title: "Grammar / Phrases",
                    text: $grammarPhraseText,
                    prompt: "Any chance of + doing\nby tomorrow\nget it",
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
            availableSets = try await APIClient.shared.listTags(subjectID: selectedSubjectID)
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
        let tagIDs = selectedSetID.isEmpty ? [] : [selectedSetID]
        let payload = CardPayload(
            subjectID: selectedSubjectID,
            tagIDs: tagIDs,
            cardType: cardType.rawValue,
            direction: card?.direction ?? "zh_to_en",
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
        CardsManagementPage(
            title: title,
            subtitle: subtitle,
            onBack: onBack,
            trailing: {
                Button {
                    Task {
                        await onSave()
                    }
                } label: {
                    CardsIconButton(systemName: "checkmark", tint: canSave ? AppSurface.accent : AppSurface.muted)
                }
                .disabled(!canSave)
                .buttonStyle(.plain)
                .accessibilityLabel("Save")
            }
        ) {
            VStack(spacing: 16) {
                content()
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
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppSurface.line, lineWidth: 1)
        )
        .shadow(color: AppSurface.shadow.opacity(0.045), radius: 14, x: 0, y: 8)
    }
}

private struct CardsFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppSurface.textSecondary)
    }
}

private struct CardsLabeledTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardsFieldLabel(title)
            TextField(prompt, text: $text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppSurface.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(AppSurface.cardSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppSurface.line, lineWidth: 1)
                )
        }
    }
}

private struct CardsLabeledTextArea: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardsFieldLabel(title)
            TextField(prompt, text: $text, axis: .vertical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppSurface.text)
                .lineLimit(3...8)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .background(AppSurface.cardSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppSurface.line, lineWidth: 1)
                )
        }
    }
}

private struct CardsAccentPicker: View {
    @Binding var selection: CardsAccentChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardsFieldLabel("Accent color")
            HStack(spacing: 12) {
                ForEach(CardsAccentChoice.allCases) { accent in
                    Button {
                        selection = accent
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(selection == accent ? AppSurface.text : Color.clear, lineWidth: 2)
                            )
                            .overlay {
                                if selection == accent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accent.title)
                }
            }
        }
    }
}

private struct CardsDangerZone: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppSurface.coral)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppSurface.muted)

            Button(role: .destructive) {
                action()
            } label: {
                Text(actionTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppSurface.coral)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppSurface.roseSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppSurface.rose.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct CardsFormError: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppSurface.coral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppSurface.roseSoft)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    var color: Color {
        switch self {
        case .indigo: return AppSurface.accent
        case .green: return AppSurface.green
        case .amber: return AppSurface.amber
        case .sky: return AppSurface.sky
        case .purple: return AppSurface.purple
        }
    }
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
    case speaking = "speaking_expression"
    case grammar = "grammar"
    case sentence = "sentence"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speaking: return "Speaking"
        case .grammar: return "Grammar"
        case .sentence: return "Sentence"
        }
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
    func cardsRowSurface(minHeight: CGFloat) -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppSurface.line, lineWidth: 1)
            )
            .shadow(color: AppSurface.shadow.opacity(0.045), radius: 14, x: 0, y: 8)
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

private func rowTint(for subject: AppSubject) -> Color {
    let colors = [AppSurface.accent, AppSurface.green, AppSurface.amber, AppSurface.sky, AppSurface.purple]
    return colors[abs(subject.id.hashValue) % colors.count]
}

private func rowTint(for set: AppTag) -> Color {
    let colors = [AppSurface.accent, AppSurface.green, AppSurface.amber, AppSurface.sky, AppSurface.purple]
    return colors[abs(set.id.hashValue) % colors.count]
}

private func subjectInitial(_ subject: AppSubject, metadata: SubjectPresentation?) -> String {
    guard let initial = metadata?.initial.trimmed, !initial.isEmpty else {
        return subject.name.initialLetter
    }
    return String(initial.prefix(1)).uppercased()
}

private func subjectTint(_ subject: AppSubject, metadata: SubjectPresentation?) -> Color {
    guard let accent = metadata?.accent, let choice = CardsAccentChoice(rawValue: accent) else {
        return rowTint(for: subject)
    }
    return choice.color
}

private func subjectDisplayDescription(_ subject: AppSubject, metadata: SubjectPresentation?) -> String {
    guard let description = metadata?.description.trimmed, !description.isEmpty else {
        return subjectDescription(subject)
    }
    return description
}

private func setTint(_ set: AppTag, metadata: SetPresentation?) -> Color {
    switch metadata?.defaultMode {
    case SetDefaultReviewMode.test.rawValue:
        return AppSurface.sky
    default:
        return rowTint(for: set)
    }
}

private func setDisplayDescription(_ set: AppTag, subject: AppSubject, metadata: SetPresentation?) -> String {
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

private func setDescription(_ set: AppTag, subject: AppSubject) -> String {
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
    if let tag = card.tags.first {
        return "\(subjectName) · \(tag.name)"
    }
    return subjectName
}
