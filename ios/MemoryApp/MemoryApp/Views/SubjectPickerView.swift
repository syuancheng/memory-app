import SwiftUI

struct SubjectPickerView: View {
    let subjects: [AppSubject]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubject: AppSubject?
    @State private var reviewTagIDs: [String] = []
    @State private var showingReview = false

    var body: some View {
        ZStack {
            if showingReview, let selectedSubject {
                ReviewSessionView(subject: selectedSubject, tagIDs: reviewTagIDs) {
                    dismiss()
                }
            } else {
                ScreenBackground()
                Color(hex: 0x1F2F28).opacity(0.14)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if selectedSubject == nil {
                            dismiss()
                        } else {
                            selectedSubject = nil
                        }
                    }

                VStack {
                    Spacer()
                    if let selectedSubject {
                        TagPickerView(
                            subject: selectedSubject,
                            onBack: { self.selectedSubject = nil },
                            onStartReview: { tagIDs in
                                reviewTagIDs = tagIDs
                                showingReview = true
                            }
                        )
                    } else {
                        subjectSheet
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.20), value: selectedSubject)
        .animation(.easeInOut(duration: 0.20), value: showingReview)
    }

    private var subjectSheet: some View {
        SheetPanel {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Choose subject")
                        .font(AppFont.medium(19))
                        .foregroundStyle(Theme.green)
                    Spacer()
                    Text("Step 1 / 2")
                        .font(AppFont.regular(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 2)

                VStack(spacing: 8) {
                    ForEach(subjects) { subject in
                        Button {
                            selectedSubject = subject
                        } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subject.name)
                                        .font(AppFont.medium(16))
                                        .foregroundStyle(Theme.text)
                                    Text(subjectMeta(subject))
                                        .font(AppFont.regular(12))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("\(subject.cardCount)")
                                    .font(AppFont.medium(15))
                                    .foregroundStyle(Theme.green2)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                            .background(Color(hex: 0xFFFDF7).opacity(0.94))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.green.opacity(0.09), lineWidth: 1)
                            )
                            .shadow(color: Theme.green.opacity(0.045), radius: 18, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func subjectMeta(_ subject: AppSubject) -> String {
        "\(subject.dueCount) due / \(subject.cardCount) cards"
    }
}
