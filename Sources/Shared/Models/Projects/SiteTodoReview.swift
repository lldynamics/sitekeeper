import Foundation

struct SiteTodoReview: Codable, Equatable, Sendable {
    enum Status: String, CaseIterable, Codable, Sendable {
        case rectifying, awaitingReview, closed
        var displayName: String {
            switch self {
            case .rectifying: return AppLocalization.string("整改中")
            case .awaitingReview: return AppLocalization.string("待复验")
            case .closed: return AppLocalization.string("复验通过并关闭")
            }
        }
    }

    struct Record: Identifiable, Codable, Equatable, Sendable {
        enum Outcome: String, Codable, Sendable {
            case passed, returned
            var displayName: String {
                switch self {
                case .passed: return AppLocalization.string("复验通过")
                case .returned: return AppLocalization.string("退回整改")
                }
            }
        }
        var id = UUID()
        var outcome: Outcome
        var reviewedAt: BusinessDateValue
        var reviewer: String
        var note: String
    }

    var status: Status = .rectifying
    var reviewer: String = ""
    var history: [Record] = []
    /// Persist unfinished review input with the todo and its form draft.
    var pendingNote: String? = nil

    var canDisable: Bool { history.isEmpty && status != .closed }
    var hasValidClosure: Bool {
        guard status == .closed, let last = history.last else { return false }
        return last.outcome == .passed && last.reviewedAt.isResolved
            && !last.reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension SiteTodo {
    mutating func enableReview() {
        guard review == nil else { return }
        review = SiteTodoReview()
        isDone = false
        completedAt = nil
    }

    @discardableResult
    mutating func disableReviewIfUnused() -> Bool {
        guard review?.canDisable == true else { return false }
        review = nil
        isDone = false
        completedAt = nil
        return true
    }

    /// Ordinary todos retain their completion behavior; reviewed todos submit for review.
    mutating func requestCompletion(at date: BusinessDateValue = .now()) {
        guard review != nil else {
            isDone = true
            if completedAt == nil { completedAt = date }
            return
        }
        if review?.status == .rectifying { review?.status = .awaitingReview }
        normalizeReviewCompletion()
    }

    mutating func reopenForWork() {
        review?.status = .rectifying
        isDone = false
        completedAt = nil
    }

    mutating func toggleCompletionForWorkflow(at date: BusinessDateValue = .now()) {
        if isDone { reopenForWork() } else { requestCompletion(at: date) }
    }

    /// Called at draft-save and decode boundaries so completion cannot bypass review.
    mutating func normalizeReviewCompletion() {
        guard let review else { return }
        isDone = review.hasValidClosure
        completedAt = isDone ? review.history.last?.reviewedAt : nil
        if review.status == .closed && !review.hasValidClosure { self.review?.status = .rectifying }
    }

    @discardableResult
    mutating func recordReview(outcome: SiteTodoReview.Record.Outcome, reviewer: String,
                               note: String, at date: BusinessDateValue = .now()) -> Bool {
        let person = reviewer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard review?.status == .awaitingReview, !person.isEmpty, date.isResolved else { return false }
        review?.reviewer = person
        review?.history.append(.init(outcome: outcome, reviewedAt: date, reviewer: person, note: note))
        review?.pendingNote = nil
        review?.status = outcome == .passed ? .closed : .rectifying
        normalizeReviewCompletion()
        return true
    }
}
