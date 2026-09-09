import Foundation
import Darwin

/// Write-ahead recovery record. On-disk entries contain only a fixed storage family and
/// leaf names; a journal can never supply an absolute destination or metadata path.
final class BackupArchiveRestoreJournal {
    enum Family: String, Codable, CaseIterable {
        case photos, drawings, documents, attachments

        var stageDirectory: String {
            switch self {
            case .photos: "photos"
            case .drawings: "drawings"
            case .documents: "project-documents"
            case .attachments: "quick-note-attachments"
            }
        }

        func target(_ name: String) -> URL {
            switch self {
            case .photos: PhotoStorage.fileURL(for: name)
            case .drawings: DrawingStorage.fileURL(for: name)
            case .documents: ProjectDocumentStorage.fileURL(for: name)
            case .attachments: QuickNoteAttachmentStorage.fileURL(for: name)
            }
        }

        func destinations(_ policy: BackupEmbeddedFileRestorePolicy) -> [String: String]? {
            switch self {
            case .photos: policy.photoFileDestinations
            case .drawings: policy.drawingFileDestinations
            case .documents: policy.documentFileDestinations
            case .attachments: policy.quickNoteAttachmentFileDestinations
            }
        }
    }

    enum Phase: String, Codable { case prepared, filesCommitted, rollingBack, finished }
    struct Entry: Codable {
        let family: Family
        let source: String
        let destination: String
        let originalExisted: Bool
    }

    struct Record: Codable {
        let version: Int
        let hasMetadata: Bool
        let originalMetadataExisted: Bool
        var phase: Phase
        let entries: [Entry]
    }

    struct RecoveryPendingError: LocalizedError {
        let directory: URL
        let underlying: Error
        var errorDescription: String? {
            String(format: String(localized: "备份恢复尚未完成，恢复包已保留在 %@。请重试读取。"), directory.path)
                + " " + underlying.localizedDescription
        }
    }

    enum FaultPoint: Equatable { case prepared, beforeReplace(Int), afterReplace(Int), filesCommitted, beforeRollback(Int), beforeFinalize, beforeCleanup, beforeJournal }
    typealias FaultInjector = (FaultPoint) throws -> Void

    let root: URL
    private let storeURL: URL
    private var record: Record

    private init(root: URL, storeURL: URL, record: Record) {
        self.root = root
        self.storeURL = storeURL
        self.record = record
    }

    static func transactionsRoot(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(".backup-restore-transactions", isDirectory: true)
    }

    static func encodeMetadata(_ snapshot: BackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func begin(
        stageRoot: URL,
        storeURL: URL,
        metadataAfter: Data?,
        policy: BackupEmbeddedFileRestorePolicy,
        fault: FaultInjector? = nil
    ) throws -> BackupArchiveRestoreJournal {
        // Attachment-only helper sessions may be alive concurrently. Only the serialized
        // metadata import owns startup recovery of its store's transaction directory.
        if metadataAfter != nil { try recoverPending(storeURL: storeURL) }
        let manager = FileManager.default
        let parent = transactionsRoot(for: storeURL)
        try validateLocation(parent)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        BackupArchiveSecurity.applyDataProtection(to: root)
        var prepared = false
        defer { if !prepared { try? manager.removeItem(at: root) } }
        let originalExists = manager.fileExists(atPath: storeURL.path)
        if let metadataAfter {
            try validateLocation(storeURL)
            if originalExists {
                try manager.copyItem(at: storeURL, to: root.appendingPathComponent("before.json"))
            }
            try metadataAfter.write(to: root.appendingPathComponent("after.json"), options: .atomic)
        }
        let rollbackRoot = root.appendingPathComponent("rollback", isDirectory: true)
        try manager.createDirectory(at: rollbackRoot, withIntermediateDirectories: false)
        var entries: [Entry] = []
        for family in Family.allCases {
            let stage = stageRoot.appendingPathComponent(family.stageDirectory, isDirectory: true)
            let mapping = family.destinations(policy)
            for source in try manager.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                let name = source.lastPathComponent
                guard let destination = mapping?[name] ?? (mapping == nil ? name : nil) else { continue }
                try validateLeaf(name)
                try validateLeaf(destination)
                try validateLocation(source)
                let target = family.target(destination)
                try validateLocation(target)
                let existed = manager.fileExists(atPath: target.path)
                if existed && !policy.overwritesExistingFiles { continue }
                if existed {
                    try manager.copyItem(at: target, to: rollbackRoot.appendingPathComponent("\(entries.count).bak"))
                }
                entries.append(Entry(family: family, source: name, destination: destination, originalExisted: existed))
            }
        }
        // Moving within the sandbox preserves streaming staging without duplicating a large archive.
        try manager.moveItem(at: stageRoot, to: root.appendingPathComponent("stage", isDirectory: true))
        let record = Record(version: 1, hasMetadata: metadataAfter != nil,
                            originalMetadataExisted: originalExists, phase: .prepared, entries: entries)
        let journal = BackupArchiveRestoreJournal(root: root, storeURL: storeURL, record: record)
        try fault?(.beforeJournal)
        try journal.writeRecord()
        prepared = true
        return journal
    }

    @discardableResult
    func commitFiles(fault: FaultInjector? = nil) throws -> BackupEmbeddedRestoreCounts {
        try fault?(.prepared)
        for (index, entry) in record.entries.enumerated() {
            try fault?(.beforeReplace(index))
            let source = root.appendingPathComponent("stage").appendingPathComponent(entry.family.stageDirectory)
                .appendingPathComponent(entry.source)
            try Self.atomicCopy(source, to: entry.family.target(entry.destination))
            try fault?(.afterReplace(index))
        }
        record.phase = .filesCommitted
        try writeRecord()
        try fault?(.filesCommitted)
        refreshThumbnails()
        return BackupEmbeddedRestoreCounts(
            photoFileCount: record.entries.filter { $0.family == .photos }.count,
            drawingFileCount: record.entries.filter { $0.family == .drawings }.count,
            documentFileCount: record.entries.filter { $0.family == .documents }.count,
            quickNoteAttachmentFileCount: record.entries.filter { $0.family == .attachments }.count
        )
    }

    func rollback(fault: FaultInjector? = nil) throws {
        if record.phase == .finished {
            try finish()
            return
        }
        // Persist the decision before doing anything. A partially completed rollback must
        // never be mistaken for a completed import even when before == after metadata.
        record.phase = .rollingBack
        try writeRecord()
        for (index, entry) in record.entries.enumerated().reversed() {
            try fault?(.beforeRollback(index))
            let target = entry.family.target(entry.destination)
            try Self.validateLocation(target)
            if entry.originalExisted {
                try Self.atomicCopy(root.appendingPathComponent("rollback/\(index).bak"), to: target)
            } else if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
        if record.hasMetadata {
            if record.originalMetadataExisted {
                try Self.atomicCopy(root.appendingPathComponent("before.json"), to: storeURL)
            } else {
                try Self.validateLocation(storeURL)
                if FileManager.default.fileExists(atPath: storeURL.path) {
                    try FileManager.default.removeItem(at: storeURL)
                }
            }
        }
        refreshThumbnails()
        try finish()
    }

    func finish(fault: FaultInjector? = nil) throws {
        try fault?(.beforeFinalize)
        let previousPhase = record.phase
        record.phase = .finished
        do {
            try writeRecord()
        } catch {
            record.phase = previousPhase
            throw error
        }
        // Only terminal cleanup is best-effort. A failed terminal write must block future saves.
        do {
            try fault?(.beforeCleanup)
            try FileManager.default.removeItem(at: root)
        } catch {
            recordBackupArchiveIssue("backup.restore.terminal_cleanup_failed", fileName: root.lastPathComponent, error: error)
        }
    }

    static func recoverPending(storeURL: URL) throws {
        do {
            try recoverPendingTransactions(storeURL: storeURL)
        } catch {
            throw RecoveryPendingError(directory: transactionsRoot(for: storeURL), underlying: error)
        }
    }

    private static func recoverPendingTransactions(storeURL: URL) throws {
        let parent = transactionsRoot(for: storeURL)
        try validateLocation(parent)
        guard FileManager.default.fileExists(atPath: parent.path) else { return }
        for root in try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: root.lastPathComponent) != nil else { throw recoveryError() }
            try validateLocation(root)
            let recordURL = root.appendingPathComponent("journal.json")
            try validateLocation(recordURL)
            guard FileManager.default.fileExists(atPath: recordURL.path) else {
                // Preparation never changes targets until journal.json exists; terminal cleanup
                // can also leave an empty/orphaned directory after interruption.
                try FileManager.default.removeItem(at: root)
                continue
            }
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: recordURL))
            guard record.version == 1 else { throw recoveryError() }
            for entry in record.entries {
                try validateLeaf(entry.source)
                try validateLeaf(entry.destination)
                try validateLocation(entry.family.target(entry.destination))
            }
            let journal = BackupArchiveRestoreJournal(root: root, storeURL: storeURL, record: record)
            if record.phase == .finished {
                try FileManager.default.removeItem(at: root)
            } else if try journal.metadataWasCommitted() {
                try journal.finish()
            } else {
                try journal.rollback()
            }
        }
    }

    private func metadataWasCommitted() throws -> Bool {
        guard record.phase == .filesCommitted else { return false }
        guard record.hasMetadata else { return true }
        try Self.validateLocation(storeURL)
        let after = root.appendingPathComponent("after.json")
        try Self.validateLocation(after)
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        return try Data(contentsOf: storeURL, options: .mappedIfSafe) == Data(contentsOf: after, options: .mappedIfSafe)
    }

    private func writeRecord() throws {
        let target = root.appendingPathComponent("journal.json")
        try Self.validateLocation(target)
        try JSONEncoder().encode(record).write(to: target, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: target)
    }
}

private extension BackupArchiveRestoreJournal {
    private func refreshThumbnails() {
        PhotoStorage.regenerateThumbnails(for: record.entries.filter { $0.family == .photos }.map(\.destination))
    }

    private static func validateLeaf(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains("\0") else { throw recoveryError() }
    }

    /// Reject symlinks at every existing path component, including the storage family root.
    private static func validateLocation(_ url: URL) throws {
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            if let type = try? FileManager.default.attributesOfItem(atPath: cursor.path)[.type],
               type as? FileAttributeType == .typeSymbolicLink {
                // /var and /tmp are system aliases; resolving these outside our sandbox is safe.
                if cursor.path != "/var" && cursor.path != "/tmp" { throw recoveryError() }
            }
            cursor.deleteLastPathComponent()
        }
    }

    private static func atomicCopy(_ source: URL, to destination: URL) throws {
        try validateLocation(source)
        try validateLocation(destination)
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".restore-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        BackupArchiveSecurity.applyDataProtection(to: temporary)
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func recoveryError() -> BackupArchiveError {
        .restoreFailed(String(localized: "备份恢复记录无效或路径不安全，已暂停加载。"))
    }
}
