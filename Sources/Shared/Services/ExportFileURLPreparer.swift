import Foundation

enum ExportFileURLPreparer {
    private static let exportDirectoryPrefix = "sitekeeper-export-"

    static func prepare(sourceFileURL: URL, suggestedFileName: String) throws -> URL {
        let fileName = sanitizedFileName(suggestedFileName, fallbackExtension: sourceFileURL.pathExtension)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(exportDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let targetURL = directory.appendingPathComponent(fileName)
        try FileManager.default.moveItem(at: sourceFileURL, to: targetURL)
        return targetURL
    }

    static func cleanup(fileURL: URL) {
        let parent = fileURL.deletingLastPathComponent()
        if parent.lastPathComponent.hasPrefix(exportDirectoryPrefix) {
            do {
                _ = try FileOps.removeIfExists(
                    at: parent,
                    context: .init(
                        event: "export.cleanup_directory",
                        category: .fileStorage,
                        source: "ExportFileURLPreparer.cleanup"
                    )
                )
            } catch {
                StorageIssueLog.recordEvent(
                    "export.cleanup_directory_failed",
                    category: .fileStorage,
                    details: ["directory": parent.lastPathComponent],
                    error: error
                )
            }
        } else {
            do {
                _ = try FileOps.removeIfExists(
                    at: fileURL,
                    context: .init(
                        event: "export.cleanup_file",
                        category: .fileStorage,
                        source: "ExportFileURLPreparer.cleanup"
                    )
                )
            } catch {
                StorageIssueLog.recordEvent(
                    "export.cleanup_file_failed",
                    category: .fileStorage,
                    details: ["file": fileURL.lastPathComponent],
                    error: error
                )
            }
        }
    }

    private static func sanitizedFileName(_ raw: String, fallbackExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            cleaned = "导出文件"
        }
        if cleaned.split(separator: ".").count == 1, !fallbackExtension.isEmpty {
            cleaned += ".\(fallbackExtension)"
        }
        return cleaned
    }
}
