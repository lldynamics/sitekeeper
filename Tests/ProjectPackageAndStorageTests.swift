import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectPackageAndStorageTests {
    @Test func packageSizeDecisionWarnsWithoutRejectingLargeExports() {
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: 0) == .normal)
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: ProjectDetailImportExportActions.largePackageWarningBytes) == .warn)
        #expect(ProjectDetailImportExportActions.packageSizeDecision(for: 10 * 1024 * 1024 * 1024) == .warn)
        #expect(StreamingZipArchiveWriter.requiresZip64ForTesting(
            entrySize: UInt64(UInt32.max) + 1,
            entryOffset: 0,
            entryCount: 1,
            centralSize: 128,
            centralOffset: 128
        ))
    }

    @Test func missingProjectPackageFilesReportsMissingAssets() {
        let projectId = UUID()
        let documents = [ProjectDocument(projectId: projectId, title: "发票", fileName: "missing-doc.pdf")]
        let drawings = [ProjectDrawing(projectId: projectId, name: "图纸A", fileName: "missing-drawing.pdf", fileType: "pdf")]
        let logs = [DailyLog(date: "2026-05-03", weather: "晴", content: "巡检", workers: "2", photos: [LogPhoto(fileName: "missing-photo.jpg", tag: .general)], projectId: projectId)]
        let quickNotes = [QuickNote(title: "补充资料", attachments: [QuickNoteAttachment(kind: .file, fileName: "missing-attachment.bin")])]

        let issues = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )

        #expect(issues.contains("资料 发票"))
        #expect(issues.contains("图纸 图纸A"))
        #expect(issues.contains("照片 2026-05-03 现场"))
        #expect(issues.contains(where: { $0.contains("随手记附件 补充资料") }))
    }

    @Test func photoStorageThrowsForInvalidImageData() {
        do {
            _ = try PhotoStorage.saveOrThrow(original: Data([0x00, 0x11]), fileName: "invalid-\(UUID().uuidString).jpg")
            Issue.record("无效图片数据不应保存成功")
        } catch let error as FileStorageError {
            #expect(error == .invalidImageData)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func photoStorageKeepsOriginalFileAndThumbnail() throws {
        let original = try Self.makeJPEGData()
        let fileName = "original-\(UUID().uuidString).jpg"
        let saved = try PhotoStorage.saveOrThrow(original: original, fileName: fileName)
        defer { PhotoStorage.delete(fileName: saved) }

        let stored = try Data(contentsOf: PhotoStorage.fileURL(for: saved))
        #expect(stored == original)
        #expect(PhotoStorage.fileSize(for: saved) == original.count)
        #expect(FileManager.default.fileExists(atPath: PhotoStorage.thumbnailURL(for: saved).path))
    }

    @Test func estimatedProjectPackageBytesUsesStoredFileSizes() throws {
        let projectId = UUID()
        let documentFile = try ProjectDocumentStorage.savePDFOrThrow(data: Data([0x01, 0x02, 0x03, 0x04]), projectId: projectId)
        let drawingSourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-\(UUID().uuidString).pdf")
        try Data([0x05, 0x06, 0x07]).write(to: drawingSourceURL, options: .atomic)
        let drawing = try DrawingStorage.saveImportedFileOrThrow(from: drawingSourceURL, projectId: projectId)
        let photoFile = try PhotoStorage.saveOrThrow(original: Self.makeJPEGData(), fileName: "photo-\(UUID().uuidString).jpg")
        let attachmentFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x08, 0x09, 0x0A, 0x0B, 0x0C]), fileName: "attachment-\(UUID().uuidString).bin")

        defer {
            ProjectDocumentStorage.delete(fileName: documentFile)
            DrawingStorage.delete(fileName: drawing.fileName)
            PhotoStorage.delete(fileName: photoFile)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFile)
            try? FileManager.default.removeItem(at: drawingSourceURL)
        }

        let documents = [ProjectDocument(projectId: projectId, title: "票据", fileName: documentFile)]
        let drawings = [drawing]
        let logs = [DailyLog(date: "2026-05-03", weather: "晴", content: "完成", workers: "1", photos: [LogPhoto(fileName: photoFile)], projectId: projectId)]
        let quickNotes = [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: attachmentFile)])]

        let estimated = ProjectDetailImportExportActions.estimatedProjectPackageBytes(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )
        let expected = ProjectDocumentStorage.fileSize(for: documentFile)
            + DrawingStorage.fileSize(for: drawing.fileName)
            + PhotoStorage.fileSize(for: photoFile)
            + QuickNoteAttachmentStorage.fileSize(for: attachmentFile)

        #expect(estimated == expected)
        #expect(estimated > 0)
    }

    @Test func warehouseMovementLinkedDocumentsAreBackwardCompatible() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "projectId": "00000000-0000-0000-0000-000000000002",
          "date": "2026-05-03",
          "movementType": "入库",
          "materialName": "电线",
          "specification": "BV 2.5",
          "unit": "卷",
          "quantity": "10",
          "counterparty": "供应商",
          "handler": "张三",
          "note": "旧数据",
          "createdAt": "2026-05-03 10:00"
        }
        """.data(using: .utf8)!

        let legacyMovement = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: legacyJSON)
        #expect(legacyMovement.linkedDocumentIds.isEmpty)

        var movement = legacyMovement
        let documentId = UUID()
        movement.linkedDocumentIds = [documentId]
        let data = try JSONEncoder().encode(movement)
        let restored = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: data)

        #expect(restored.linkedDocumentIds == [documentId])
    }

    @Test func warehouseAttachmentImportRejectsOversizedFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("warehouse-oversize-\(UUID().uuidString).bin")
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: Data([0x01]))
        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.truncate(atOffset: UInt64(ImportLimitPolicy.maxImportBytes + 1))
        try handle.close()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let movement = ProjectWarehouseMovement(
            projectId: UUID(),
            movementType: .inbound,
            materialName: "测试材料",
            unit: "个",
            quantity: "1"
        )
        let draft = ProjectWarehouseAttachmentDraft(fileURL: tempURL, title: "超大附件")

        let result = ProjectWarehouseAttachmentImporter.importAttachments(
            [draft],
            movement: movement,
            store: DataStore()
        )

        #expect(result.documents.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].contains("文件"))
        #expect(result.failures[0].contains("过大"))
    }

    private static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }
}
