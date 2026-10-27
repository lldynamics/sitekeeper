import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DrawingIssueSaveTests {
    @Test func failedWriteRollsBackIssueAndLinkThenRetryPersistsBoth() async throws {
        enum Failure: Error { case injected }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let project = Project(name: "Issue save", location: "")
        store.appendProject(project)
        let drawing = ProjectDrawing(projectId: project.id, name: "Drawing", fileName: "drawing.pdf", fileType: "pdf")
        store.appendProjectDrawing(drawing)
        try await store.flushSaveOrThrow()
        let todo = SiteTodo(title: "Inspection", drawingIssueLayerOrPage: "Page 2", projectId: project.id)
        do {
            try await DrawingIssueSaveService.save(todo, drawing: drawing, store: store, persist: {
                store.appendSiteTodo(SiteTodo(title: "Unrelated change"))
                throw Failure.injected
            })
            Issue.record("Expected injected persistence failure")
        } catch Failure.injected {}
        #expect(!store.siteTodos.contains { $0.id == todo.id })
        #expect(store.siteTodos.contains { $0.title == "Unrelated change" })
        #expect(store.projectDrawings.first?.linkedTodoIDs.isEmpty == true)
        try await DrawingIssueSaveService.save(todo, drawing: drawing, store: store)
        let reopened = DataStore(storageDirectory: root)
        await reopened.awaitInitialLoad()
        #expect(reopened.siteTodos.filter { $0.id == todo.id }.count == 1)
        #expect(reopened.projectDrawings.first?.linkedTodoIDs == [todo.id])
        #expect(reopened.siteTodos.first { $0.id == todo.id }?.drawingIssueLayerOrPage == "Page 2")
        await #expect(throws: DataStore.PersistenceBlockedError.self) {
            try await DrawingIssueSaveService.save(todo, drawing: drawing, store: store)
        }
        #expect(store.siteTodos.filter { $0.id == todo.id }.count == 1)
    }

    @Test func deletedDrawingCannotReceiveAnOrphanIssue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let project = Project(name: "Deleted drawing", location: "Test")
        store.appendProject(project)
        let drawing = ProjectDrawing(projectId: project.id, name: "Deleted", fileName: "gone.pdf", fileType: "pdf")
        let todo = SiteTodo(title: "Issue", projectId: project.id)
        await #expect(throws: DataStore.PersistenceBlockedError.self) {
            try await DrawingIssueSaveService.save(todo, drawing: drawing, store: store)
        }
        #expect(store.siteTodos.isEmpty)
    }
}
