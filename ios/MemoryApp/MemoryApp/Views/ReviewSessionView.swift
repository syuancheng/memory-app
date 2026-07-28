import SwiftUI

struct ReviewSessionView: View {
    let subject: AppSubject
    let tagIDs: [String]
    let onClose: () -> Void
    @State private var cards: [ReviewCard] = []
    @State private var reviewStep = 0
    @State private var initialCardCount = 0
    @State private var completedCount = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("lastReviewSummary") private var lastReviewSummary = "No sessions yet"

    private var currentCard: ReviewCard? {
        cards.first
    }

    var body: some View {
        ZStack {
            ScreenBackground()

            if isLoading {
                ProgressView()
            } else if let currentCard {
                ReviewCardView(
                    card: currentCard,
                    progressText: "\(cards.count) left",
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
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(AppFont.regular(13))
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .background(Theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submit(rating: Rating, revealedCount: Int) async {
        guard let currentCard else {
            return
        }
        errorMessage = nil
        do {
            _ = try await APIClient.shared.submitReview(card: currentCard, rating: rating, revealedCount: revealedCount)
            if rating == .remembered {
                removeCurrentCardFromQueue()
            } else {
                retryCurrentCardLater()
            }
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
        }
    }

    private func retryCurrentCardLater() {
        guard !cards.isEmpty else {
            return
        }
        if cards.count > 1 {
            let currentCard = cards.removeFirst()
            cards.append(currentCard)
        }
        reviewStep += 1
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.green)
                .padding(.bottom, 4)

            Text("Done for now")
                .font(AppFont.medium(28))
                .foregroundStyle(Theme.text)

            Text("Completed \(completedCount) of \(initialCardCount) cards.")
                .font(AppFont.regular(15))
                .foregroundStyle(Theme.muted)

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
            .background(Theme.green.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.green.opacity(0.18), radius: 24, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
