import Foundation

struct ProjectDocumentBackupFile: Identifiable, Codable, Sendable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum ProjectDocumentStorage {
    private static let fileFamily = DocumentStorageFileFamily(
        directoryName: "ProjectDocuments",
        eventPrefix: "project_document"
    )

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
        try fileFamily.writeDataOrThrow(data, fileName: fileName)
        return fileName
    }

    static func saveImportedFileOrThrow(from sourceURL: URL, projectId: UUID, fileExtension ext: String) throws -> String {
        let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName = "\(projectId.uuidString)-\(UUID().uuidString).\(normalizedExt.isEmpty ? "dat" : normalizedExt)"
        try fileFamily.copyFileOrThrow(from: sourceURL, fileName: fileName)
        return fileName
    }

    static func fileURL(for fileName: String) -> URL {
        fileFamily.fileURL(for: fileName)
    }

    static func data(for fileName: String) -> Data? {
        fileFamily.data(for: fileName, failureEvent: "project_document.read_failed")
    }

    static func dataAsync(for fileName: String) async -> Data? {
        await fileFamily.dataAsync(for: fileName, failureEvent: "project_document.read_failed")
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
        try fileFamily.deleteOrThrow(
            fileName: fileName,
            quarantineCategory: .projectDocument,
            event: "project_document.delete",
            source: "ProjectDocumentStorage.deleteOrThrow"
        )
    }

    static func exists(fileName: String) -> Bool {
        fileFamily.exists(fileName: fileName)
    }

    static func fileSize(for fileName: String) -> Int {
        fileFamily.fileSize(for: fileName, failureEvent: "project_document.file_size_failed")
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
        fileFamily.allStoredFileNames(failureEvent: "project_document.directory_list_failed")
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
        try fileFamily.restoreOrThrow(files.map { ($0.fileName, $0.data) })
    }
}
