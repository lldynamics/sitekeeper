import Foundation

extension FileQuarantineStore {
    struct FileIdentity: Equatable {
        let inode: UInt64
        let bytes: UInt64
        let modifiedAt: Date

        init(url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let inode = attributes[.systemFileNumber] as? NSNumber,
                  let bytes = attributes[.size] as? NSNumber,
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                throw FileStorageError.readFailed(url.lastPathComponent)
            }
            self.inode = inode.uint64Value
            self.bytes = bytes.uint64Value
            self.modifiedAt = modifiedAt
        }
    }

    struct DeferredQuarantine {
        let sourceURL: URL
        let category: FileQuarantineCategory
        let originalFileName: String?
        let retentionDays: Int?
        let identity: FileIdentity
        let quarantineRoot: URL?
    }

    // Every access uses transactionLock, including draining failed requests on retry.
    final class ExportProtection: @unchecked Sendable {
        var leases: [UUID: Set<String>] = [:]
        var retainedPaths = Set<String>()
        var requests: [String: DeferredQuarantine] = [:]
    }

    static let exportProtection = ExportProtection()
    static func beginBackupExport(protecting fileURLs: Set<URL>) -> UUID {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        if exportProtection.leases.isEmpty { exportProtection.retainedPaths = [] }
        let leaseID = UUID()
        exportProtection.leases[leaseID] = Set(fileURLs.map { $0.standardizedFileURL.path })
        return leaseID
    }

    static func endBackupExport(_ leaseID: UUID, retaining fileURLs: Set<URL>) {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        guard exportProtection.leases.removeValue(forKey: leaseID) != nil else { return }
        exportProtection.retainedPaths.formUnion(fileURLs.map { $0.standardizedFileURL.path })
        retryDeferredQuarantines(retainingPaths: exportProtection.retainedPaths)
    }

    static func isQuarantineDeferred(for url: URL) -> Bool {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return exportProtection.requests[url.standardizedFileURL.path] != nil
    }

    private static func retryDeferredQuarantines(retainingPaths: Set<String>) {
        for (path, request) in Array(exportProtection.requests) {
            guard !exportProtection.leases.values.contains(where: { $0.contains(path) }) else { continue }
            guard request.quarantineRoot == rootURL else { continue }
            do {
                guard !retainingPaths.contains(path), FileManager.default.fileExists(atPath: path) else {
                    exportProtection.requests.removeValue(forKey: path)
                    continue
                }
                // A replacement at the same pathname belongs to a later operation.
                guard try FileIdentity(url: request.sourceURL) == request.identity else {
                    exportProtection.requests.removeValue(forKey: path)
                    continue
                }
                try quarantine(fileAt: request.sourceURL, category: request.category,
                               originalFileName: request.originalFileName, retentionDays: request.retentionDays)
                exportProtection.requests.removeValue(forKey: path)
            } catch {
                StorageIssueLog.recordEvent(
                    "quarantine.deferred_delete_failed", category: .fileStorage,
                    details: ["file": request.sourceURL.lastPathComponent], error: error
                )
                // Keep both the file and request; the next completed export retries it.
            }
        }
    }
}
