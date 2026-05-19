import Foundation
import UniformTypeIdentifiers

struct DrawingBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum DrawingStorage {
    private static let fileFamily = DocumentStorageFileFamily(
        directoryName: "Drawings",
        eventPrefix: "drawing"
    )

    private static var drawingDir: URL {
        fileFamily.directoryURL
    }

    static func saveImportedFile(from sourceURL: URL, projectId: UUID) -> ProjectDrawing? {
        // 兼容旧调用：新导入流程应优先使用 `saveImportedFileOrThrow`。
        do {
            return try saveImportedFileOrThrow(from: sourceURL, projectId: projectId)
        } catch {
            DocumentStorageIssueLogger.record("drawing.import_failed", fileName: sourceURL.lastPathComponent, error: error)
            return nil
        }
    }

    static func saveImportedFileOrThrow(from sourceURL: URL, projectId: UUID) throws -> ProjectDrawing {
        guard let ext = drawingFileExtension(for: sourceURL) else {
            let rawType = sourceURL.pathExtension.lowercased()
            throw FileStorageError.unsupportedFileType(rawType.isEmpty ? String(localized: "未知类型") : rawType)
        }
        guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
            throw FileStorageError.unsupportedFileType(ext)
        }
        let baseName = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = baseName.isEmpty ? "图纸" : baseName
        let storedFileName = "\(UUID().uuidString).\(ext)"
        let targetURL = drawingDir.appendingPathComponent(storedFileName)
        try ensureDirectoryExists()

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            try copyDWGSidecarIfAvailable(from: sourceURL, toDrawingURL: targetURL)
        } catch {
            throw FileStorageError.copyFailed(sourceURL.lastPathComponent)
        }

        return makeDrawing(
            projectId: projectId,
            displayName: displayName,
            storedFileName: storedFileName,
            fileType: ext
        )
    }

    static func saveImportedDataOrThrow(data: Data, sourceFileName: String, projectId: UUID) throws -> ProjectDrawing {
        let ext = (sourceFileName as NSString).pathExtension.lowercased()
        guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
            throw FileStorageError.unsupportedFileType(ext.isEmpty ? String(localized: "未知类型") : ext)
        }
        let rawBaseName = ((sourceFileName as NSString).lastPathComponent as NSString).deletingPathExtension
        let displayName = rawBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "图纸"
            : rawBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedFileName = "\(UUID().uuidString).\(ext)"
        let targetURL = drawingDir.appendingPathComponent(storedFileName)
        try ensureDirectoryExists()
        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(sourceFileName)
        }
        return makeDrawing(
            projectId: projectId,
            displayName: displayName,
            storedFileName: storedFileName,
            fileType: ext
        )
    }

    private static func drawingFileExtension(for sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ProjectDrawing.allowedFileExtensions.contains(ext) {
            return ext
        }

        if let contentType = contentTypeFromResourceValues(for: sourceURL) {
            if contentType.conforms(to: .pdf) {
                return "pdf"
            }
            if let preferred = contentType.preferredFilenameExtension?.lowercased(),
               ProjectDrawing.allowedFileExtensions.contains(preferred) {
                return preferred
            }
        }

        // 某些文件提供器会返回无后缀 URL，fallback 到文件名推断。
        let lowerName = sourceURL.lastPathComponent.lowercased()
        if lowerName.hasSuffix(".dwg") { return "dwg" }
        if lowerName.hasSuffix(".dxf") { return "dxf" }
        if lowerName.hasSuffix(".pdf") { return "pdf" }
        return nil
    }

    private static func contentTypeFromResourceValues(for sourceURL: URL) -> UTType? {
        do {
            return try sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        } catch {
            DocumentStorageIssueLogger.record("drawing.content_type_read_failed", fileName: sourceURL.lastPathComponent, error: error)
            return nil
        }
    }

    private static func makeDrawing(
        projectId: UUID,
        displayName: String,
        storedFileName: String,
        fileType: String
    ) -> ProjectDrawing {
        ProjectDrawing(
            projectId: projectId,
            name: displayName,
            fileName: storedFileName,
            fileType: fileType,
            importedAt: Formatters.now()
        )
    }

    static func fileURL(for fileName: String) -> URL {
        fileFamily.fileURL(for: fileName)
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("drawing.delete_failed", fileName: fileName, error: error)
        }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        try fileFamily.deleteOrThrow(
            fileName: fileName,
            quarantineCategory: .drawing,
            event: "drawing.delete",
            source: "DrawingStorage.deleteOrThrow"
        )
        quarantineSidecars(for: fileName)
    }

    static func data(for fileName: String) -> Data? {
        fileFamily.data(for: fileName, failureEvent: "drawing.read_failed")
    }

    static func dataAsync(for fileName: String) async -> Data? {
        await fileFamily.dataAsync(for: fileName, failureEvent: "drawing.read_failed")
    }

    static func exists(fileName: String) -> Bool {
        fileFamily.exists(fileName: fileName)
    }

    static func fileSize(for fileName: String) -> Int {
        fileFamily.fileSize(for: fileName, failureEvent: "drawing.file_size_failed")
    }

    static func backupFiles(for drawings: [ProjectDrawing]) -> [DrawingBackupFile] {
        var seen = Set<String>()
        var files: [DrawingBackupFile] = []
        for drawing in drawings {
            for fileName in [drawing.fileName] + sidecarFileNames(for: drawing.fileName) {
                guard !seen.contains(fileName), let data = data(for: fileName) else { continue }
                seen.insert(fileName)
                files.append(DrawingBackupFile(fileName: fileName, data: data))
            }
        }
        return files
    }

    static func allStoredFileNames() -> [String] {
        fileFamily.allStoredFileNames(failureEvent: "drawing.directory_list_failed")
    }

    static func referencedFileNames(for drawings: [ProjectDrawing]) -> Set<String> {
        Set(drawings.flatMap { drawing in
            [drawing.fileName] + sidecarFileNames(for: drawing.fileName)
        })
    }

    static func orphanFileNames(for drawings: [ProjectDrawing]) -> [String] {
        let referenced = referencedFileNames(for: drawings)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [DrawingBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            DocumentStorageIssueLogger.record("drawing.restore_failed", error: error)
        }
    }

    static func restoreOrThrow(_ files: [DrawingBackupFile]) throws {
        try fileFamily.restoreOrThrow(files.map { ($0.fileName, $0.data) })
    }

    static func sidecarFileName(for fileName: String) -> String {
        "\(fileName).sitekeeper-cad.json"
    }

    static func sidecarFileNames(for fileName: String) -> [String] {
        let canonical = sidecarFileName(for: fileName)
        let baseName = (fileName as NSString).deletingPathExtension
        let legacy = "\(baseName).sitekeeper-cad.json"
        return canonical == legacy ? [canonical] : [canonical, legacy]
    }

    static func sidecarURL(for fileName: String) -> URL {
        fileURL(for: sidecarFileName(for: fileName))
    }

    private static func copyDWGSidecarIfAvailable(from sourceURL: URL, toDrawingURL targetURL: URL) throws {
        guard targetURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dwg" else {
            return
        }
        guard let sourceSidecarURL = dwgSidecarCandidates(for: sourceURL).first(where: { candidate in
            FileManager.default.fileExists(atPath: candidate.path)
        }) else {
            return
        }

        let targetSidecarURL = targetURL.appendingPathExtension("sitekeeper-cad.json")
        try FileOps.replaceByCopyWithRollback(
            from: sourceSidecarURL,
            to: targetSidecarURL,
            context: .init(
                event: "drawing.sidecar_replace",
                category: .fileStorage,
                source: "DrawingStorage.copyDWGSidecarIfAvailable"
            )
        )
    }

    private static func dwgSidecarCandidates(for sourceURL: URL) -> [URL] {
        [
            sourceURL.appendingPathExtension("sitekeeper-cad.json"),
            sourceURL.deletingPathExtension()
                .appendingPathExtension("sitekeeper-cad.json"),
            sourceURL.appendingPathExtension("sitekeeper-cad")
                .appendingPathComponent("drawing.sitekeeper-cad.json"),
            sourceURL.deletingPathExtension()
                .appendingPathExtension("sitekeeper-cad")
                .appendingPathComponent("drawing.sitekeeper-cad.json"),
            sourceURL.deletingLastPathComponent()
                .appendingPathComponent("drawing.sitekeeper-cad.json")
        ]
    }

    private static func quarantineSidecars(for fileName: String) {
        for sidecar in sidecarFileNames(for: fileName) {
            let url = fileURL(for: sidecar)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                _ = try FileQuarantineStore.quarantine(
                    fileAt: url,
                    category: .drawingSidecar,
                    originalFileName: sidecar
                )
            } catch {
                DocumentStorageIssueLogger.record("drawing.sidecar_quarantine_failed", fileName: sidecar, error: error)
            }
        }
    }

    private static func ensureDirectoryExists() throws {
        try fileFamily.ensureDirectoryExists()
    }
}
