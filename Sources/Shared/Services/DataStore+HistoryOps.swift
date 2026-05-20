import Foundation

@MainActor
extension DataStore {
    func appendCalculationHistory(tool: String, input: String, result: String, date: String = Formatters.now()) {
        let record = HistoryRecord(tool: tool, input: input, result: result, date: date)
        replaceHistoryRecords([record] + historyRecords)
        scheduleSave()
    }

    func mergeHistoryRecordsByID(_ records: [HistoryRecord]) {
        guard !records.isEmpty else { return }
        var current = historyRecords
        var existingIDs = Set(current.map(\.id))
        for record in records where existingIDs.insert(record.id).inserted {
            current.append(record)
        }
        replaceHistoryRecords(current)
    }

    func restoreHistoryRecords(from deletion: DataStoreRemovalResult<HistoryRecord>) {
        replaceHistoryRecords(deletion.restoredItems(current: historyRecords, id: \.id))
    }

    @discardableResult
    func removeCalculationHistory(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: historyRecords,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }
        return removeHistoryRecords(
            where: { ids.contains($0.id) },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func clearCalculationHistory(
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        removeHistoryRecords(
            where: { _ in true },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    private func removeHistoryRecords(
        where shouldRemove: (HistoryRecord) -> Bool,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        let snapshot = historyRecords
        let removed = snapshot.filter(shouldRemove)
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: snapshot,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        var values = snapshot
        values.removeAll(where: shouldRemove)
        replaceHistoryRecords(values)

        let result = DataStoreRemovalResult(
            snapshot: snapshot,
            removed: removed,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }
}
