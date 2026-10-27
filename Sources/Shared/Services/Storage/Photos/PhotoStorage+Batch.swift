import Foundation
import UIKit

extension PhotoStorage {
    // 逐调用注入目录与故障点，测试无需切换全局文档目录或影响其他并行用例。
    enum BatchCheckpoint: Equatable, Sendable {
        case stagingWrite(Int)
        case commit(Int)
        case rollback(Int)
    }

    struct BatchRecoveryError: LocalizedError {
        let originalError: Error
        let rollbackErrors: [Error]
        let recoveryDirectory: URL

        var errorDescription: String? { originalError.localizedDescription }
    }

    private struct BatchTarget {
        let destination: URL
        let staged: URL
        let previous: URL?
    }

    private static let batchWriteLock = NSLock()

    static func saveManyOrThrow(
        originals: [Data],
        logId: UUID,
        directory: URL,
        checkpoint: (BatchCheckpoint) throws -> Void = { _ in }
    ) throws -> [String] {
        let names = originals.indices.map { index in
            "\(logId.uuidString)\(index == 0 ? "" : "-\(index)").jpg"
        }
        try saveBatchOrThrow(originals: originals, fileNames: names, directory: directory, checkpoint: checkpoint)
        return names
    }

    static func saveBatchOrThrow(
        originals: [Data],
        fileNames: [String],
        directory: URL,
        checkpoint: (BatchCheckpoint) throws -> Void = { _ in }
    ) throws {
        guard !originals.isEmpty else { return }
        batchWriteLock.lock()
        defer { batchWriteLock.unlock() }
        try Task.checkCancellation()
        let transaction = directory.appendingPathComponent(".photo-transaction-\(UUID().uuidString)", isDirectory: true)
        var attempted: [BatchTarget] = []
        do {
            try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
            let targets = try prepareBatch(originals: originals, fileNames: fileNames, directory: directory,
                                           transaction: transaction, checkpoint: checkpoint)
            try writeBatchManifest(targets, transaction: transaction)
            try commitBatch(targets, attempted: &attempted, checkpoint: checkpoint)
        } catch {
            try rollbackBatch(attempted, fileNames: fileNames, transaction: transaction,
                              originalError: error, checkpoint: checkpoint)
        }
        fileNames.forEach { PhotoCache.shared.invalidate(fileName: $0) }
        do {
            try removeTransactionFile(transaction)
        } catch {
            // 提交已成功，清理失败不能伪装成保存失败；保留路径和底层错误供诊断。
            logIssue("batch_staging_cleanup_failed", error: error, details: ["recoveryDirectory": transaction.path])
        }
    }

    private static func prepareBatch(
        originals: [Data],
        fileNames: [String],
        directory: URL,
        transaction: URL,
        checkpoint: (BatchCheckpoint) throws -> Void
    ) throws -> [BatchTarget] {
        var targets: [BatchTarget] = []
        // 先完成整批解码、预写入和旧文件备份，正式目标在准备阶段保持原样。
        for (index, original) in originals.enumerated() {
            try Task.checkCancellation()
            let thumbnail = try batchThumbnail(original)
            for (folder, data) in [("Photos", original), ("PhotoThumbnails", thumbnail)] {
                try Task.checkCancellation()
                let destination = directory.appendingPathComponent(folder, isDirectory: true)
                    .appendingPathComponent(fileNames[index])
                let target = try stageBatchTarget(data, destination: destination, position: targets.count,
                                                 transaction: transaction, checkpoint: checkpoint)
                targets.append(target)
            }
        }
        return targets
    }

    private static func batchThumbnail(_ original: Data) throws -> Data {
        try autoreleasepool {
            guard let image = UIImage(data: original) else { throw FileStorageError.invalidImageData }
            guard let data = resize(image, maxSide: 800).jpegData(compressionQuality: 0.7) else {
                throw FileStorageError.imageEncodingFailed
            }
            return data
        }
    }

    private static func stageBatchTarget(
        _ data: Data,
        destination: URL,
        position: Int,
        transaction: URL,
        checkpoint: (BatchCheckpoint) throws -> Void
    ) throws -> BatchTarget {
        let staged = transaction.appendingPathComponent("new-\(position)")
        try checkpoint(.stagingWrite(position))
        try data.write(to: staged, options: .atomic)
        let previous: URL?
        if FileManager.default.fileExists(atPath: destination.path) {
            let backup = transaction.appendingPathComponent("previous-\(position)")
            try FileManager.default.copyItem(at: destination, to: backup)
            previous = backup
        } else {
            previous = nil
        }
        return BatchTarget(destination: destination, staged: staged, previous: previous)
    }

    private static func writeBatchManifest(_ targets: [BatchTarget], transaction: URL) throws {
        let manifest = targets.map { target in
            ["destination": target.destination.path, "staged": target.staged.lastPathComponent,
             "previous": target.previous?.lastPathComponent ?? ""]
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: transaction.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private static func commitBatch(
        _ targets: [BatchTarget],
        attempted: inout [BatchTarget],
        checkpoint: (BatchCheckpoint) throws -> Void
    ) throws {
        for (index, target) in targets.enumerated() {
            try checkpoint(.commit(index))
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: target.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            attempted.append(target)
            try Data(contentsOf: target.staged).write(to: target.destination, options: .atomic)
        }
    }

    private static func rollbackBatch(
        _ attempted: [BatchTarget],
        fileNames: [String],
        transaction: URL,
        originalError: Error,
        checkpoint: (BatchCheckpoint) throws -> Void
    ) throws -> Never {
        var rollbackErrors: [Error] = []
        // 回滚不响应取消，旧字节只有在恢复成功后才允许清理。
        for (index, target) in attempted.reversed().enumerated() {
            do {
                try checkpoint(.rollback(index))
                if let previous = target.previous {
                    try Data(contentsOf: previous).write(to: target.destination, options: .atomic)
                } else {
                    try removeTransactionFile(target.destination)
                }
            } catch {
                rollbackErrors.append(error)
                logIssue("batch_rollback_failed", fileName: target.destination.lastPathComponent, error: error,
                         details: ["recoveryDirectory": transaction.path])
            }
        }
        fileNames.forEach { PhotoCache.shared.invalidate(fileName: $0) }
        if rollbackErrors.isEmpty {
            do { try removeTransactionFile(transaction) } catch { rollbackErrors.append(error) }
        }
        guard rollbackErrors.isEmpty else {
            logIssue("batch_recovery_required", error: originalError, details: ["recoveryDirectory": transaction.path])
            throw BatchRecoveryError(originalError: originalError, rollbackErrors: rollbackErrors, recoveryDirectory: transaction)
        }
        throw originalError
    }

    private static func removeTransactionFile(_ url: URL) throws {
        try FileOps.removeIfExists(
            at: url,
            context: .init(event: "photo.batch_transaction_cleanup", category: .fileStorage, source: "PhotoStorage.saveBatchOrThrow")
        )
    }
}
