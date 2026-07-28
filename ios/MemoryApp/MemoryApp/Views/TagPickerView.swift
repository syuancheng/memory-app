import SwiftUI

struct TagPickerView: View {
    let subject: AppSubject
    let onBack: () -> Void
    let onStartReview: ([String]) -> Void

    @State private var tags: [AppTag] = []
    @State private var selectedTagIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var selectedDueCount: Int {
        tags
            .filter { selectedTagIDs.contains($0.id) }
            .reduce(0) { $0 + $1.dueCount }
    }

    private var canStartReview: Bool {
        !selectedTagIDs.isEmpty && selectedDueCount > 0
    }

    var body: some View {
        SheetPanel {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(subject.name)
                        .font(AppFont.medium(19))
                        .foregroundStyle(Theme.green)
                    Spacer()
                    Button("Subject") {
                        onBack()
                    }
                    .font(AppFont.medium(15))
                    .foregroundStyle(Theme.green)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)

                HStack {
                    Button(!tags.isEmpty && selectedTagIDs.count == tags.count ? "All tags selected" : "Select all tags") {
                        selectedTagIDs = Set(tags.map(\.id))
                    }
                    .disabled(tags.isEmpty)
                    .font(AppFont.medium(12))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.greenSoft)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.green.opacity(0.14), lineWidth: 1))
                    .buttonStyle(.plain)

                    Spacer()

                    Text("\(selectedTagIDs.count) selected · \(selectedDueCount) due")
                        .font(AppFont.regular(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 2)
                .padding(.bottom, -2)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 128)
                } else {
                    VStack(spacing: 8) {
                        ForEach(tags) { tag in
                            Button {
                                toggle(tag)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selectedTagIDs.contains(tag.id) ? Theme.green : .clear)
                                            .frame(width: 22, height: 22)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .stroke(selectedTagIDs.contains(tag.id) ? Theme.green : Theme.green.opacity(0.24), lineWidth: 1.5)
                                            )
                                        if selectedTagIDs.contains(tag.id) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tag.name)
                                            .font(AppFont.medium(16))
                                            .foregroundStyle(Theme.text)
                                        Text(tagMeta(tag))
                                            .font(AppFont.regular(12))
                                            .foregroundStyle(Theme.muted)
                                    }

                                    Spacer()

                                    Text("\(tag.cardCount)")
                                        .font(AppFont.medium(15))
                                        .foregroundStyle(Theme.green2)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 50)
                                .background(
                                    selectedTagIDs.contains(tag.id)
                                        ? LinearGradient(colors: [.white, Color(hex: 0xF3FAF6)], startPoint: .top, endPoint: .bottom)
                                        : LinearGradient(colors: [Color(hex: 0xFFFDF7).opacity(0.94), Color(hex: 0xFFFDF7).opacity(0.94)], startPoint: .top, endPoint: .bottom)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                                        .stroke(selectedTagIDs.contains(tag.id) ? Theme.green.opacity(0.18) : Theme.green.opacity(0.09), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.regular(13))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isLoading && errorMessage == nil && !canStartReview {
                    Text(tags.isEmpty ? "No tags in this subject yet." : "No due cards in the selected tags.")
                        .font(AppFont.regular(12))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }

                Button("Review selected · \(selectedTagIDs.count)") {
                    onStartReview(Array(selectedTagIDs))
                }
                .disabled(!canStartReview)
                .buttonStyle(SheetActionButtonStyle(kind: .primary))
                .padding(.top, 2)
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
            selectedTagIDs = Set(tags.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggle(_ tag: AppTag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
    }

    private func tagMeta(_ tag: AppTag) -> String {
        "\(tag.dueCount) due / \(tag.cardCount) cards"
    }
}

struct SheetActionButtonStyle: ButtonStyle {
    enum Kind {
        case ghost
        case primary
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium(16))
            .foregroundStyle(kind == .primary ? Color(hex: 0xFFFAF2).opacity(isEnabled ? 1 : 0.64) : Theme.green)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background(configuration: configuration))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.green.opacity(kind == .primary ? 0 : 0.13), lineWidth: 1)
            )
            .shadow(color: Theme.green.opacity(0.10), radius: 24, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }

    private func background(configuration: Configuration) -> Color {
        switch kind {
        case .ghost:
            return Color(hex: 0xFFFDF7).opacity(configuration.isPressed ? 0.82 : 1)
        case .primary:
            return Theme.green.opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1) : 0.38)
        }
    }
}
