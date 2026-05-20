import Foundation

@MainActor
extension DataStore {
    private static let historyRecordMaxTotalCount = 200
    private static let historyRecordMaxCountPerTool = 50

    var historyRetentionTotalLimit: Int {
        Self.historyRecordMaxTotalCount
    }

    var historyRetentionPerToolLimit: Int {
        Self.historyRecordMaxCountPerTool
    }

    @discardableResult
    func enforceCalculationHistoryRetention(
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        let snapshot = historyRecords
        let trimmed = applyingHistoryRetention(to: snapshot)
        let keptIDs = Set(trimmed.map(\.id))
        let removed = snapshot.filter { !keptIDs.contains($0.id) }

        replaceHistoryRecords(trimmed)

        let result = DataStoreRemovalResult(
            snapshot: snapshot,
            removed: removed,
            audit: audit,
            deferredFileCleanup: removed.isEmpty ? nil : deferredFileCleanup
        )
        if recordsAuditImmediately, !result.isEmpty {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }

    func applyingHistoryRetention(to records: [HistoryRecord]) -> [HistoryRecord] {
        guard !records.isEmpty else { return [] }
        var kept: [HistoryRecord] = []
        kept.reserveCapacity(min(records.count, Self.historyRecordMaxTotalCount))
        var toolCounts: [String: Int] = [:]

        for record in records {
            if kept.count >= Self.historyRecordMaxTotalCount {
                break
            }
            let count = toolCounts[record.tool, default: 0]
            if count >= Self.historyRecordMaxCountPerTool {
                continue
            }
            kept.append(record)
            toolCounts[record.tool] = count + 1
        }
        return kept
    }
}
