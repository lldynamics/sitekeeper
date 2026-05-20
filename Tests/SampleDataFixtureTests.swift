import Testing
import Foundation
import UIKit
@testable import sitekeeper

@MainActor
struct SampleDataFixtureTests {
    @Test func sampleFixtureDecodesAndKeepsBinaryAssetsInSync() throws {
        let store = makeStore()
        let snapshot = try #require(store.loadSampleFixtureSnapshot())

        #expect(snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(snapshot.projects.count >= 3)
        #expect(snapshot.materialItems.count >= 5)
        #expect(snapshot.quoteItems.count >= 4)
        #expect(snapshot.dailyLogs.count >= 4)
        #expect(snapshot.siteTodos.count >= 4)
        #expect(snapshot.quickNotes.count >= 4)
        #expect(snapshot.projectDrawings.count >= 1)
        #expect(snapshot.projectDocuments.count >= 2)

        let drawingFileNames = Set(snapshot.drawingFiles.map(\.fileName))
        let documentFileNames = Set(snapshot.documentFiles.map(\.fileName))
        let attachmentFileNames = Set(snapshot.quickNoteAttachmentFiles.map(\.fileName))
        let photoFileNames = Set(snapshot.photoFiles.map(\.fileName))

        #expect(snapshot.projectDrawings.allSatisfy { drawingFileNames.contains($0.fileName) })
        #expect(snapshot.projectDocuments.allSatisfy { documentFileNames.contains($0.fileName) })
        #expect(snapshot.quickNotes.flatMap(\.attachments).allSatisfy { attachmentFileNames.contains($0.fileName) })
        #expect(snapshot.dailyLogs.flatMap(\.allPhotoFileNames).allSatisfy { photoFileNames.contains($0) })

        let samplePhoto = try #require(snapshot.photoFiles.first)
        #expect(UIImage(data: samplePhoto.data) != nil)
    }

    private func makeStore() -> DataStore {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleDataFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        store.clearAllBusinessData(deleteStoredFiles: false)
        return store
    }
}
