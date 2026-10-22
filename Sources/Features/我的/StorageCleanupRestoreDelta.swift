import Foundation

struct StorageCleanupRecordChange<Record: Codable & Sendable>: Codable, Sendable {
    let before: Record
    let after: Record?
}

/// Only records changed by this cleanup are retained. Later edits remain owned by the live store.
struct StorageCleanupRestoreDelta: Codable, Sendable {
    let dailyLogs: [StorageCleanupRecordChange<DailyLog>]
    let siteTodos: [StorageCleanupRecordChange<SiteTodo>]
    let quickNotes: [StorageCleanupRecordChange<QuickNote>]
    let projectDrawings: [StorageCleanupRecordChange<ProjectDrawing>]
    let projectDocuments: [StorageCleanupRecordChange<ProjectDocument>]
    let projectFinancialRecords: [StorageCleanupRecordChange<ProjectFinancialRecord>]
    let projectWarehouseMovements: [StorageCleanupRecordChange<ProjectWarehouseMovement>]

    @MainActor
    init(before: StorageCleanupUndoSnapshot, after store: DataStore) throws {
        dailyLogs = try Self.changes(before.dailyLogs, store.dailyLogs)
        siteTodos = try Self.changes(before.siteTodos, store.siteTodos)
        quickNotes = try Self.changes(before.quickNotes, store.quickNotes)
        projectDrawings = try Self.changes(before.projectDrawings, store.projectDrawings)
        projectDocuments = try Self.changes(before.projectDocuments, store.projectDocuments)
        projectFinancialRecords = try Self.changes(before.projectFinancialRecords, store.projectFinancialRecords)
        projectWarehouseMovements = try Self.changes(before.projectWarehouseMovements, store.projectWarehouseMovements)
    }

    @MainActor
    func restore(into store: DataStore) {
        let projectIDs = Set(store.projects.map(\.id))
        func projectExists(_ id: UUID?) -> Bool { id.map(projectIDs.contains) ?? true }
        store.replaceDailyLogs(Self.merge(dailyLogs, into: store.dailyLogs, canRestore: { projectExists($0.projectId) }) { before, after, current in
            guard current.projectId == before.projectId else { return }
            if current.photoFileName == after.photoFileName { current.photoFileName = before.photoFileName }
            current.photos = Self.restoreRemoved(before.photos, after: after.photos, current: current.photos)
        })
        store.replaceSiteTodos(Self.merge(siteTodos, into: store.siteTodos, canRestore: { projectExists($0.projectId) }) { before, after, current in
            guard current.projectId == before.projectId else { return }
            if current.rectificationBeforePhotoFileName == after.rectificationBeforePhotoFileName {
                current.rectificationBeforePhotoFileName = before.rectificationBeforePhotoFileName
            }
            if current.rectificationAfterPhotoFileName == after.rectificationAfterPhotoFileName {
                current.rectificationAfterPhotoFileName = before.rectificationAfterPhotoFileName
            }
        })
        store.replaceQuickNotes(Self.merge(quickNotes, into: store.quickNotes, canRestore: { projectExists($0.projectId) }) { before, after, current in
            guard current.projectId == before.projectId else { return }
            current.attachments = Self.restoreRemoved(before.attachments, after: after.attachments, current: current.attachments)
        })
        let financialIDs = Set(store.projectFinancialRecords.map(\.id))
        let existingDocumentIDs = Set(store.projectDocuments.map(\.id))
        let restoredDocumentIDs = Set(projectDocuments.filter { $0.after == nil && !existingDocumentIDs.contains($0.before.id) }.map { $0.before.id })
        store.replaceProjectDocuments(Self.merge(projectDocuments, into: store.projectDocuments, canRestore: { projectExists($0.projectId) }) { _, _, _ in }.map { document in
            var value = document
            if restoredDocumentIDs.contains(value.id), let id = value.linkedFinancialRecordId, !financialIDs.contains(id) { value.linkedFinancialRecordId = nil }
            return value
        })
        restoreDrawings(into: store, projectIDs: projectIDs)
        let documentIDs = Set(store.projectDocuments.map(\.id))
        store.replaceProjectFinancialRecords(Self.merge(projectFinancialRecords, into: store.projectFinancialRecords, canRestore: { projectExists($0.projectId) }) { before, after, current in
            guard current.projectId == before.projectId else { return }
            current.linkedDocumentIds = Self.restoreRemovedIDs(before.linkedDocumentIds, after: after.linkedDocumentIds, current: current.linkedDocumentIds, available: documentIDs)
        })
        store.replaceProjectWarehouseMovements(Self.merge(projectWarehouseMovements, into: store.projectWarehouseMovements, canRestore: { projectExists($0.projectId) }) { before, after, current in
            guard current.projectId == before.projectId else { return }
            current.linkedDocumentIds = Self.restoreRemovedIDs(before.linkedDocumentIds, after: after.linkedDocumentIds, current: current.linkedDocumentIds, available: documentIDs)
        })
    }

    @MainActor
    private func restoreDrawings(into store: DataStore, projectIDs: Set<UUID>) {
        var drawings = store.projectDrawings
        var existingIDs = Set(drawings.map(\.id))
        let todoProjects = Dictionary(store.siteTodos.compactMap { item in item.projectId.map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        let logProjects = Dictionary(store.dailyLogs.compactMap { item in item.projectId.map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        let documentProjects = Dictionary(store.projectDocuments.map { ($0.id, $0.projectId) }, uniquingKeysWith: { first, _ in first })
        for change in projectDrawings where change.after == nil {
            var drawing = change.before
            guard projectIDs.contains(drawing.projectId), existingIDs.insert(drawing.id).inserted else { continue }
            drawing.linkedTodoIDs = drawing.linkedTodoIDs.filter { todoProjects[$0] == drawing.projectId }
            drawing.linkedLogIDs = drawing.linkedLogIDs.filter { logProjects[$0] == drawing.projectId }
            drawing.linkedDocumentIDs = drawing.linkedDocumentIDs.filter { documentProjects[$0] == drawing.projectId }
            if drawing.isCurrentVersion, drawings.contains(where: {
                $0.projectId == drawing.projectId && $0.name == drawing.name && $0.isCurrentVersion
            }) {
                drawing.isCurrentVersion = false
            }
            drawings.append(drawing)
        }
        store.replaceProjectDrawings(drawings)
    }

    private static func changes<Record: Identifiable & Codable & Sendable>(_ before: [Record], _ after: [Record]) throws -> [StorageCleanupRecordChange<Record>] {
        let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try before.compactMap { record in
            let current = afterByID[record.id]
            if let current, try encoder.encode(record) == encoder.encode(current) { return nil }
            return StorageCleanupRecordChange(before: record, after: current)
        }
    }

    private static func merge<Record: Identifiable & Codable & Sendable>(
        _ changes: [StorageCleanupRecordChange<Record>], into current: [Record],
        canRestore: (Record) -> Bool, update: (Record, Record, inout Record) -> Void
    ) -> [Record] {
        var result = current
        var indices = Dictionary(result.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for change in changes where canRestore(change.before) {
            if let after = change.after {
                // An existing record deleted after cleanup must stay deleted.
                guard let index = indices[change.before.id] else { continue }
                update(change.before, after, &result[index])
            } else if indices[change.before.id] == nil {
                indices[change.before.id] = result.count
                result.append(change.before)
            }
        }
        return result
    }

    private static func restoreRemoved<Item: Identifiable>(_ before: [Item], after: [Item], current: [Item]) -> [Item] {
        let retainedIDs = Set(after.map(\.id)).union(current.map(\.id))
        return current + before.filter { !retainedIDs.contains($0.id) }
    }

    private static func restoreRemovedIDs(_ before: [UUID], after: [UUID], current: [UUID], available: Set<UUID>) -> [UUID] {
        let retainedIDs = Set(after).union(current)
        return current + before.filter { !retainedIDs.contains($0) && available.contains($0) }
    }
}

enum StorageCleanupRestoreError: LocalizedError {
    case legacySnapshot

    var errorDescription: String? {
        String(localized: "此旧版清理批次缺少变更范围，无法安全恢复业务记录。为避免覆盖后续数据，本次未恢复；原文件仍保留在回收站。")
    }
}
