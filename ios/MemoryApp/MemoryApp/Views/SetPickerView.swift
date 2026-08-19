import SwiftUI

struct SetPickerView: View {
    let subject: AppSubject
    let mode: StudyMode
    let onStart: (StudySessionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataStore: AppDataStore
    @State private var sets: [AppSet] = []
    @State private var selection: SetSelectionState = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isAllSelected: Bool {
        selection.isAll
    }

    private var selectedSetIDs: [String] {
        switch selection {
        case .all:
            return sets.map(\.id)
        case .specific(let ids):
            return sets.filter { ids.contains($0.id) }.map(\.id)
        }
    }

    private var selectedCardCount: Int {
        switch selection {
        case .all:
            return mode == .learn ? subject.cardCount : subject.dueCount
        case .specific(let ids):
            return sets
                .filter { ids.contains($0.id) }
                .reduce(0) { $0 + (mode == .learn ? $1.cardCount : $1.dueCount) }
        }
    }

    private var canStart: Bool {
        selectedCardCount > 0 && !selectedSetIDs.isEmpty
    }

    private var primaryTitle: String {
        if canStart {
            return mode == .learn ? mode.actionTitle : "\(mode.actionTitle) \(selectedCardCount) cards"
        }
        return mode == .learn ? "No cards to learn" : "No cards due"
    }

    private var pickerTitle: String {
        mode == .learn ? "Choose what to learn" : "Choose what to review"
    }

    var body: some View {
        StudySelectionPage(title: subject.name, onBack: dismiss.callAsFunction) {
            Text(pickerTitle)
                .appText(AppType.title2)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AppColor.primary)
                    Spacer()
                }
                .frame(minHeight: AppSpace.giant * 2)
            } else {
                LazyVStack(spacing: AppLayout.cardGap) {
                    Button {
                        selection = .all
                    } label: {
                        StudySelectionRow(
                            title: "All",
                            subtitle: mode == .learn ? nil : "\(subject.dueCount) due · \(subject.cardCount) cards",
                            count: mode == .learn ? subject.cardCount : subject.dueCount,
                            isSelected: isAllSelected
                        )
                    }
                    .buttonStyle(StudySelectionPressStyle())

                    ForEach(sets) { set in
                        Button {
                            toggle(set)
                        } label: {
                            StudySelectionRow(
                                title: set.name,
                                subtitle: mode == .learn ? nil : "\(set.dueCount) due · \(set.cardCount) cards",
                                count: mode == .learn ? set.cardCount : set.dueCount,
                                isSelected: isSetSelected(set)
                            )
                        }
                        .buttonStyle(StudySelectionPressStyle())
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .appText(AppType.label, color: AppColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !isLoading && errorMessage == nil && sets.isEmpty {
                AppEmptyState(
                    title: "No sets yet",
                    message: "This subject has no sets, so \"All\" covers everything.",
                    density: .compact
                )
            }

            Spacer(minLength: AppSpace.giant * 2)
        }
        .safeAreaInset(edge: .bottom) {
            AppButton(
                title: primaryTitle,
                variant: .primary,
                size: .large,
                fullWidth: true,
                isEnabled: canStart
            ) {
                onStart(
                    StudySessionConfig(
                        mode: mode,
                        subject: subject,
                        selectedSetIDs: selectedSetIDs
                    )
                )
            }
            .padding(.horizontal, AppLayout.screenMargin)
            .padding(.top, AppSpace.md)
            .padding(.bottom, AppSpace.sm)
            .background(AppColor.surfaceBase)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppColor.separator)
                    .frame(height: AppLayout.separatorHeight)
            }
        }
        .task {
            await loadSets()
        }
    }

    private func loadSets() async {
        isLoading = true
        errorMessage = nil
        do {
            sets = try await dataStore.refreshSets(subjectID: subject.id, force: false)
            selection = .all
            await preloadSelectedDueCards()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func isSetSelected(_ set: AppSet) -> Bool {
        switch selection {
        case .all:
            return false
        case .specific(let ids):
            return ids.contains(set.id)
        }
    }

    private func toggle(_ set: AppSet) {
        var ids: Set<String>
        switch selection {
        case .all:
            ids = [set.id]
        case .specific(let currentIDs):
            ids = currentIDs
            if ids.contains(set.id) {
                ids.remove(set.id)
            } else {
                ids.insert(set.id)
            }
        }

        if ids.count == sets.count || ids.isEmpty {
            selection = .all
        } else {
            selection = .specific(ids)
        }

        Task {
            await preloadSelectedDueCards()
        }
    }

    private func preloadSelectedDueCards() async {
        guard mode == .review, canStart else {
            return
        }
        await dataStore.preloadDueCards(subjectID: subject.id, setIDs: selectedSetIDs)
    }
}

private enum SetSelectionState: Hashable {
    case all
    case specific(Set<String>)

    var isAll: Bool {
        if case .all = self {
            return true
        }
        return false
    }
}
