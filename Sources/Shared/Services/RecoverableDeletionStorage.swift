import Foundation

enum RecoverableDeletionStorageError: Error {
    case rootUnavailable(String)
}

enum RecoverableDeletionStorage {
    private static let rootOverrideLock = NSLock()
    private static var rootOverrides: [String: URL] = [:]

    static func rootURL(named rootDirectoryName: String) -> URL? {
        if let rootOverride = rootOverride(for: rootDirectoryName) {
            return rootOverride
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    static func manifestURL(rootDirectoryName: String, manifestFileName: String) -> URL? {
        rootURL(named: rootDirectoryName)?
            .appendingPathComponent(manifestFileName)
    }

    @discardableResult
    static func createRootDirectory(named rootDirectoryName: String) throws -> URL {
        guard let rootURL = rootURL(named: rootDirectoryName) else {
            throw RecoverableDeletionStorageError.rootUnavailable(rootDirectoryName)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    static func loadManifest<Manifest: Decodable>(
        rootDirectoryName: String,
        manifestFileName: String,
        default defaultManifest: @autoclosure () -> Manifest
    ) throws -> Manifest {
        guard let manifestURL = manifestURL(
            rootDirectoryName: rootDirectoryName,
            manifestFileName: manifestFileName
        ) else {
            throw RecoverableDeletionStorageError.rootUnavailable(rootDirectoryName)
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return defaultManifest()
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func saveManifest<Manifest: Encodable>(
        _ manifest: Manifest,
        rootDirectoryName: String,
        manifestFileName: String
    ) throws {
        let rootURL = try createRootDirectory(named: rootDirectoryName)
        let manifestURL = rootURL.appendingPathComponent(manifestFileName)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    static func purgeExpiredItems<Item>(
        _ items: [Item],
        now: Date,
        expiresAt: (Item) -> Date,
        removeAfterFailure: Bool = false,
        deleteExpiredItem: (Item) throws -> Void,
        onDeleteFailure: (Item, Error) -> Void
    ) -> (remaining: [Item], purgedCount: Int) {
        var remaining: [Item] = []
        var purgedCount = 0

        for item in items {
            guard expiresAt(item) <= now else {
                remaining.append(item)
                continue
            }
            do {
                try deleteExpiredItem(item)
                purgedCount += 1
            } catch {
                onDeleteFailure(item, error)
                if removeAfterFailure {
                    purgedCount += 1
                } else {
                    remaining.append(item)
                }
            }
        }

        return (remaining, purgedCount)
    }

    static func withRootURLForTesting<T>(
        _ rootURL: URL,
        rootDirectoryName: String,
        perform body: () throws -> T
    ) rethrows -> T {
        let previous = setRootOverride(rootURL, for: rootDirectoryName)
        defer {
            restoreRootOverride(previous, for: rootDirectoryName)
        }
        return try body()
    }

    private static func rootOverride(for rootDirectoryName: String) -> URL? {
        rootOverrideLock.lock()
        defer { rootOverrideLock.unlock() }
        return rootOverrides[rootDirectoryName]
    }

    @discardableResult
    private static func setRootOverride(_ rootURL: URL, for rootDirectoryName: String) -> URL? {
        rootOverrideLock.lock()
        defer { rootOverrideLock.unlock() }
        let previous = rootOverrides[rootDirectoryName]
        rootOverrides[rootDirectoryName] = rootURL
        return previous
    }

    private static func restoreRootOverride(_ rootURL: URL?, for rootDirectoryName: String) {
        rootOverrideLock.lock()
        defer { rootOverrideLock.unlock() }
        rootOverrides[rootDirectoryName] = rootURL
    }
}
