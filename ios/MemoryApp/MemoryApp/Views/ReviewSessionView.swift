import SwiftUI

struct ReviewSessionView: View {
    var mode: StudyMode = .review
    let subject: AppSubject
    let setIDs: [String]
    let onClose: () -> Void
    @EnvironmentObject private var dataStore: AppDataStore
    @EnvironmentObject private var session: AuthSessionStore
    @State private var cards: [ReviewCard] = []
    @State private var reviewSession: ReviewSessionPayload?
    @State private var reviewStep = 0
    @State private var initialCardCount = 0
    @State private var completedCount = 0
    @State private var leechedCount = 0
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
                    progressText: "\(reviewSession?.remainingCount ?? cards.count) left",
                    gradePreviews: gradePreviews,
                    resetToken: reviewStep,
                    onClose: onClose,
                    onDelete: deleteCurrentCard,
                    onMaster: masterCurrentCard
                ) { rating, revealedCount in
                    await submit(rating: rating, revealedCount: revealedCount)
                }
            } else if let reviewSession, reviewSession.remainingCount > 0, reviewSession.nextAvailableAt != nil {
                waitingView()
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
        isLoading = true
        errorMessage = nil
        do {
            let loadedSession = try await APIClient.shared.getReviewSession(subjectID: subject.id, setIDs: setIDs, mode: mode)
            applyLoadedSession(loadedSession)
            await loadGradePreviews()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyLoadedSession(_ loadedSession: ReviewSessionPayload) {
        reviewSession = loadedSession
        cards = loadedSession.cards
        initialCardCount = loadedSession.initialTotalCount
        completedCount = loadedSession.completedCount
        leechedCount = loadedSession.leechedCount
        reviewStep += 1
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

    private func submit(rating: Rating, revealedCount: Int) async -> Bool {
        guard let currentCard else {
            return false
        }
        let submittedCard = currentCard
        guard session.user?.id?.isEmpty == false else {
            errorMessage = "Please sign in again."
            return false
        }
        guard let sessionID = reviewSession?.id else {
            errorMessage = "Review session is not ready."
            return false
        }

        errorMessage = nil
        do {
            _ = try await APIClient.shared.submitReview(
                card: submittedCard,
                mode: mode,
                rating: rating,
                revealedCount: revealedCount,
                sessionID: sessionID
            )
            dataStore.invalidateAfterReviewMutation(cardID: submittedCard.id)
            let refreshedSession = try await APIClient.shared.getReviewSession(subjectID: subject.id, setIDs: setIDs, mode: mode)
            applyLoadedSession(refreshedSession)
            await loadGradePreviews()
            Task {
                await dataStore.warmHome()
            }
            if refreshedSession.isCheckInCompleted {
                lastReviewSummary = "Completed \(refreshedSession.completedCount) cards"
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            await loadCards()
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
            await loadCards()
        } catch {
            errorMessage = error.localizedDescription
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

            Text(completionMessage)
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

    private var completionMessage: String {
        if leechedCount > 0 {
            return "Completed \(completedCount), paused \(leechedCount) hard cards."
        }
        return "Completed \(completedCount) of \(initialCardCount) cards."
    }

    private func waitingView() -> some View {
        VStack(spacing: AppSpace.md) {
            Image(systemName: "clock")
                .font(AppIcon.font(AppSpace.huge))
                .foregroundStyle(AppColor.primary)
                .padding(.bottom, AppSpace.xs)

            Text("Next card soon")
                .appText(AppType.title1)

            Text("A card is scheduled to come back shortly.")
                .appText(AppType.body, color: AppColor.textTertiary)
                .multilineTextAlignment(.center)

            AppButton(
                title: "Refresh",
                variant: .secondary,
                size: .large,
                fullWidth: true
            ) {
                Task {
                    await loadCards()
                }
            }
            .padding(.top, AppSpace.sm)
        }
        .padding(.horizontal, AppLayout.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
