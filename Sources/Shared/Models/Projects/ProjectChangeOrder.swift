import Foundation

/// An independent field record. Its amounts never change the project's contract or ledger.
struct ProjectChangeOrder: Identifiable, Codable, Equatable, Sendable {
    enum ConfirmationState: String, CaseIterable, Codable, Sendable {
        case draft, pendingConfirmation, confirmed, declined

        var displayName: String {
            switch self {
            case .draft: return AppLocalization.string("增项草稿")
            case .pendingConfirmation: return AppLocalization.string("增项待确认")
            case .confirmed: return AppLocalization.string("增项已确认")
            case .declined: return AppLocalization.string("增项不采用")
            }
        }
    }

    var id: UUID
    var title: String
    var detail: String
    var proposedAmount: MoneyValue
    var confirmedAmount: MoneyValue
    var requester: String
    var createdAt: BusinessDateValue
    var confirmationState: ConfirmationState
    var confirmedBy: String
    var confirmedAt: BusinessDateValue?
    var confirmationNote: String
    /// References only; the original documents remain owned by their project.
    var documentIDs: [UUID]

    init(id: UUID = UUID(), title: String, detail: String = "", proposedAmount: MoneyValue = .empty,
         confirmedAmount: MoneyValue = .empty, requester: String = "", createdAt: BusinessDateValue = .now(),
         confirmationState: ConfirmationState = .draft, confirmedBy: String = "",
         confirmedAt: BusinessDateValue? = nil, confirmationNote: String = "", documentIDs: [UUID] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.proposedAmount = proposedAmount
        self.confirmedAmount = confirmedAmount
        self.requester = requester
        self.createdAt = createdAt
        self.confirmationState = confirmationState
        self.confirmedBy = confirmedBy
        self.confirmedAt = confirmedAt
        self.confirmationNote = confirmationNote
        self.documentIDs = documentIDs
    }

    func validate(projectID: UUID, documents: [ProjectDocument]) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.titleRequired
        }
        guard [proposedAmount, confirmedAmount].allSatisfy({ $0.isEmpty || ($0.isValid && !$0.isNegative) }) else {
            throw ValidationError.invalidAmount
        }
        let available = Set(documents.filter { $0.projectId == projectID }.map(\.id))
        guard Set(documentIDs).count == documentIDs.count, Set(documentIDs).isSubset(of: available) else {
            throw ValidationError.unavailableDocument
        }
        if confirmationState == .confirmed {
            guard confirmedAmount.isValid, !confirmedAmount.isNegative,
                  !confirmedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  confirmedAt?.isResolved == true else { throw ValidationError.confirmationRequired }
        }
    }

    enum ValidationError: LocalizedError {
        case titleRequired, invalidAmount, unavailableDocument, confirmationRequired

        var errorDescription: String? {
            switch self {
            case .titleRequired: return AppLocalization.string("请填写增项标题。")
            case .invalidAmount: return AppLocalization.string("增项金额须为有效的非负数，未确定时可留空。")
            case .unavailableDocument: return AppLocalization.string("关联资料已失效或不属于当前项目，请重新选择。")
            case .confirmationRequired: return AppLocalization.string("记录确认前，请填写有效确认金额、记录人和确认日期。")
            }
        }
    }
}
