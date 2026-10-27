import Foundation

@MainActor
extension DataStore {
    func appendLaborRecord(_ record: LaborRecord) {
        replaceLaborRecords(laborRecords + [record])
    }

    @discardableResult
    func updateLaborRecord(_ record: LaborRecord) -> Bool {
        var current = laborRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        replaceLaborRecords(current)
        return true
    }

    func mergeLaborRecordsByID(_ records: [LaborRecord]) {
        replaceLaborRecords(mergedFinanceElementsByID(laborRecords, with: records))
    }

    func restoreLaborRecords(from deletion: DataStoreRemovalResult<LaborRecord>) {
        replaceLaborRecords(deletion.restoredItems(current: laborRecords, id: \.id))
    }

    @discardableResult
    func removeLaborRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<LaborRecord> {
        removeFinanceElements(
            from: laborRecords,
            ids: ids,
            id: \.id,
            replace: replaceLaborRecords,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
