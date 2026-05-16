import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DataStoreDeletionPolicyTests {
    @Test func throwingCleanupDeletesPhotoDrawingAndDocumentFiles() throws {
        let projectId = UUID()
        let photoFileName = "policy-photo-\(UUID().uuidString).png"

        guard let photoData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a7YAAAAASUVORK5CYII=") else {
            throw NSError(domain: "DataStoreDeletionPolicyTests", code: 1)
        }

        _ = try PhotoStorage.saveOrThrow(original: photoData, fileName: photoFileName)
        let drawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x11, 0x22, 0x33]),
            sourceFileName: "policy-test.dwg",
            projectId: projectId
        )
        let documentFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data([0x44, 0x55]),
            projectId: projectId,
            fileExtension: "txt"
        )

        defer {
            if PhotoStorage.exists(fileName: photoFileName) {
                PhotoStorage.delete(fileName: photoFileName)
            }
            if DrawingStorage.exists(fileName: drawing.fileName) {
                DrawingStorage.delete(fileName: drawing.fileName)
            }
            if ProjectDocumentStorage.exists(fileName: documentFileName) {
                ProjectDocumentStorage.delete(fileName: documentFileName)
            }
        }

        #expect(PhotoStorage.exists(fileName: photoFileName))
        #expect(DrawingStorage.exists(fileName: drawing.fileName))
        #expect(ProjectDocumentStorage.exists(fileName: documentFileName))

        try DataStoreDeferredFileCleanup.deletePhotoFilesOrThrow(
            [photoFileName],
            summary: "dataStoreDeletionPolicyTests.photo"
        )
        try DataStoreDeferredFileCleanup.deleteDrawingFilesOrThrow(
            [drawing.fileName],
            summary: "dataStoreDeletionPolicyTests.drawing"
        )
        try DataStoreDeferredFileCleanup.deleteProjectDocumentFilesOrThrow(
            [documentFileName],
            summary: "dataStoreDeletionPolicyTests.document"
        )

        #expect(!PhotoStorage.exists(fileName: photoFileName))
        #expect(!DrawingStorage.exists(fileName: drawing.fileName))
        #expect(!ProjectDocumentStorage.exists(fileName: documentFileName))
    }
}
