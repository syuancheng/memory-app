import Foundation

struct PendingReviewSubmission: Codable, Identifiable, Hashable {
    let id: String
    let cardID: String
    let mode: String
    let rating: Rating
    let revealedTokensCount: Int
    let totalTokensCount: Int
    let createdAt: Date
}

enum PendingReviewStore {
    private static let keyPrefix = "pending-review-submissions"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func enqueue(_ submission: PendingReviewSubmission, userID: String) {
        var submissions = load(userID: userID)
        if !submissions.contains(where: { $0.id == submission.id }) {
            submissions.append(submission)
            save(submissions, userID: userID)
        }
    }

    static func remove(id: String, userID: String) {
        save(load(userID: userID).filter { $0.id != id }, userID: userID)
    }

    static func load(userID: String) -> [PendingReviewSubmission] {
        guard !userID.isEmpty,
              let data = UserDefaults.standard.data(forKey: key(userID: userID)),
              let submissions = try? decoder.decode([PendingReviewSubmission].self, from: data) else {
            return []
        }
        return submissions
    }

    @discardableResult
    static func flush(userID: String, maxAttempts: Int = 2) async -> Int {
        var synced = 0
        for submission in load(userID: userID) {
            if await submitWithRetry(submission, userID: userID, maxAttempts: maxAttempts) {
                synced += 1
            }
        }
        return synced
    }

    @discardableResult
    static func submitWithRetry(_ submission: PendingReviewSubmission, userID: String, maxAttempts: Int = 3) async -> Bool {
        var delayNanos: UInt64 = 350_000_000
        for attempt in 1...maxAttempts {
            do {
                _ = try await APIClient.shared.submitReview(
                    cardID: submission.cardID,
                    mode: submission.mode,
                    rating: submission.rating,
                    revealedCount: submission.revealedTokensCount,
                    totalTokensCount: submission.totalTokensCount,
                    clientReviewID: submission.id
                )
                remove(id: submission.id, userID: userID)
                return true
            } catch {
                if attempt == maxAttempts {
                    return false
                }
                try? await Task.sleep(nanoseconds: delayNanos)
                delayNanos *= 2
            }
        }
        return false
    }

    private static func save(_ submissions: [PendingReviewSubmission], userID: String) {
        guard !userID.isEmpty,
              let data = try? encoder.encode(submissions) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key(userID: userID))
    }

    private static func key(userID: String) -> String {
        "\(keyPrefix).\(userID)"
    }
}
