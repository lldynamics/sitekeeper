import Foundation

extension ReportBuilder {
    static func operationAuditActionDisplayName(_ action: OperationAuditEntry.Action) -> String {
        switch action {
        case .import:
            return loc("导入")
        case .restore:
            return loc("恢复")
        case .cleanup:
            return loc("清理")
        case .repair:
            return loc("修复")
        case .delete:
            return loc("删除")
        }
    }

    static func operationAuditOutcomeDisplayName(_ outcome: OperationAuditEntry.Outcome) -> String {
        switch outcome {
        case .started:
            return loc("开始")
        case .succeeded:
            return loc("完成")
        case .failed:
            return loc("失败")
        case .cancelled:
            return loc("取消")
        }
    }

    static func operationAuditDisplayHeaders() -> [String] {
        loc(["时间", "操作", "结果", "摘要", "详情", "来源", "ID"])
    }

    static func operationAuditDisplayRow(_ entry: OperationAuditEntry) -> [String] {
        [
            Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp)),
            operationAuditActionDisplayName(entry.action),
            operationAuditOutcomeDisplayName(entry.outcome),
            entry.summary,
            entry.detail,
            entry.source,
            entry.id.uuidString
        ]
    }

    static func operationAuditPDFLine(_ entry: OperationAuditEntry) -> String {
        let timestamp = Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp))
        let action = operationAuditActionDisplayName(entry.action)
        let outcome = operationAuditOutcomeDisplayName(entry.outcome)
        let detail = entry.detail.isEmpty ? "" : "  \(entry.detail)"
        let source = entry.source.isEmpty ? "" : "  \(entry.source)"
        return "- \(timestamp) [\(action) / \(outcome)] \(entry.summary)\(detail)\(source)"
    }
}
