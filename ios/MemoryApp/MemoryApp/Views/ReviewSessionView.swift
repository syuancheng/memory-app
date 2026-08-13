import SwiftUI

struct ReviewSessionView: View {
    var mode: StudyMode = .review
    let subject: AppSubject
    let setIDs: [String]
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
        isLoading = true
        errorMessage = nil
        do {
            cards = try await APIClient.shared.listDueCards(subjectID: subject.id, setIDs: setIDs)
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
