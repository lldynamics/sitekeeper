import Foundation

@MainActor
extension DataStore {
    func appendProjectFinancialRecord(_ record: ProjectFinancialRecord) {
        replaceProjectFinancialRecords(projectFinancialRecords + [record])
    }

    @discardableResult
    func updateProjectFinancialRecord(_ record: ProjectFinancialRecord) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        replaceProjectFinancialRecords(current)
        return true
    }

    @discardableResult
    func mutateProjectFinancialRecord(
        id: UUID,
        _ mutation: (inout ProjectFinancialRecord) -> Void
    ) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectFinancialRecords(current)
        return true
    }

    func mergeProjectFinancialRecordsByID(_ records: [ProjectFinancialRecord]) {
        replaceProjectFinancialRecords(mergedProjectRecordElementsByID(projectFinancialRecords, with: records))
    }

    @discardableResult
    func removeProjectFinancialRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectFinancialRecord> {
        removeProjectRecordElements(
            from: projectFinancialRecords,
            ids: ids,
            id: \.id,
            replace: replaceProjectFinancialRecords,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
