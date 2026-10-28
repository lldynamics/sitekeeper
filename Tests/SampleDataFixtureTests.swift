import Testing
import Foundation
import UIKit
import PDFKit
@testable import sitekeeper

@MainActor
struct SampleDataFixtureTests {
    @Test func syntheticFixtureIsDeterministicAndRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(SyntheticSampleFixtureBuilder.makeSnapshot())
        let second = try encoder.encode(SyntheticSampleFixtureBuilder.makeSnapshot())
        #expect(first == second)
        let decoded = try JSONDecoder().decode(BackupSnapshot.self, from: first)
        #expect(try encoder.encode(decoded) == first)
        #expect(decoded.projects.allSatisfy { $0.customerPhone.hasPrefix("NON-DIALABLE-") })
        #expect(decoded.projectContacts.allSatisfy { $0.phone.hasPrefix("NON-DIALABLE-") })
    }

    @Test func sampleFixtureDecodesAndKeepsBinaryAssetsInSync() throws {
        let store = makeStore()
        let snapshot = try #require(store.loadSampleFixtureSnapshot())

        #expect(snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(snapshot.projects.count >= 5)
        #expect(snapshot.materialItems.count >= 10)
        #expect(snapshot.quoteItems.count >= 8)
        #expect(snapshot.dailyLogs.count >= 8)
        #expect(snapshot.siteTodos.count >= 8)
        #expect(snapshot.quickNotes.count >= 8)
        #expect(snapshot.projectDrawings.count >= 3)
        #expect(snapshot.projectDocuments.count >= 5)
        #expect(snapshot.projectContacts.count >= 8)
        #expect(snapshot.projectFinancialRecords.count >= 8)
        #expect(snapshot.materialSheetDrafts.count >= 4)
        #expect(snapshot.photoFiles.count >= 4)
        #expect(snapshot.quickNoteAttachmentFiles.count >= 3)

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
        #expect(snapshot.photoFiles.allSatisfy { UIImage(data: $0.data) != nil })
        #expect(snapshot.quickNoteAttachmentFiles.allSatisfy { UIImage(data: $0.data) != nil })
        #expect(snapshot.drawingFiles.count == 3)
        #expect(snapshot.documentFiles.count == 5)
        #expect(snapshot.drawingFiles.allSatisfy { PDFDocument(data: $0.data)?.pageCount == 1 })
        #expect(snapshot.documentFiles.allSatisfy { PDFDocument(data: $0.data)?.pageCount == 1 })

        let projectIDs = Set(snapshot.projects.map(\.id))
        #expect(projectIDs.count == snapshot.projects.count)
        let projectReferences = snapshot.materialItems.compactMap(\.projectId)
            + snapshot.quoteItems.compactMap(\.projectId) + snapshot.laborRecords.compactMap(\.projectId)
            + snapshot.dailyLogs.compactMap(\.projectId) + snapshot.siteTodos.compactMap(\.projectId)
            + snapshot.quickNotes.compactMap(\.projectId) + snapshot.materialSheetDrafts.compactMap(\.projectId)
            + snapshot.projectDrawings.map(\.projectId) + snapshot.projectDocuments.map(\.projectId)
            + snapshot.projectFinancialRecords.map(\.projectId) + snapshot.projectContacts.map(\.projectId)
            + snapshot.progressTasks.map(\.projectId) + snapshot.projectWarehouseMovements.map(\.projectId)
        #expect(projectReferences.allSatisfy { projectIDs.contains($0) })
        #expect(drawingFileNames.count == snapshot.drawingFiles.count)
        #expect(documentFileNames.count == snapshot.documentFiles.count)
        #expect(attachmentFileNames.count == snapshot.quickNoteAttachmentFiles.count)
        #expect(photoFileNames.count == snapshot.photoFiles.count)
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
