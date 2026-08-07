import SwiftUI

struct TagPickerView: View {
    let subject: AppSubject
    let mode: StudyMode
    let onStart: (StudySessionConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [AppTag] = []
    @State private var selection: TagSelectionState = .all
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isAllSelected: Bool {
        selection.isAll
    }

    private var selectedTagIDs: [String] {
        switch selection {
        case .all:
            return tags.map(\.id)
        case .specific(let ids):
            return tags.filter { ids.contains($0.id) }.map(\.id)
        }
    }

    private var selectedDueCount: Int {
        switch selection {
        case .all:
            return subject.dueCount
        case .specific(let ids):
            return tags
                .filter { ids.contains($0.id) }
                .reduce(0) { $0 + $1.dueCount }
        }
    }

    private var canStart: Bool {
        selectedDueCount > 0 && !selectedTagIDs.isEmpty
    }

    private var primaryTitle: String {
        canStart ? "\(mode.actionTitle) \(selectedDueCount) cards" : "No cards due"
    }

    var body: some View {
        StudySelectionPage(title: subject.name, onBack: dismiss.callAsFunction) {
            Text("Choose what to review")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppSurface.text)
                .padding(.bottom, 18)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(AppSurface.accent)
                    Spacer()
                }
                .frame(minHeight: 160)
            } else {
                LazyVStack(spacing: 12) {
                    Button {
                        selection = .all
                    } label: {
                        StudySelectionRow(
                            title: "All",
                            subtitle: "\(subject.dueCount) due · \(subject.cardCount) cards",
                            count: subject.dueCount,
                            isSelected: isAllSelected
                        )
                    }
                    .buttonStyle(StudySelectionPressStyle())

                    ForEach(tags) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            StudySelectionRow(
                                title: tag.name,
                                subtitle: "\(tag.dueCount) due · \(tag.cardCount) cards",
                                count: tag.dueCount,
                                isSelected: isTagSelected(tag)
                            )
                        }
                        .buttonStyle(StudySelectionPressStyle())
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }

            if !isLoading && errorMessage == nil && tags.isEmpty {
                Text("No tags in this subject yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppSurface.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }

            Spacer(minLength: 24)
                .frame(height: 96)
        }
        .safeAreaInset(edge: .bottom) {
            Button(primaryTitle) {
                onStart(
                    StudySessionConfig(
                        mode: mode,
                        subject: subject,
                        selectedTagIDs: selectedTagIDs
                    )
                )
            }
            .disabled(!canStart)
            .buttonStyle(StudyPrimaryActionButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(
                AppSurface.background
                    .shadow(color: AppSurface.background, radius: 18, x: 0, y: -8)
            )
        }
        .task {
            await loadTags()
        }
    }

    private func loadTags() async {
        isLoading = true
        errorMessage = nil
        do {
            tags = try await APIClient.shared.listTags(subjectID: subject.id)
            selection = .all
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func isTagSelected(_ tag: AppTag) -> Bool {
        switch selection {
        case .all:
            return false
        case .specific(let ids):
            return ids.contains(tag.id)
        }
    }

    private func toggle(_ tag: AppTag) {
        var ids: Set<String>
        switch selection {
        case .all:
            ids = [tag.id]
        case .specific(let currentIDs):
            ids = currentIDs
            if ids.contains(tag.id) {
                ids.remove(tag.id)
            } else {
                ids.insert(tag.id)
            }
        }

        if ids.count == tags.count || ids.isEmpty {
            selection = .all
        } else {
            selection = .specific(ids)
        }
    }
}

private enum TagSelectionState: Hashable {
    case all
    case specific(Set<String>)

    var isAll: Bool {
        if case .all = self {
            return true
        }
        return false
    }
}
