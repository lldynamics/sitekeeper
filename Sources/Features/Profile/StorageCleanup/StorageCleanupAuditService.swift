import Foundation

enum StorageCleanupAuditService {
    static func cleanupAuditDetail(for entry: FileQuarantineEntry) -> String {
        "\(entry.category.rawValue) · \(entry.originalFileName)"
    }

    static func record(
        _ event: StorageCleanupActionResultBuilder.AuditEvent,
        source: String
    ) {
        record(
            action: event.action,
            outcome: .started,
            summary: event.summary,
            detail: event.detail,
            source: source
        )
    }

    static func completeSucceeded(
        _ event: StorageCleanupActionResultBuilder.CompletionEvent,
        source: String
    ) -> String {
        completeSucceeded(
            action: event.action,
            summary: event.summary,
            detail: event.detail,
            statusMessage: event.statusMessage,
            source: source
        )
    }

    static func completeFailed(
        _ event: StorageCleanupActionResultBuilder.CompletionEvent,
        source: String
    ) -> String {
        completeFailed(
            action: event.action,
            summary: event.summary,
            detail: event.detail,
            statusMessage: event.statusMessage,
            source: source
        )
    }

    static func record(
        action: OperationAuditEntry.Action,
        outcome: OperationAuditEntry.Outcome,
        summary: String,
        detail: String,
        source: String
    ) {
        OperationAuditLog.record(
            action: action,
            outcome: outcome,
            summary: summary,
            detail: detail,
            source: source
        )
    }

    static func completeSucceeded(
        action: OperationAuditEntry.Action,
        summary: String,
        detail: String,
        statusMessage: String,
        source: String
    ) -> String {
        record(
            action: action,
            outcome: .succeeded,
            summary: summary,
            detail: detail,
            source: source
        )
        return statusMessage
    }

    static func completeFailed(
        action: OperationAuditEntry.Action,
        summary: String,
        detail: String,
        statusMessage: String,
        source: String
    ) -> String {
        record(
            action: action,
            outcome: .failed,
            summary: summary,
            detail: detail,
            source: source
        )
        return statusMessage
    }
}
