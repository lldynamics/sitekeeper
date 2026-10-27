import Foundation

enum FileStorageError: LocalizedError, Equatable {
    case invalidImageData
    case imageEncodingFailed
    case unsupportedFileType(String)
    case directoryCreationFailed(String)
    case copyFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return AppLocalization.string("无法识别图片数据。")
        case .imageEncodingFailed:
            return AppLocalization.string("图片编码失败。")
        case .unsupportedFileType(let type):
            return String(format: AppLocalization.string("暂不支持的文件类型：%@。"), type)
        case .directoryCreationFailed(let name):
            return String(format: AppLocalization.string("无法创建存储目录：%@。"), name)
        case .copyFailed(let name):
            return String(format: AppLocalization.string("文件复制失败：%@。"), name)
        case .writeFailed(let name):
            return String(format: AppLocalization.string("文件写入失败：%@。"), name)
        case .readFailed(let name):
            return String(format: AppLocalization.string("文件读取失败：%@。"), name)
        case .deleteFailed(let name):
            return String(format: AppLocalization.string("文件删除失败：%@。"), name)
        }
    }
}

struct FileOpsAuditContext {
    let action: OperationAuditEntry.Action
    let summary: String
    let source: String
    var detail: String = ""
}

enum FileOps {
    enum RemovalStrategy {
        case permanent
        case quarantine(
            category: FileQuarantineCategory,
            originalFileName: String? = nil,
            retentionDays: Int? = nil
        )

        var storageLogValue: String {
            switch self {
            case .permanent:
                return "permanent"
            case .quarantine(let category, _, _):
                return "quarantine:\(category.rawValue)"
            }
        }
    }

    struct Context {
        let event: String
        let category: StorageIssueCategory
        let source: String
        var audit: FileOpsAuditContext?
    }

    @discardableResult
    static func removeIfExists(
        at url: URL,
        strategy: RemovalStrategy = .permanent,
        context: Context
    ) throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return false }
        do {
            switch strategy {
            case .permanent:
                try manager.removeItem(at: url)
            case .quarantine(let category, let originalFileName, let retentionDays):
                _ = try FileQuarantineStore.quarantine(
                    fileAt: url,
                    category: category,
                    originalFileName: originalFileName ?? url.lastPathComponent,
                    retentionDays: retentionDays
                )
            }
            recordAudit(
                context.audit,
                outcome: .succeeded,
                fileName: url.lastPathComponent
            )
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "\(context.event).remove_failed",
                category: context.category,
                details: [
                    "source": context.source,
                    "file": url.lastPathComponent,
                    "strategy": strategy.storageLogValue
                ],
                error: error
            )
            recordAudit(
                context.audit,
                outcome: .failed,
                fileName: url.lastPathComponent
            )
            throw error
        }
    }

    static func replaceByCopyWithRollback(
        from sourceURL: URL,
        to targetURL: URL,
        context: Context
    ) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: sourceURL.path) else {
            let error = FileStorageError.copyFailed(sourceURL.lastPathComponent)
            StorageIssueLog.recordEvent(
                "\(context.event).source_missing",
                category: context.category,
                details: [
                    "source": context.source,
                    "file": sourceURL.lastPathComponent
                ],
                error: error
            )
            recordAudit(
                context.audit,
                outcome: .failed,
                fileName: targetURL.lastPathComponent
            )
            throw error
        }

        let hasExistingTarget = manager.fileExists(atPath: targetURL.path)
        let rollbackURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".fileops-rollback-\(UUID().uuidString)-\(targetURL.lastPathComponent)")

        do {
            if hasExistingTarget {
                try manager.moveItem(at: targetURL, to: rollbackURL)
            }
            try manager.copyItem(at: sourceURL, to: targetURL)
            if manager.fileExists(atPath: rollbackURL.path) {
                do {
                    try manager.removeItem(at: rollbackURL)
                } catch {
                    StorageIssueLog.recordEvent(
                        "\(context.event).rollback_cleanup_failed",
                        category: context.category,
                        details: [
                            "source": context.source,
                            "file": rollbackURL.lastPathComponent
                        ],
                        error: error
                    )
                }
            }
            recordAudit(
                context.audit,
                outcome: .succeeded,
                fileName: targetURL.lastPathComponent
            )
        } catch {
            rollbackTargetIfNeeded(
                targetURL: targetURL,
                rollbackURL: rollbackURL,
                category: context.category,
                source: context.source,
                event: context.event
            )
            StorageIssueLog.recordEvent(
                "\(context.event).replace_failed",
                category: context.category,
                details: [
                    "source": context.source,
                    "sourceFile": sourceURL.lastPathComponent,
                    "targetFile": targetURL.lastPathComponent
                ],
                error: error
            )
            recordAudit(
                context.audit,
                outcome: .failed,
                fileName: targetURL.lastPathComponent
            )
            throw error
        }
    }

    private static func rollbackTargetIfNeeded(
        targetURL: URL,
        rollbackURL: URL,
        category: StorageIssueCategory,
        source: String,
        event: String
    ) {
        let manager = FileManager.default
        if manager.fileExists(atPath: targetURL.path) {
            try? manager.removeItem(at: targetURL)
        }
        guard manager.fileExists(atPath: rollbackURL.path) else { return }
        do {
            try manager.moveItem(at: rollbackURL, to: targetURL)
        } catch {
            StorageIssueLog.recordEvent(
                "\(event).rollback_restore_failed",
                category: category,
                details: [
                    "source": source,
                    "file": targetURL.lastPathComponent
                ],
                error: error
            )
        }
    }

    private static func recordAudit(
        _ audit: FileOpsAuditContext?,
        outcome: OperationAuditEntry.Outcome,
        fileName: String
    ) {
        guard let audit else { return }
        let prefix = audit.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = prefix.isEmpty ? "file=\(fileName)" : "\(prefix), file=\(fileName)"
        OperationAuditLog.record(
            action: audit.action,
            outcome: outcome,
            summary: audit.summary,
            detail: detail,
            source: audit.source
        )
    }
}
