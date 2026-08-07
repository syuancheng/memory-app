import SwiftUI

struct ReviewSessionView: View {
    var mode: StudyMode = .review
    let subject: AppSubject
    let tagIDs: [String]
    let onClose: () -> Void
    @State private var cards: [ReviewCard] = []
    @State private var reviewStep = 0
    @State private var initialCardCount = 0
    @State private var completedCount = 0
    @State private var gradePreviews: [ReviewGradePreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("lastReviewSummary") private var lastReviewSummary = "No sessions yet"

    private var currentCard: ReviewCard? {
        cards.first
    }

    var body: some View {
        ZStack {
            AppSurface.background
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if let currentCard {
                ReviewCardView(
                    mode: mode,
                    card: currentCard,
                    progressText: "\(cards.count) left",
                    gradePreviews: gradePreviews,
                    resetToken: reviewStep,
                    onClose: onClose,
                    onDelete: deleteCurrentCard,
                    onMaster: masterCurrentCard
                ) { rating, revealedCount in
                    await submit(rating: rating, revealedCount: revealedCount)
                }
            } else if initialCardCount > 0 {
                completionView
            } else {
                VStack(spacing: 10) {
                    Text("No due cards")
                        .font(AppFont.medium(22))
                    Text("Reviewed cards will return when they are due again.")
                        .font(AppFont.regular(15))
                        .foregroundStyle(AppSurface.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(AppFont.regular(13))
                        .foregroundStyle(AppSurface.coral)
                        .padding(12)
                        .background(AppSurface.cardSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppSurface.line, lineWidth: 1)
                        )
                        .padding()
                }
            }
        }
        .task {
            await loadCards()
        }
    }

    private func loadCards() async {
        isLoading = true
        errorMessage = nil
        do {
            cards = try await APIClient.shared.listDueCards(subjectID: subject.id, tagIDs: tagIDs)
            reviewStep = 0
            initialCardCount = cards.count
            completedCount = 0
            await loadGradePreviews()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadGradePreviews() async {
        guard let currentCard else {
            gradePreviews = []
            return
        }
        do {
            gradePreviews = try await APIClient.shared.getReviewPreviews(cardID: currentCard.id)
        } catch {
            gradePreviews = []
            errorMessage = error.localizedDescription
        }
    }

    private func submit(rating: Rating, revealedCount: Int) async {
        guard let currentCard else {
            return
        }
        errorMessage = nil
        do {
            _ = try await APIClient.shared.submitReview(card: currentCard, mode: mode, rating: rating, revealedCount: revealedCount)
            removeCurrentCardFromQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrentCard() async {
        guard let currentCard else {
            return
        }
        errorMessage = nil
        do {
            try await APIClient.shared.deleteCard(currentCard)
            removeCurrentCardFromQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func masterCurrentCard() async {
        guard let currentCard else {
            return
        }
        errorMessage = nil
        do {
            try await APIClient.shared.markCardMastered(currentCard)
            removeCurrentCardFromQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCurrentCardFromQueue() {
        let nextCompletedCount = completedCount + 1
        completedCount = nextCompletedCount
        if !cards.isEmpty {
            cards.removeFirst()
        }
        reviewStep += 1
        if cards.isEmpty {
            lastReviewSummary = "Completed \(nextCompletedCount) cards"
            gradePreviews = []
        } else {
            Task {
                await loadGradePreviews()
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(AppSurface.green)
                .padding(.bottom, 4)

            Text("Done for now")
                .font(AppFont.medium(28))
                .foregroundStyle(AppSurface.text)

            Text("Completed \(completedCount) of \(initialCardCount) cards.")
                .font(AppFont.regular(15))
                .foregroundStyle(AppSurface.muted)

            Button("Back to home") {
                onClose()
            }
            .buttonStyle(CompletionButtonStyle())
            .padding(.top, 10)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompletionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium(16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AppSurface.dark.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: AppSurface.dark.opacity(0.14), radius: 18, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
