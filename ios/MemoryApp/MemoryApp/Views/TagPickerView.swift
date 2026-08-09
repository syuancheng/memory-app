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
        // 本屏由 navigationDestination push 出来 → dismiss 用 .back（系统箭头）
        StudySelectionPage(title: subject.name, onBack: dismiss.callAsFunction) {
            Text("Choose what to review")
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
                    .appText(AppType.label, color: AppColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !isLoading && errorMessage == nil && tags.isEmpty {
                AppEmptyState(
                    title: "No sets yet",
                    message: "This subject has no sets, so \"All\" covers everything.",
                    density: .compact
                )
            }

            // 为底部吸附的主操作条让位
            Spacer(minLength: AppSpace.giant * 2)
        }
        .safeAreaInset(edge: .bottom) {
            // 改造前禁用态是 dark.opacity(0.32) 底 + white.opacity(0.62) 字（约 1.9:1）。
            // 现在走 AppButton 的 disabledFill + disabledText（6.92:1）。
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
                        selectedTagIDs: selectedTagIDs
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
