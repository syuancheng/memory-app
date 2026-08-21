import SwiftUI

/// 今天的新学/复习目标刚好达成时弹出的里程碑提示——`justCompleted` 是这一刻
/// 完成的那一边，`otherRemaining` 是另一边这时候还剩多少，决定按钮组合。
private enum DailyGoalSide {
    case learn
    case review
}

private struct DailyGoalMilestone {
    let justCompleted: DailyGoalSide
    let otherRemaining: Int
    var isFullyComplete: Bool { otherRemaining == 0 }
}

struct ReviewSessionView: View {
    let subject: AppSubject
    let setIDs: [String]
    let onClose: () -> Void
    @EnvironmentObject private var dataStore: AppDataStore
    @EnvironmentObject private var session: AuthSessionStore
    @State private var currentMode: StudyMode
    @State private var cards: [ReviewCard] = []
    @State private var reviewSession: ReviewSessionPayload?
    @State private var reviewStep = 0
    @State private var initialCardCount = 0
    @State private var completedCount = 0
    @State private var gradePreviews: [ReviewGradePreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var milestone: DailyGoalMilestone?
    @State private var hasResolvedLearnMilestone = false
    @State private var hasResolvedReviewMilestone = false
    @State private var isCheckingIn = false
    @AppStorage("lastReviewSummary") private var lastReviewSummary = "No sessions yet"

    /// mode 现在落在 @State 里（而不是普通 var）——「复习完成后去新学」需要在
    /// 同一个 ReviewSessionView 里直接切换模式重新拉候选池，不用绕回
    /// SubjectPickerView 重新选 subject/set。外部调用方式（含参数名 mode）不变。
    init(mode: StudyMode = .review, subject: AppSubject, setIDs: [String], onClose: @escaping () -> Void) {
        _currentMode = State(initialValue: mode)
        self.subject = subject
        self.setIDs = setIDs
        self.onClose = onClose
    }

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
            } else if let milestone {
                milestoneView(milestone)
            } else if let currentCard {
                ReviewCardView(
                    mode: currentMode,
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
            } else if let reviewSession, reviewSession.nextAvailableAt != nil {
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
            let loadedSession = try await APIClient.shared.getReviewSession(subjectID: subject.id, setIDs: setIDs, mode: currentMode)
            reviewSession = loadedSession
            cards = loadedSession.cards
            initialCardCount = loadedSession.cards.count
            completedCount = 0
            reviewStep += 1
            await loadGradePreviews()
            // 万一今天的目标在打开这个会话之前就已经达成了（比如刚在另一个科目学完），
            // 一进来就该看到里程碑提示，不用等提交一张卡才发现。
            if let summary = try? await dataStore.refreshSummary(force: false) {
                evaluateMilestone(summary: summary)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func applyRefreshedSession(_ loadedSession: ReviewSessionPayload) {
        reviewSession = loadedSession
        cards = loadedSession.cards
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

        errorMessage = nil
        do {
            let updatedState = try await APIClient.shared.submitReview(
                card: submittedCard,
                mode: currentMode,
                rating: rating,
                revealedCount: revealedCount
            )
            dataStore.invalidateAfterReviewMutation(cardID: submittedCard.id)

            if currentMode == .learn {
                try await handleLearnSubmit(submittedCard: submittedCard, updatedState: updatedState)
            } else {
                try await handleReviewSubmit()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Learn 模式提交后的本地循环：不再整包刷新会话——评分返回的 `ReviewState.state`
    /// 直接告诉我们这张卡毕不毕业，毕业了就从今天这批里拿掉、没毕业就塞回队列末尾
    /// 立刻可以再出现，不用等 FSRS 给的短期 due_at，也不用等一趟网络往返。只有当
    /// 本地队列真正空了，才发一次请求去确认没有别的到期内容、拿权威 summary 判定
    /// 今天的新卡目标是不是刚好达成。
    private func handleLearnSubmit(submittedCard: ReviewCard, updatedState: ReviewState) async throws {
        let graduated = updatedState.state == 2 || updatedState.state == 3 // Review / Relearning
        cards.removeFirst()
        if graduated {
            completedCount += 1
        } else {
            cards.append(submittedCard)
        }
        reviewStep += 1
        await loadGradePreviews()

        if cards.isEmpty {
            async let sessionTask = APIClient.shared.getReviewSession(subjectID: subject.id, setIDs: setIDs, mode: currentMode)
            async let summaryTask: MeSummary? = try? await dataStore.refreshSummary(force: true)
            let refreshedSession = try await sessionTask
            applyRefreshedSession(refreshedSession)
            if let refreshedSummary = await summaryTask {
                evaluateMilestone(summary: refreshedSummary)
            }
            if refreshedSession.cards.isEmpty && refreshedSession.nextAvailableAt == nil {
                lastReviewSummary = "Completed \(completedCount) cards"
            }
        } else {
            // 队列还没清空，今天的目标不可能刚好达成——只在后台把 summary/首页角标
            // 刷新一下，不阻塞下一张卡的展示。
            Task {
                _ = try? await dataStore.refreshSummary(force: true)
            }
        }
    }

    /// Review 模式维持原来的行为：每次提交后整包重新拉取候选池。
    private func handleReviewSubmit() async throws {
        completedCount += 1
        // 显式同步刷新 summary（而不是 fire-and-forget 的 warmHome），因为下面
        // 马上要用这次提交之后最新的 remaining 数字判断今天的目标是不是刚好
        // 达成——跟拉候选池并发发出，避免在每张卡之间多等一整趟串行请求。
        async let sessionTask = APIClient.shared.getReviewSession(subjectID: subject.id, setIDs: setIDs, mode: currentMode)
        async let summaryTask: MeSummary? = try? await dataStore.refreshSummary(force: true)
        let refreshedSession = try await sessionTask
        applyRefreshedSession(refreshedSession)
        await loadGradePreviews()
        if let refreshedSummary = await summaryTask {
            evaluateMilestone(summary: refreshedSummary)
        }
        if refreshedSession.cards.isEmpty && refreshedSession.nextAvailableAt == nil {
            lastReviewSummary = "Completed \(completedCount) cards"
        }
    }

    /// 只在「当前模式对应的目标从大于 0 变成 0」那一刻弹一次；用户点过「继续」
    /// 之后就不再为同一边重复打扰，但切到另一边、那边也刚好达成时仍然要弹。
    private func evaluateMilestone(summary: MeSummary) {
        if currentMode == .learn, summary.newRemainingToday == 0, !hasResolvedLearnMilestone {
            hasResolvedLearnMilestone = true
            milestone = DailyGoalMilestone(justCompleted: .learn, otherRemaining: summary.reviewRemainingToday)
        } else if currentMode == .review, summary.reviewRemainingToday == 0, !hasResolvedReviewMilestone {
            hasResolvedReviewMilestone = true
            milestone = DailyGoalMilestone(justCompleted: .review, otherRemaining: summary.newRemainingToday)
        }
    }

    private func switchMode(to newMode: StudyMode) {
        currentMode = newMode
        milestone = nil
        Task {
            await loadCards()
        }
    }

    private func checkInFromMilestone() async {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        errorMessage = nil
        do {
            let updatedSummary = try await APIClient.shared.checkIn()
            dataStore.applyRefreshedSummary(updatedSummary)
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCheckingIn = false
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
        "Completed \(completedCount) of \(initialCardCount) cards."
    }

    @ViewBuilder
    private func milestoneView(_ milestone: DailyGoalMilestone) -> some View {
        VStack(spacing: AppSpace.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(AppIcon.font(AppSpace.huge))
                .foregroundStyle(AppColor.successFill)
                .padding(.bottom, AppSpace.xs)

            Text(milestoneTitle(milestone))
                .appText(AppType.title1)

            Text(milestoneMessage(milestone))
                .appText(AppType.body, color: AppColor.textTertiary)
                .multilineTextAlignment(.center)

            VStack(spacing: AppSpace.sm) {
                if milestone.isFullyComplete {
                    AppButton(
                        title: "Check in for today",
                        variant: .primary,
                        size: .large,
                        fullWidth: true,
                        isEnabled: !isCheckingIn,
                        isLoading: isCheckingIn
                    ) {
                        Task {
                            await checkInFromMilestone()
                        }
                    }
                } else {
                    AppButton(
                        title: milestone.justCompleted == .learn ? "Go review" : "Go learn",
                        variant: .primary,
                        size: .large,
                        fullWidth: true
                    ) {
                        switchMode(to: milestone.justCompleted == .learn ? .review : .learn)
                    }
                }

                AppButton(
                    title: milestone.justCompleted == .learn ? "Keep learning" : "Keep reviewing",
                    variant: .secondary,
                    size: .large,
                    fullWidth: true
                ) {
                    self.milestone = nil
                }

                AppButton(
                    title: "Done",
                    variant: .ghost,
                    size: .large,
                    fullWidth: true,
                    action: onClose
                )
            }
            .padding(.top, AppSpace.sm)
        }
        .padding(.horizontal, AppLayout.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func milestoneTitle(_ milestone: DailyGoalMilestone) -> String {
        if milestone.isFullyComplete {
            return "All done for today"
        }
        return milestone.justCompleted == .learn ? "Today's new cards are done" : "Today's reviews are done"
    }

    private func milestoneMessage(_ milestone: DailyGoalMilestone) -> String {
        if milestone.isFullyComplete {
            return "You've finished today's new cards and reviews. Check in to keep your streak going."
        }
        switch milestone.justCompleted {
        case .learn:
            let count = milestone.otherRemaining
            return "You still have \(count) review\(count == 1 ? "" : "s") left today. Keep learning, or go finish your reviews."
        case .review:
            let count = milestone.otherRemaining
            return "You still have \(count) new card\(count == 1 ? "" : "s") to learn today. Keep reviewing, or go learn something new."
        }
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
