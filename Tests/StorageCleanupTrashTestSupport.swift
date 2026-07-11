import Foundation
@testable import sitekeeper

@MainActor
enum StorageCleanupTrashTestSupport {
    static func emptyUndoSnapshot() -> StorageCleanupUndoSnapshot {
        StorageCleanupUndoSnapshot(
            dailyLogs: [],
            siteTodos: [],
            quickNotes: [],
            projectDrawings: [],
            projectDocuments: [],
            projectFinancialRecords: [],
            projectWarehouseMovements: []
        )
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        removeFileIfExists(url)
        try data.write(to: url, options: .atomic)
    }

    static func removeFileIfExists(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func rootURL() throws -> URL {
        try StorageCleanupTrashStore.rootURLForTesting()
    }

    static func manifestURL() throws -> URL {
        try StorageCleanupTrashStore.manifestURLForTesting()
    }

    static func preserveManifest() throws -> () -> Void {
        let manager = FileManager.default
        let rootURL = try rootURL()
        let manifestURL = try manifestURL()
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let originalAttributes = try? manager.attributesOfItem(atPath: rootURL.path)
        let originalPermissions = originalAttributes?[.posixPermissions] as? NSNumber
        let backupURL = rootURL.appendingPathComponent(".manifest-backup-\(UUID().uuidString)")
        var didBackupManifest = false

        if manager.fileExists(atPath: backupURL.path) {
            try? manager.removeItem(at: backupURL)
        }
        if manager.fileExists(atPath: manifestURL.path) {
            try manager.moveItem(at: manifestURL, to: backupURL)
            didBackupManifest = true
        }

        return {
            try? manager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: rootURL.path)
            if manager.fileExists(atPath: manifestURL.path) {
                try? manager.removeItem(at: manifestURL)
            }
            if didBackupManifest, manager.fileExists(atPath: backupURL.path) {
                try? manager.moveItem(at: backupURL, to: manifestURL)
            }
            if let originalPermissions {
                try? manager.setAttributes([.posixPermissions: originalPermissions], ofItemAtPath: rootURL.path)
            }
        }
    }

    static func setRootPermissions(_ permissions: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: rootURL().path
        )
    }

    static func writeManifest(_ batches: [StorageCleanupTrashBatch]) throws {
        let manager = FileManager.default
        let rootURL = try rootURL()
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt })
        try data.write(to: try manifestURL(), options: .atomic)
    }
}
