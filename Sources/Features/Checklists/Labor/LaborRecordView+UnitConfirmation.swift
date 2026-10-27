import SwiftUI

extension LaborRecordView {
    func openFocusedLaborIfNeeded() {
        guard let focusedLaborId, !didOpenFocusedLabor,
              let record = store.laborRecords.first(where: { $0.id == focusedLaborId }) else { return }
        didOpenFocusedLabor = true
        searchText = ""
        projectFilter = record.projectId
        Task { @MainActor in
            editingRecord = record
        }
    }

    func requestBulkUnitConfirmation(_ unit: LaborWorkloadUnit) {
        guard unit != .legacyUnspecified else { return }
        let visibleIDs = Set(filtered.map(\.id))
        let recordIDs = LaborUnitConfirmation.eligibleRecordIDs(in: filtered, limitedTo: visibleIDs)
        guard !recordIDs.isEmpty else { return }
        pendingBulkUnit = unit
        pendingBulkRecordIDs = recordIDs
        showBulkUnitConfirmation = true
    }

    var bulkUnitConfirmationMessage: String {
        guard let pendingBulkUnit else { return "" }
        return String(
            format: AppLocalization.string("将当前筛选出的 %lld 条记录确认为“%@”？数值和金额不会换算。"),
            Int64(pendingBulkRecordIDs.count),
            pendingBulkUnit.displayName
        )
    }

    func applyBulkUnitConfirmation() {
        guard let pendingBulkUnit else { return }
        let ids = LaborUnitConfirmation.eligibleRecordIDs(
            in: store.laborRecords,
            limitedTo: pendingBulkRecordIDs
        )
        guard !ids.isEmpty else {
            clearPendingBulkUnitConfirmation()
            return
        }
        store.replaceLaborRecords(LaborUnitConfirmation.applying(
            pendingBulkUnit,
            to: store.laborRecords,
            recordIDs: ids
        ))
        store.scheduleSave()
        operationNotice = .info(String(
            format: AppLocalization.string("已确认 %lld 条人工记录的计量单位"),
            Int64(ids.count)
        ))
        clearPendingBulkUnitConfirmation()
        unitFilter = .all
    }

    func clearPendingBulkUnitConfirmation() {
        pendingBulkUnit = nil
        pendingBulkRecordIDs = []
    }

    static func isValidExportedFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}
