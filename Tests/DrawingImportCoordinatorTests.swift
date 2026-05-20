import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DrawingImportCoordinatorTests {
    @Test func unsupportedSingleFileReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-drawing-\(UUID().uuidString).txt")
        try Data("not a drawing".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [fileURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.unsupported"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == fileURL.lastPathComponent)
        #expect(result.operationMessage.contains(fileURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }

    @Test func zipWithoutDrawingEntriesReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "drawing-empty-zip")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: "notes/readme.txt", data: Data("no drawings".utf8))
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [finishedURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.emptyZip"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == finishedURL.lastPathComponent)
        #expect(result.failures.first?.reason.contains("ZIP") == true)
        #expect(result.operationMessage.contains(finishedURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }
}
