import Foundation

@MainActor
extension DataStore {
    func appendProjectDrawing(_ drawing: ProjectDrawing) {
        replaceProjectDrawings(projectDrawings + [drawing])
    }

    func appendProjectDrawings(_ drawings: [ProjectDrawing]) {
        guard !drawings.isEmpty else { return }
        replaceProjectDrawings(projectDrawings + drawings)
    }

    @discardableResult
    func updateProjectDrawing(_ drawing: ProjectDrawing) -> Bool {
        var current = projectDrawings
        guard let index = current.firstIndex(where: { $0.id == drawing.id }) else { return false }
        current[index] = drawing
        replaceProjectDrawings(current)
        return true
    }

    @discardableResult
    func mutateProjectDrawing(
        id: UUID,
        _ mutation: (inout ProjectDrawing) -> Void
    ) -> Bool {
        var current = projectDrawings
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectDrawings(current)
        return true
    }

    func mergeProjectDrawingsByID(_ drawings: [ProjectDrawing]) {
        guard !drawings.isEmpty else { return }
        var current = projectDrawings
        var existingIDs = Set(current.map(\.id))
        for drawing in drawings where existingIDs.insert(drawing.id).inserted {
            current.append(drawing)
        }
        replaceProjectDrawings(current)
    }

    func restoreProjectDrawings(from deletion: DataStoreRemovalResult<ProjectDrawing>) {
        replaceProjectDrawings(deletion.restoredItems(current: projectDrawings, id: \.id))
    }

    @discardableResult
    func removeProjectDrawings(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDrawing> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: projectDrawings,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }
        return removeProjectDrawingElements(
            from: projectDrawings,
            where: { ids.contains($0.id) },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeProjectDrawings(
        where shouldRemove: (ProjectDrawing) -> Bool,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDrawing> {
        removeProjectDrawingElements(
            from: projectDrawings,
            where: shouldRemove,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    private func removeProjectDrawingElements(
        from current: [ProjectDrawing],
        where shouldRemove: (ProjectDrawing) -> Bool,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDrawing> {
        let removed = current.filter(shouldRemove)
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        replaceProjectDrawings(current.filter { !shouldRemove($0) })

        let result = DataStoreRemovalResult(
            snapshot: current,
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
