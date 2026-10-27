import Foundation

@MainActor
extension DataStore {
    func appendQuickNote(_ note: QuickNote) {
        replaceQuickNotes(quickNotes + [note])
    }

    func insertQuickNoteAtTop(_ note: QuickNote) {
        var notes = quickNotes
        notes.insert(note, at: 0)
        replaceQuickNotes(notes)
    }

    @discardableResult
    func updateQuickNote(_ note: QuickNote) -> Bool {
        var current = quickNotes
        guard let index = current.firstIndex(where: { $0.id == note.id }) else { return false }
        current[index] = note
        replaceQuickNotes(current)
        return true
    }

    func mergeQuickNotesByID(_ notes: [QuickNote]) {
        replaceQuickNotes(mergedProjectRecordElementsByID(quickNotes, with: notes))
    }

    @discardableResult
    func removeQuickNotes(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<QuickNote> {
        removeProjectRecordElements(
            from: quickNotes,
            ids: ids,
            id: \.id,
            replace: replaceQuickNotes,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
