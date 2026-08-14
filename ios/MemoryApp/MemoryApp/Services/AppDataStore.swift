import Foundation

@MainActor
final class AppDataStore: ObservableObject {
    struct LibrarySnapshot {
        let subjects: [AppSubject]
        let sets: [AppSet]
        let cards: [ReviewCard]
    }

    private struct DueCardsKey: Hashable {
        let subjectID: String
        let setIDs: [String]

        init(subjectID: String, setIDs: [String]) {
            self.subjectID = subjectID
            self.setIDs = setIDs.sorted()
        }
    }

    private struct TimedValue<Value> {
        let value: Value
        let loadedAt: Date
    }

    private enum CacheKey: Hashable {
        case subjects
        case sets
        case cards
        case summary
    }

    @Published private(set) var subjects: [AppSubject] = []
    @Published private(set) var sets: [AppSet] = []
    @Published private(set) var cards: [ReviewCard] = []
    @Published private(set) var summary: MeSummary?

    private var activeUserID: String?
    private var generation = 0
    private var loadedAt: [CacheKey: Date] = [:]
    private var dueCardsCache: [DueCardsKey: TimedValue<[ReviewCard]>] = [:]
    private var reviewPreviewCache: [String: TimedValue<[ReviewGradePreview]>] = [:]

    private let libraryTTL: TimeInterval = 45
    private let summaryTTL: TimeInterval = 30
    private let reviewTTL: TimeInterval = 20

    func configure(userID: String?) {
        guard let userID, !userID.isEmpty else {
            clear()
            return
        }

        if activeUserID != userID {
            clear()
            activeUserID = userID
        }
    }

    func clear() {
        generation += 1
        activeUserID = nil
        subjects = []
        sets = []
        cards = []
        summary = nil
        loadedAt.removeAll()
        dueCardsCache.removeAll()
        reviewPreviewCache.removeAll()
    }

    var cachedSummary: MeSummary? {
        guard isFresh(.summary, ttl: summaryTTL) else {
            return nil
        }
        return summary
    }

    var cachedLibrary: LibrarySnapshot? {
        guard isFresh(.subjects, ttl: libraryTTL),
              isFresh(.sets, ttl: libraryTTL),
              isFresh(.cards, ttl: libraryTTL) else {
            return nil
        }
        return LibrarySnapshot(subjects: subjects, sets: sets, cards: cards)
    }

    func warmAfterSignIn() async {
        async let home: () = warmHome()
        async let library: () = warmLibrary()
        _ = await (home, library)
    }

    func warmHome() async {
        do {
            _ = try await refreshHomeData(force: false)
        } catch {
            // Preload must never block the app shell. The foreground page still
            // surfaces any error when it performs its own refresh.
        }
    }

    func warmLibrary() async {
        do {
            _ = try await refreshLibrary(force: false)
        } catch {
            // Same rule as warmHome: preload is opportunistic.
        }
    }

    func refreshHomeData(force: Bool) async throws -> (subjects: [AppSubject], summary: MeSummary) {
        if !force,
           let summary = cachedSummary,
           isFresh(.subjects, ttl: libraryTTL) {
            return (subjects, summary)
        }

        let requestGeneration = generation
        let userID = activeUserID

        async let loadedSubjects = APIClient.shared.listSubjects()
        async let loadedSummary = APIClient.shared.getMeSummary()

        let resolvedSubjects = try await loadedSubjects
        let resolvedSummary = try await loadedSummary

        guard isCurrent(requestGeneration, userID: userID) else {
            return (subjects, summary ?? resolvedSummary)
        }

        markLoaded(.subjects)
        markLoaded(.summary)
        subjects = resolvedSubjects
        summary = resolvedSummary
        return (resolvedSubjects, resolvedSummary)
    }

    func refreshSummary(force: Bool) async throws -> MeSummary {
        if !force, let cachedSummary {
            return cachedSummary
        }

        let requestGeneration = generation
        let userID = activeUserID
        let resolvedSummary = try await APIClient.shared.getMeSummary()

        guard isCurrent(requestGeneration, userID: userID) else {
            return summary ?? resolvedSummary
        }

        markLoaded(.summary)
        summary = resolvedSummary
        return resolvedSummary
    }

    func refreshLibrary(force: Bool) async throws -> LibrarySnapshot {
        if !force, let cachedLibrary {
            return cachedLibrary
        }

        let requestGeneration = generation
        let userID = activeUserID

        async let loadedSubjects = APIClient.shared.listSubjects()
        async let loadedSets = APIClient.shared.listSets()
        async let loadedCards = APIClient.shared.listCards()

        let resolvedSubjects = try await loadedSubjects
        let resolvedSets = try await loadedSets
        let resolvedCards = try await loadedCards

        guard isCurrent(requestGeneration, userID: userID) else {
            return LibrarySnapshot(subjects: subjects, sets: sets, cards: cards)
        }

        markLoaded(.subjects)
        markLoaded(.sets)
        markLoaded(.cards)
        subjects = resolvedSubjects
        sets = resolvedSets
        cards = resolvedCards

        return LibrarySnapshot(subjects: resolvedSubjects, sets: resolvedSets, cards: resolvedCards)
    }

    func cachedSets(subjectID: String) -> [AppSet]? {
        guard isFresh(.sets, ttl: libraryTTL) else {
            return nil
        }
        return sets.filter { $0.subjectID == subjectID }
    }

    func cachedCards(subjectID: String, setIDs: [String] = []) -> [ReviewCard]? {
        guard isFresh(.cards, ttl: libraryTTL) else {
            return nil
        }
        return filter(cards: cards, subjectID: subjectID, setIDs: setIDs)
    }

    func refreshSets(subjectID: String, force: Bool) async throws -> [AppSet] {
        if !force, let cached = cachedSets(subjectID: subjectID) {
            return cached
        }
        return try await APIClient.shared.listSets(subjectID: subjectID)
    }

    func refreshCards(subjectID: String, setIDs: [String] = [], force: Bool) async throws -> [ReviewCard] {
        if !force, let cached = cachedCards(subjectID: subjectID, setIDs: setIDs) {
            return cached
        }
        return try await APIClient.shared.listCards(subjectID: subjectID, setIDs: setIDs)
    }

    func cachedDueCards(subjectID: String, setIDs: [String]) -> [ReviewCard]? {
        let key = DueCardsKey(subjectID: subjectID, setIDs: setIDs)
        guard let cached = dueCardsCache[key],
              Date().timeIntervalSince(cached.loadedAt) < reviewTTL else {
            return nil
        }
        return cached.value
    }

    @discardableResult
    func preloadDueCards(subjectID: String, setIDs: [String]) async -> [ReviewCard]? {
        do {
            return try await refreshDueCards(subjectID: subjectID, setIDs: setIDs, force: false)
        } catch {
            return nil
        }
    }

    func refreshDueCards(subjectID: String, setIDs: [String], force: Bool) async throws -> [ReviewCard] {
        if !force, let cached = cachedDueCards(subjectID: subjectID, setIDs: setIDs) {
            return cached
        }

        let requestGeneration = generation
        let userID = activeUserID
        let resolvedCards = try await APIClient.shared.listDueCards(subjectID: subjectID, setIDs: setIDs)

        guard isCurrent(requestGeneration, userID: userID) else {
            return cachedDueCards(subjectID: subjectID, setIDs: setIDs) ?? resolvedCards
        }

        let key = DueCardsKey(subjectID: subjectID, setIDs: setIDs)
        dueCardsCache[key] = TimedValue(value: resolvedCards, loadedAt: Date())

        if let firstCard = resolvedCards.first {
            Task {
                _ = await preloadReviewPreviews(cardID: firstCard.id)
            }
        }

        return resolvedCards
    }

    func cachedReviewPreviews(cardID: String) -> [ReviewGradePreview]? {
        guard let cached = reviewPreviewCache[cardID],
              Date().timeIntervalSince(cached.loadedAt) < reviewTTL else {
            return nil
        }
        return cached.value
    }

    @discardableResult
    func preloadReviewPreviews(cardID: String) async -> [ReviewGradePreview]? {
        do {
            return try await refreshReviewPreviews(cardID: cardID, force: false)
        } catch {
            return nil
        }
    }

    func refreshReviewPreviews(cardID: String, force: Bool) async throws -> [ReviewGradePreview] {
        if !force, let cached = cachedReviewPreviews(cardID: cardID) {
            return cached
        }

        let requestGeneration = generation
        let userID = activeUserID
        let previews = try await APIClient.shared.getReviewPreviews(cardID: cardID)

        guard isCurrent(requestGeneration, userID: userID) else {
            return cachedReviewPreviews(cardID: cardID) ?? previews
        }

        reviewPreviewCache[cardID] = TimedValue(value: previews, loadedAt: Date())
        return previews
    }

    func invalidateAfterSubjectMutation() {
        invalidateLibraryAndSummary()
    }

    func invalidateAfterSetMutation() {
        invalidateLibraryAndSummary()
    }

    func invalidateAfterCardMutation(cardID: String? = nil) {
        invalidateLibraryAndSummary()
        dueCardsCache.removeAll()
        if let cardID {
            reviewPreviewCache.removeValue(forKey: cardID)
        } else {
            reviewPreviewCache.removeAll()
        }
    }

    func invalidateAfterReviewMutation(cardID: String) {
        generation += 1
        loadedAt[.subjects] = nil
        loadedAt[.sets] = nil
        loadedAt[.summary] = nil
        dueCardsCache.removeAll()
        reviewPreviewCache.removeValue(forKey: cardID)
    }

    func invalidateSummary() {
        generation += 1
        loadedAt[.summary] = nil
    }

    private func invalidateLibraryAndSummary() {
        generation += 1
        loadedAt.removeAll()
        dueCardsCache.removeAll()
        reviewPreviewCache.removeAll()
    }

    private func isFresh(_ key: CacheKey, ttl: TimeInterval) -> Bool {
        guard let loadedAt = loadedAt[key] else {
            return false
        }
        return Date().timeIntervalSince(loadedAt) < ttl
    }

    private func markLoaded(_ key: CacheKey) {
        loadedAt[key] = Date()
    }

    private func isCurrent(_ requestGeneration: Int, userID: String?) -> Bool {
        requestGeneration == generation && userID == activeUserID
    }

    private func filter(cards: [ReviewCard], subjectID: String, setIDs: [String]) -> [ReviewCard] {
        let setFilter = Set(setIDs)
        return cards.filter { card in
            card.subjectID == subjectID && (setFilter.isEmpty || setFilter.contains(card.set.id))
        }
    }
}
