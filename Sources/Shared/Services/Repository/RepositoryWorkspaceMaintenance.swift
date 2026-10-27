import Foundation
import os

enum RepositoryWorkspaceMaintenanceError: LocalizedError {
    case inUse, unsafeDirectory, changed

    var errorDescription: String? {
        switch self {
        case .inUse: AppLocalization.string("请先关闭正在使用的试用副本，再清理数据。")
        case .unsafeDirectory: AppLocalization.string("试用副本目录异常，已停止清理并保留文件。")
        case .changed: AppLocalization.string("试用副本已变化，请重新查看清空预览后确认。")
        }
    }
}

/// Every open repository and candidate builder holds a reader lease. Destructive
/// maintenance is exclusive, so SQLite handles cannot outlive a successful clear.
final class RepositoryWorkspaceLease: Sendable {
    private struct State { var readers = 0
    var exclusive = false }
    private static let states = OSAllocatedUnfairLock(initialState: [String: State]())
    private let key: String
    private let exclusive: Bool

    init(root: URL, exclusive: Bool = false) throws {
        let key = root.resolvingSymlinksInPath().standardizedFileURL.path
        try Self.states.withLock { states in
            var state = states[key] ?? State()
            guard !state.exclusive, !exclusive || state.readers == 0 else {
                throw RepositoryWorkspaceMaintenanceError.inUse
            }
            if exclusive { state.exclusive = true } else { state.readers += 1 }
            states[key] = state
        }
        self.key = key
        self.exclusive = exclusive
    }

    deinit {
        Self.states.withLock { states in
            guard var state = states[key] else { return }
            if exclusive { state.exclusive = false } else { state.readers -= 1 }
            states[key] = state.readers == 0 && !state.exclusive ? nil : state
        }
    }
}

enum RepositoryWorkspaceMaintenance {
    struct Summary { let count: Int
    let bytes: Int64 }

    static func root(beside source: URL) -> URL {
        source.deletingLastPathComponent().appendingPathComponent(".sqlite-candidates", isDirectory: true)
    }

    static func summary(beside source: URL) throws -> Summary {
        let directories = try directories(in: root(beside: source))
        return Summary(count: directories.count, bytes: try directories.reduce(0) { try $0 + byteCount(in: $1) })
    }

    static func byteCount(in directory: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        var failure: Error?
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
            failure = error
            return false
        }) else { throw RepositoryWorkspaceMaintenanceError.unsafeDirectory }
        var total: Int64 = 0
        for case let url as URL in entries {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw RepositoryWorkspaceMaintenanceError.unsafeDirectory }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        if let failure { throw failure }
        return total
    }

    fileprivate static func directories(in root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw RepositoryWorkspaceMaintenanceError.unsafeDirectory }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { url in
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard UUID(uuidString: url.lastPathComponent) != nil, values.isDirectory == true, values.isSymbolicLink != true else {
                    throw RepositoryWorkspaceMaintenanceError.unsafeDirectory
                }
                return url
            }.sorted { $0.path < $1.path }
    }

    static func prepareClear(beside source: URL, expectedCount: Int? = nil) throws -> RepositoryWorkspaceClearPlan {
        let directory = root(beside: source)
        let lease = try RepositoryWorkspaceLease(root: directory, exclusive: true)
        let copies = try directories(in: directory)
        guard expectedCount == nil || expectedCount == copies.count else { throw RepositoryWorkspaceMaintenanceError.changed }
        return RepositoryWorkspaceClearPlan(root: directory, copies: copies, lease: lease)
    }

    static func remove(_ entry: RepositoryWorkspaceEntry, beside source: URL) throws {
        let plan = try prepareClear(beside: source)
        defer { withExtendedLifetime(plan) {} }
        guard plan.copies.contains(entry.directory), entry.directory.lastPathComponent == entry.id.uuidString else {
            throw RepositoryWorkspaceMaintenanceError.unsafeDirectory
        }
        _ = try FileOps.removeIfExists(at: entry.directory, context: .init(
            event: "repository.delete_copy", category: .dataStore, source: "RepositoryWorkspaceMaintenance"
        ))
    }
}

struct RepositoryWorkspaceClearPlan: Sendable {
    let root: URL
    let copies: [URL]
    fileprivate let lease: RepositoryWorkspaceLease

    func removeAll() throws {
        guard try RepositoryWorkspaceMaintenance.directories(in: root) == copies else { throw RepositoryWorkspaceMaintenanceError.changed }
        _ = try FileOps.removeIfExists(at: root, context: .init(
            event: "repository.clear_all_copies", category: .dataStore, source: "RepositoryWorkspaceClearPlan"
        ))
    }
}
