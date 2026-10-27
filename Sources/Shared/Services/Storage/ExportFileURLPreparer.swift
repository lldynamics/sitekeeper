import Foundation

enum ExportCompletionOutcome: Equatable {
    case succeeded
    case cancelled
    case failed(String)
    case invalidFile
}

enum ExportCompletionHandler {
    @MainActor
    static func notice(
        for outcome: ExportCompletionOutcome,
        retry: @escaping () -> Void
    ) -> OperationToastNotice {
        switch outcome {
        case .succeeded:
            AppHaptics.success()
            return .info(AppLocalization.string("导出成功"))
        case .cancelled:
            return .info(AppLocalization.string("已取消导出"))
        case .invalidFile:
            AppHaptics.error()
            return retryNotice(
                message: AppLocalization.string("导出文件为空或写入不完整，请重试。"),
                retry: retry
            )
        case .failed(let message):
            AppHaptics.error()
            return retryNotice(
                message: "\(AppLocalization.string("导出失败"))：\(message)",
                retry: retry
            )
        }
    }

    static func evaluate(
        _ result: Result<URL, Error>,
        source: String
    ) -> ExportCompletionOutcome {
        switch result {
        case .success(let fileURL):
            return validateExportedFile(at: fileURL, source: source) ? .succeeded : .invalidFile
        case .failure(let error):
            if isCancellation(error) {
                return .cancelled
            }
            return .failed(error.localizedDescription)
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain && error.code == CocoaError.userCancelled.rawValue) ||
            (error.domain == NSURLErrorDomain && error.code == URLError.cancelled.rawValue)
    }

    private static func retryNotice(
        message: String,
        retry: @escaping () -> Void
    ) -> OperationToastNotice {
        OperationToastNotice(
            message: message,
            actionTitle: AppLocalization.string("继续导出"),
            action: retry,
            autoDismissDuration: .seconds(4)
        )
    }

    private static func validateExportedFile(at fileURL: URL, source: String) -> Bool {
        let accessedSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                StorageIssueLog.recordEvent(
                    "export.validate_file_not_regular",
                    category: .fileStorage,
                    details: ["source": source, "file_name": fileURL.lastPathComponent]
                )
                return false
            }
            guard let fileSize = values.fileSize, fileSize > 0 else {
                StorageIssueLog.recordEvent(
                    "export.validate_file_empty",
                    category: .fileStorage,
                    details: ["source": source, "file_name": fileURL.lastPathComponent]
                )
                return false
            }
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "export.validate_file_metadata_failed",
                category: .fileStorage,
                details: ["source": source, "file_name": fileURL.lastPathComponent],
                error: error
            )
            return false
        }
    }
}

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
