import Foundation
import SwiftUI
import Testing
@testable import sitekeeper

@MainActor
struct UndoableDeletionCoordinatorTests {
    private struct Item: Identifiable, Equatable {
        let id: UUID
        var name: String
    }

    @Test func restoringItemsKeepsNewItemsAndCurrentEdits() {
        let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
        let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000000")!
        let thirdID = UUID(uuidString: "30000000-0000-0000-0000-000000000000")!
        let newID = UUID(uuidString: "40000000-0000-0000-0000-000000000000")!
        let snapshot = [
            Item(id: firstID, name: "first"),
            Item(id: secondID, name: "second"),
            Item(id: thirdID, name: "third")
        ]
        let current = [
            Item(id: newID, name: "new"),
            Item(id: firstID, name: "first-edited"),
            Item(id: thirdID, name: "third")
        ]

        let restored = UndoableDeletionCoordinator.restoringItems(
            snapshot: snapshot,
            current: current,
            deletedIDs: Set([secondID])
        )

        #expect(restored.map(\.id) == [newID, firstID, secondID, thirdID])
        #expect(restored.first { $0.id == firstID }?.name == "first-edited")
        #expect(restored.first { $0.id == secondID }?.name == "second")
    }

    @Test func restoringItemsDoesNotResurrectItemsDeletedElsewhere() {
        let firstID = UUID(uuidString: "50000000-0000-0000-0000-000000000000")!
        let secondID = UUID(uuidString: "60000000-0000-0000-0000-000000000000")!
        let snapshot = [
            Item(id: firstID, name: "first"),
            Item(id: secondID, name: "second")
        ]
        let current: [Item] = []

        let restored = UndoableDeletionCoordinator.restoringItems(
            snapshot: snapshot,
            current: current,
            deletedIDs: Set([secondID])
        )

        #expect(restored.map(\.id) == [secondID])
    }

    @Test func queueRecordsAuditStartedAndSucceededWhenCommitted() {
        OperationAuditLog.clear()
        defer { OperationAuditLog.clear() }

        var notice: OperationToastNotice?
        var didCommit = false
        let coordinator = UndoableDeletionCoordinator(delay: .seconds(30))
        coordinator.queue(
            notice: Binding(
                get: { notice },
                set: { notice = $0 }
            ),
            message: "deleted",
            commit: {
                didCommit = true
            },
            undo: {},
            audit: UndoableDeletionAuditContext(
                summary: "audit success test",
                detail: "one item",
                source: "UndoableDeletionCoordinatorTests"
            )
        )

        #expect(OperationAuditLog.entries().first?.outcome == .started)
        coordinator.flushPendingCommit()

        let entries = OperationAuditLog.entries()
        #expect(didCommit)
        #expect(entries.contains { $0.summary == "audit success test" && $0.outcome == .succeeded })
    }

    @Test func queueRecordsAuditCancelledWhenUndone() {
        OperationAuditLog.clear()
        defer { OperationAuditLog.clear() }

        var notice: OperationToastNotice?
        var didCommit = false
        var didUndo = false
        let coordinator = UndoableDeletionCoordinator(delay: .seconds(30))
        coordinator.queue(
            notice: Binding(
                get: { notice },
                set: { notice = $0 }
            ),
            message: "deleted",
            commit: {
                didCommit = true
            },
            undo: {
                didUndo = true
            },
            audit: UndoableDeletionAuditContext(
                summary: "audit cancel test",
                detail: "one item",
                source: "UndoableDeletionCoordinatorTests"
            )
        )

        notice?.action?()

        let entries = OperationAuditLog.entries()
        #expect(didUndo)
        #expect(!didCommit)
        #expect(entries.contains { $0.summary == "audit cancel test" && $0.outcome == .cancelled })
    }
}
