import AVFoundation
import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers

private enum DocumentStorageIssueLogger {
    static func record(
        _ event: String,
        fileName: String? = nil,
        error: Error? = nil,
        details: [String: String] = [:]
    ) {
        var payload = details
        if let fileName, !fileName.isEmpty {
            payload["file"] = fileName
        }
        StorageIssueLog.recordEvent(
            event,
            category: .fileStorage,
            details: payload,
            error: error
        )
    }
}

struct ProjectDocumentBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum ProjectDocumentStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        DocumentStorageIssueLogger.record(
            "project_document.base_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }

    private static var documentDir: URL {
        baseDirectory.appendingPathComponent("ProjectDocuments")
    }

    static func savePDF(data: Data, projectId: UUID) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `savePDFOrThrow`。
        do {
            return try savePDFOrThrow(data: data, projectId: projectId)
        } catch {
            DocumentStorageIssueLogger.record("project_document.save_failed", error: error)
            return nil
        }
    }

    static func savePDFOrThrow(data: Data, projectId: UUID) throws -> String {
        return try saveDataOrThrow(data: data, projectId: projectId, fileExtension: "pdf")
    }

    static func saveDataOrThrow(data: Data, projectId: UUID, fileExtension ext: String) throws -> String {
        let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName = "\(projectId.uuidString)-\(UUID().uuidString).\(normalizedExt.isEmpty ? "dat" : normalizedExt)"
        try ensureDirectoryExists()
        do {
            try data.write(to: fileURL(for: fileName), options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(fileName)
        }
        return fileName
    }

    static func saveImportedFileOrThrow(from sourceURL: URL, projectId: UUID, fileExtension ext: String) throws -> String {
        let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName = "\(projectId.uuidString)-\(UUID().uuidString).\(normalizedExt.isEmpty ? "dat" : normalizedExt)"
        try ensureDirectoryExists()
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL(for: fileName))
        } catch {
            throw FileStorageError.copyFailed(sourceURL.lastPathComponent)
        }
        return fileName
    }

    static func fileURL(for fileName: String) -> URL {
        documentDir.appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            DocumentStorageIssueLogger.record("project_document.read_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogEvent: nil,
            failureLogEvent: "project_document.read_failed",
            fileName: fileName
        )
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("project_document.delete_failed", fileName: fileName, error: error)
        }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
        } catch {
            throw FileStorageError.deleteFailed(fileName)
        }
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func fileSize(for fileName: String) -> Int {
        let url = fileURL(for: fileName)
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            DocumentStorageIssueLogger.record("project_document.file_size_failed", fileName: fileName, error: error)
            return 0
        }
    }

    static func backupFiles(for documents: [ProjectDocument]) -> [ProjectDocumentBackupFile] {
        var seen = Set<String>()
        return documents.compactMap { document in
            guard !seen.contains(document.fileName), let data = data(for: document.fileName) else { return nil }
            seen.insert(document.fileName)
            return ProjectDocumentBackupFile(fileName: document.fileName, data: data)
        }
    }

    static func allStoredFileNames() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            DocumentStorageIssueLogger.record("project_document.directory_list_failed", error: error)
            return []
        }
    }

    static func referencedFileNames(for documents: [ProjectDocument]) -> Set<String> {
        Set(documents.map(\.fileName))
    }

    static func orphanFileNames(for documents: [ProjectDocument]) -> [String] {
        let referenced = referencedFileNames(for: documents)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [ProjectDocumentBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            DocumentStorageIssueLogger.record("project_document.restore_failed", error: error)
        }
    }

    static func restoreOrThrow(_ files: [ProjectDocumentBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: documentDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("ProjectDocuments")
        }
    }
}

struct DrawingBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum DrawingStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        DocumentStorageIssueLogger.record(
            "drawing.base_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }

    private static var drawingDir: URL {
        baseDirectory.appendingPathComponent("Drawings")
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
        drawingDir.appendingPathComponent(fileName)
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
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
            deleteSidecars(for: fileName)
        } catch {
            throw FileStorageError.deleteFailed(fileName)
        }
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            DocumentStorageIssueLogger.record("drawing.read_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogEvent: nil,
            failureLogEvent: "drawing.read_failed",
            fileName: fileName
        )
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func fileSize(for fileName: String) -> Int {
        let url = fileURL(for: fileName)
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            DocumentStorageIssueLogger.record("drawing.file_size_failed", fileName: fileName, error: error)
            return 0
        }
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
        do {
            let files = try FileManager.default.contentsOfDirectory(at: drawingDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            DocumentStorageIssueLogger.record("drawing.directory_list_failed", error: error)
            return []
        }
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
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
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
        if FileManager.default.fileExists(atPath: targetSidecarURL.path) {
            try FileManager.default.removeItem(at: targetSidecarURL)
        }
        try FileManager.default.copyItem(at: sourceSidecarURL, to: targetSidecarURL)
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

    private static func deleteSidecars(for fileName: String) {
        for sidecar in sidecarFileNames(for: fileName) {
            let url = fileURL(for: sidecar)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                DocumentStorageIssueLogger.record("drawing.sidecar_delete_failed", fileName: sidecar, error: error)
            }
        }
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: drawingDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("Drawings")
        }
    }
}

struct QuickNoteAttachmentBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum QuickNoteAttachmentStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        DocumentStorageIssueLogger.record(
            "quick_note_attachment.base_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }

    private static var attachmentDir: URL {
        baseDirectory.appendingPathComponent("QuickNoteAttachments")
    }

    static func makeFileName(extension ext: String) -> String {
        "quick-note-\(UUID().uuidString).\(ext)"
    }

    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.78) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `saveImageOrThrow`。
        do {
            return try saveImageOrThrow(image, compressionQuality: compressionQuality)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.image_save_failed", error: error)
            return nil
        }
    }

    static func saveImageOrThrow(_ image: UIImage, compressionQuality: CGFloat = 0.78) throws -> String {
        let resized = image.resizedForQuickNote(longEdge: 1800)
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else {
            throw FileStorageError.imageEncodingFailed
        }
        return try saveDataOrThrow(data, fileName: makeFileName(extension: "jpg"))
    }

    static func saveData(_ data: Data, extension ext: String) -> String? {
        saveData(data, fileName: makeFileName(extension: ext))
    }

    static func saveData(_ data: Data, fileName: String) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `saveDataOrThrow`。
        do {
            return try saveDataOrThrow(data, fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.save_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func saveDataOrThrow(_ data: Data, fileName: String) throws -> String {
        do {
            try ensureDirectoryExists()
            try data.write(to: fileURL(for: fileName), options: .atomic)
            return fileName
        } catch {
            throw FileStorageError.writeFailed(fileName)
        }
    }

    static func importFileOrThrow(from source: URL) throws -> QuickNoteAttachment {
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        return QuickNoteAttachment(kind: .file, fileName: fileName, originalName: source.lastPathComponent)
    }

    static func importVideoOrThrow(from source: URL) async throws -> (fileName: String, originalName: String, byteSize: Int, durationSeconds: Double?) {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        let byteSize = fileSize(for: fileName)
        let durationSeconds: Double? = await {
            let asset = AVURLAsset(url: target)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return nil }
                return seconds
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.video_duration_failed", fileName: source.lastPathComponent, error: error)
                return nil
            }
        }()
        return (fileName, source.lastPathComponent, byteSize, durationSeconds)
    }

    static func fileURL(for fileName: String) -> URL {
        attachmentDir.appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.read_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogEvent: nil,
            failureLogEvent: "quick_note_attachment.read_failed",
            fileName: fileName
        )
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func fileSize(for fileName: String) -> Int {
        fileSize(at: fileURL(for: fileName))
    }

    static func fileSize(at url: URL) -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.file_size_failed", fileName: url.lastPathComponent, error: error)
            return 0
        }
    }

    static func formattedFileSize(for fileName: String) -> String? {
        let size = fileSize(for: fileName)
        guard size > 0 else { return nil }
        return formattedFileSize(size)
    }

    static func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.delete_failed", fileName: fileName, error: error)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
        } catch {
            throw FileStorageError.deleteFailed(fileName)
        }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func delete(attachments: [QuickNoteAttachment]) {
        for attachment in attachments {
            delete(fileName: attachment.fileName)
        }
    }

    static func backupFiles(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> [QuickNoteAttachmentBackupFile] {
        var seen = Set<String>()
        let allAttachments = notes.flatMap(\.attachments) + extraAttachments
        return allAttachments.compactMap { attachment in
            guard !seen.contains(attachment.fileName),
                  let data = data(for: attachment.fileName) else { return nil }
            seen.insert(attachment.fileName)
            return QuickNoteAttachmentBackupFile(fileName: attachment.fileName, data: data)
        }
    }

    static func allStoredFileNames() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.directory_list_failed", error: error)
            return []
        }
    }

    static func referencedFileNames(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> Set<String> {
        var names = Set((notes.flatMap { $0.attachments.map(\.fileName) }) + extraAttachments.map(\.fileName))
        names.formUnion(draftReferencedFileNames())
        let videoAttachments = notes.flatMap(\.attachments).filter { $0.attachmentKind == .video }
            + extraAttachments.filter { $0.attachmentKind == .video }
        for attachment in videoAttachments {
            names.insert(videoThumbnailFileName(for: attachment.fileName))
        }
        return names
    }

    static func orphanFileNames(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> [String] {
        let referenced = referencedFileNames(for: notes, extraAttachments: extraAttachments)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [QuickNoteAttachmentBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.restore_failed", error: error)
        }
    }

    static func restoreOrThrow(_ files: [QuickNoteAttachmentBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    static func videoThumbnail(for fileName: String) -> UIImage? {
        let thumbName = videoThumbnailFileName(for: fileName)
        if let data = data(for: thumbName), let image = UIImage(data: data) {
            return image
        }
        let asset = AVAsset(url: fileURL(for: fileName))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.video_thumbnail_failed", fileName: fileName, error: error)
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        if let data = image.jpegData(compressionQuality: 0.72) {
            _ = saveData(data, fileName: thumbName)
        }
        return image
    }

    static func thumbnailCacheUsageBytes() -> Int {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return 0
        }
        return files.reduce(0) { total, url in
            guard url.lastPathComponent.hasPrefix("thumb-") else { return total }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                return total + (values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_file_size_failed", fileName: url.lastPathComponent, error: error)
                return total
            }
        }
    }

    static func clearThumbnailCache() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: nil)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return
        }
        for url in files where url.lastPathComponent.hasPrefix("thumb-") {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_cleanup_failed", fileName: url.lastPathComponent, error: error)
            }
        }
    }

    private static func videoThumbnailFileName(for fileName: String) -> String {
        "thumb-\(fileName).jpg"
    }

    private static func draftReferencedFileNames() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: "quickNoteDraftAttachments"),
              let data = raw.data(using: .utf8) else {
            return []
        }
        let attachments: [QuickNoteAttachment]
        do {
            attachments = try JSONDecoder().decode([QuickNoteAttachment].self, from: data)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.draft_decode_failed", error: error)
            return []
        }
        var names = Set(attachments.map(\.fileName))
        for attachment in attachments where attachment.attachmentKind == .video {
            names.insert(videoThumbnailFileName(for: attachment.fileName))
        }
        return names
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("QuickNoteAttachments")
        }
    }

    static func clearAttachmentsDirectory() {
        do {
            try FileManager.default.removeItem(at: attachmentDir)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.directory_cleanup_failed", fileName: attachmentDir.lastPathComponent, error: error)
        }
    }
}

private extension UIImage {
    func resizedForQuickNote(longEdge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > longEdge, maxSide > 0 else { return self }
        let ratio = longEdge / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private enum DocumentStorageBackgroundReader {
    static func data(
        from url: URL,
        missingFileCode: CocoaError.Code,
        missingLogEvent: String?,
        failureLogEvent: String,
        fileName: String
    ) async -> Data? {
        await Task.detached(priority: .utility) {
            do {
                return try Data(contentsOf: url, options: .mappedIfSafe)
            } catch let cocoaError as CocoaError where cocoaError.code == missingFileCode {
                if let missingLogEvent {
                    DocumentStorageIssueLogger.record(missingLogEvent, fileName: fileName)
                }
                return nil
            } catch {
                DocumentStorageIssueLogger.record(failureLogEvent, fileName: fileName, error: error)
                return nil
            }
        }.value
    }
}
