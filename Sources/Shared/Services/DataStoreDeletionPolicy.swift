import Foundation

struct DataStoreDeletionAuditContext {
    let summary: String
    var detail: String = ""
    var source: String = ""

    func record(outcome: OperationAuditEntry.Outcome) {
        OperationAuditLog.record(
            action: .delete,
            outcome: outcome,
            summary: summary,
            detail: detail,
            source: source
        )
    }
}

struct DataStoreDeferredFileCleanup {
    let summary: String
    let fileCount: Int
    let perform: () -> Void
}

struct DataStoreRemovalResult<Element> {
    let snapshot: [Element]
    let removed: [Element]
    var audit: DataStoreDeletionAuditContext?
    var deferredFileCleanup: DataStoreDeferredFileCleanup?

    var isEmpty: Bool { removed.isEmpty }
    var deletedCount: Int { removed.count }

    func removedIDs<ID: Hashable>(_ id: (Element) -> ID) -> Set<ID> {
        Set(removed.map(id))
    }

    func restoredItems<ID: Hashable>(
        current: [Element],
        id: (Element) -> ID
    ) -> [Element] {
        let snapshotIDs = Set(snapshot.map(id))
        let deletedIDs = removedIDs(id)
        var currentByID = Dictionary(uniqueKeysWithValues: current.map { (id($0), $0) })

        for item in snapshot where deletedIDs.contains(id(item)) {
            currentByID[id(item)] = item
        }

        let newItems = current.filter { !snapshotIDs.contains(id($0)) }
        let restoredSnapshotItems = snapshot.compactMap { currentByID[id($0)] }
        return newItems + restoredSnapshotItems
    }

    func performDeferredFileCleanup() {
        deferredFileCleanup?.perform()
    }

    func recordAuditStarted() {
        audit?.record(outcome: .started)
    }

    func recordAuditSucceeded() {
        audit?.record(outcome: .succeeded)
    }

    func recordAuditCancelled() {
        audit?.record(outcome: .cancelled)
    }
}
