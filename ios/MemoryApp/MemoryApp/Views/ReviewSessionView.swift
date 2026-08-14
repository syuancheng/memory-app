import SwiftUI

struct ReviewSessionView: View {
    var mode: StudyMode = .review
    let subject: AppSubject
    let setIDs: [String]
    let onClose: () -> Void
    @EnvironmentObject private var dataStore: AppDataStore
    @EnvironmentObject private var session: AuthSessionStore
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
            AppColor.surfaceBase
                .ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .tint(AppColor.primary)
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
                AppEmptyState(
                    icon: "checkmark.circle",
                    title: "No due cards",
                    message: "Reviewed cards will return when they are due again."
                )
                .padding(.horizontal, AppLayout.screenMargin)
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .appText(AppType.label, color: AppColor.dangerText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpace.md)
                        .background(AppColor.dangerSoft, in: AppRadius.shape(AppRadius.md))
                        .padding(AppLayout.screenMargin)
                }
            }
        }
        .task {
            await loadCards()
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func loadCards() async {
        if let cachedCards = dataStore.cachedDueCards(subjectID: subject.id, setIDs: setIDs) {
            applyLoadedCards(cachedCards)
            await loadGradePreviews()
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let loadedCards = try await dataStore.refreshDueCards(subjectID: subject.id, setIDs: setIDs, force: false)
            applyLoadedCards(loadedCards)
            await loadGradePreviews()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyLoadedCards(_ loadedCards: [ReviewCard]) {
        cards = loadedCards
        reviewStep = 0
        initialCardCount = loadedCards.count
        completedCount = 0
    }

    private func loadGradePreviews() async {
        guard let currentCard else {
            gradePreviews = []
            return
        }
        do {
            if let cachedPreviews = dataStore.cachedReviewPreviews(cardID: currentCard.id) {
                gradePreviews = cachedPreviews
            } else {
                gradePreviews = try await dataStore.refreshReviewPreviews(cardID: currentCard.id, force: false)
            }
        } catch {
            gradePreviews = []
            errorMessage = error.localizedDescription
        }
        preloadUpcomingGradePreview()
    }

    private func submit(rating: Rating, revealedCount: Int) async {
        guard let currentCard else {
            return
        }
        let submittedCard = currentCard
        guard let userID = session.user?.id, !userID.isEmpty else {
            errorMessage = "Please sign in again."
            return
        }
        let submission = PendingReviewSubmission(
            id: UUID().uuidString,
            cardID: submittedCard.id,
            mode: mode.rawValue,
            rating: rating,
            revealedTokensCount: revealedCount,
            totalTokensCount: submittedCard.answerTokens.count,
            createdAt: Date()
        )
        errorMessage = nil
        PendingReviewStore.enqueue(submission, userID: userID)

        removeCurrentCardFromQueue()

        Task {
            let didSync = await PendingReviewStore.submitWithRetry(submission, userID: userID)
            if didSync {
                dataStore.invalidateAfterReviewMutation(cardID: submittedCard.id)
                await dataStore.warmHome()
            } else {
                errorMessage = "Review saved locally. It will sync when the connection is stable."
            }
        }
    }

    private func deleteCurrentCard() async {
        guard let currentCard else {
            return
        }
        errorMessage = nil
        do {
            try await APIClient.shared.deleteCard(currentCard)
            dataStore.invalidateAfterCardMutation(cardID: currentCard.id)
            Task {
                await dataStore.warmAfterSignIn()
            }
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
            dataStore.invalidateAfterReviewMutation(cardID: currentCard.id)
            Task {
                await dataStore.warmHome()
            }
            removeCurrentCardFromQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCurrentCardFromQueue() {
        let nextCompletedCount = completedCount + 1
        let nextCard = cards.dropFirst().first
        completedCount = nextCompletedCount
        if !cards.isEmpty {
            cards.removeFirst()
        }
        reviewStep += 1
        if cards.isEmpty {
            lastReviewSummary = "Completed \(nextCompletedCount) cards"
            gradePreviews = []
        } else {
            gradePreviews = nextCard.flatMap { dataStore.cachedReviewPreviews(cardID: $0.id) } ?? []
            Task {
                await loadGradePreviews()
            }
        }
    }

    private func preloadUpcomingGradePreview() {
        guard cards.count > 1 else {
            return
        }
        let upcomingCard = cards[1]
        Task {
            _ = await dataStore.preloadReviewPreviews(cardID: upcomingCard.id)
        }
    }

    private var completionView: some View {
        VStack(spacing: AppSpace.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppIcon.font(AppSpace.huge))
                .foregroundStyle(AppColor.successFill)   // 图标场景，3.77:1 达标（非文字）
                .padding(.bottom, AppSpace.xs)

            Text("Done for now")
                .appText(AppType.title1)

            Text("Completed \(completedCount) of \(initialCardCount) cards.")
                .appText(AppType.body, color: AppColor.textTertiary)
                .multilineTextAlignment(.center)

            AppButton(
                title: "Back to home",
                variant: .primary,
                size: .large,
                fullWidth: true,
                action: onClose
            )
            .padding(.top, AppSpace.sm)
        }
        .padding(.horizontal, AppLayout.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
