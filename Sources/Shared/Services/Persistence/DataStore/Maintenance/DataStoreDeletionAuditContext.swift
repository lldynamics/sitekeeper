import Foundation

struct DataStoreDeletionAuditContext {
    let summary: String
    var detail: String = ""
    var source: String = ""

    func record(outcome: OperationAuditEntry.Outcome) {
        OperationAuditLog.record(
            action: .delete,
            outcome: outcome,
            summary: summary,
            detail: detail,
            source: source
        )
    }
}
