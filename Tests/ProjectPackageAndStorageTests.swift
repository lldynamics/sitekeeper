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

    @Test func drawingStorageCopiesLibreDWGSidecarWithImportedDWG() throws {
        let projectId = UUID()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwg-sidecar-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceDWGURL = folder.appendingPathComponent("original.dwg")
        let sourceSidecarURL = sourceDWGURL.appendingPathExtension("sitekeeper-cad.json")
        let sidecarData = Data("""
        {
          "schema": "sitekeeper-cad-worker-v1",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 1, "maxY": 1 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "entities": []
        }
        """.utf8)
        try Data("AC1032 source dwg".utf8).write(to: sourceDWGURL, options: .atomic)
        try sidecarData.write(to: sourceSidecarURL, options: .atomic)

        let drawing = try DrawingStorage.saveImportedFileOrThrow(from: sourceDWGURL, projectId: projectId)
        let storedSidecarURL = DrawingStorage.sidecarURL(for: drawing.fileName)
        defer {
            if DrawingStorage.exists(fileName: drawing.fileName) {
                DrawingStorage.delete(fileName: drawing.fileName)
            }
        }

        #expect(FileManager.default.fileExists(atPath: storedSidecarURL.path))
        #expect(try Data(contentsOf: storedSidecarURL) == sidecarData)
        #expect(DrawingStorage.referencedFileNames(for: [drawing]).contains(DrawingStorage.sidecarFileName(for: drawing.fileName)))
        #expect(DrawingStorage.orphanFileNames(for: [drawing]).contains(DrawingStorage.sidecarFileName(for: drawing.fileName)) == false)
        #expect(DrawingStorage.backupFiles(for: [drawing]).contains { $0.fileName == DrawingStorage.sidecarFileName(for: drawing.fileName) })

        DrawingStorage.delete(fileName: drawing.fileName)
        #expect(FileManager.default.fileExists(atPath: storedSidecarURL.path) == false)
    }

    @Test func remoteLibreDWGConversionAdapterCachesReturnedCADDatabase() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwg-remote-conversion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("remote-source.dwg")
        try Data("AC1032 remote dwg".utf8).write(to: dwgURL, options: .atomic)
        let sidecarURL = dwgURL.appendingPathExtension("sitekeeper-cad.json")

        let responseJSON = Data("""
        {
          "schema": "sitekeeper-cad-worker-v1",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "textStyles": [{ "id": "standard", "name": "Standard" }],
          "blocks": [],
          "entities": [
            {
              "id": "remote-line-1",
              "type": "line",
              "layerID": "0",
              "start": { "x": 0, "y": 0 },
              "end": { "x": 10, "y": 0 },
              "bounds": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 }
            }
          ]
        }
        """.utf8)

        CADRemoteDWGConversionMockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/convert/dwg")
            #expect(request.value(forHTTPHeaderField: "X-SiteKeeper-File-Name") == "remote-source.dwg")
            guard let requestURL = request.url else {
                throw CADRemoteDWGConversionError.invalidResponse
            }
            guard let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                throw CADRemoteDWGConversionError.invalidResponse
            }
            return (response, responseJSON)
        }
        defer { CADRemoteDWGConversionMockURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CADRemoteDWGConversionMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let adapter = CADRemoteDWGConversionAdapter(
            endpointProvider: { URL(string: "https://cad.example.test") },
            session: session
        )

        let file = SiteKeeperCADKernel.CADFile(url: dwgURL, displayName: "remote-source.dwg", format: .dwg)
        #expect(adapter.canImportDWG(file: file))

        let drawing = try await adapter.importDWG(file: file)
        #expect(drawing.entities.count == 1)
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))

        let engineDatabase = try await SiteKeeperCADKernel.DWGImportEngine(geometryAdapter: adapter)
            .importDrawing(file: file)
        #expect(engineDatabase.importSource == adapter.id)
        #expect(engineDatabase.drawableEntityCount == 1)

        let database = try await SiteKeeperCADKernel.IntermediateJSONImportEngine().importDrawing(
            file: SiteKeeperCADKernel.CADFile(
                url: sidecarURL,
                displayName: sidecarURL.lastPathComponent,
                format: .intermediateJSON
            )
        )
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount == 1)
    }

    @Test func cadRemoteConversionEndpointAcceptsHostWithoutScheme() {
        let endpoint = CADRemoteDWGConversionSettings.endpointURL(from: "127.0.0.1:8765")
        #expect(endpoint?.scheme == "http")
        #expect(endpoint?.host == "127.0.0.1")
        #expect(endpoint?.port == 8765)
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

final class CADRemoteDWGConversionMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "cad.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: CADRemoteDWGConversionError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
