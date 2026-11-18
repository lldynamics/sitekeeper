import Foundation

struct DocumentStorageFileFamily {
    let directoryName: String
    let eventPrefix: String

    var directoryURL: URL {
        baseDirectory.appendingPathComponent(directoryName)
    }

    /// Compatibility for preview/share callers: invalid metadata has no filesystem or network target.
    func fileURL(for fileName: String) -> URL {
        (try? validatedFileURL(for: fileName)) ?? AttachmentStoragePath.unavailableURL
    }

    func validatedFileURL(for fileName: String) throws -> URL {
        try AttachmentStoragePath.fileURL(for: fileName, in: directoryURL)
    }

    func ensureDirectoryExists() throws {
        do {
            try AttachmentStoragePath.validateDirectory(directoryURL)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed(directoryName)
        }
    }

    func writeDataOrThrow(_ data: Data, fileName: String, failureFileName: String? = nil) throws {
        let target = try validatedFileURL(for: fileName)
        try ensureDirectoryExists()
        do {
            try AttachmentStoragePath.validateFile(target)
            try data.write(to: target, options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(failureFileName ?? fileName)
        }
    }

    func copyFileOrThrow(from sourceURL: URL, fileName: String, failureFileName: String? = nil) throws {
        let target = try validatedFileURL(for: fileName)
        try ensureDirectoryExists()
        do {
            try AttachmentStoragePath.validateFile(target)
            try FileManager.default.copyItem(at: sourceURL, to: target)
        } catch {
            throw FileStorageError.copyFailed(failureFileName ?? sourceURL.lastPathComponent)
        }
    }

    func data(for fileName: String, failureEvent: String) -> Data? {
        do {
            return try Data(contentsOf: validatedFileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            DocumentStorageIssueLogger.record(failureEvent, fileName: fileName, error: error)
            return nil
        }
    }

    func dataAsync(for fileName: String, failureEvent: String) async -> Data? {
        do {
            return try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: failureEvent,
                    source: "DocumentStorageFileFamily.dataAsync",
                    category: .fileStorage,
                    details: ["file": fileName]
                )
            ) {
                do {
                    return try Data(contentsOf: validatedFileURL(for: fileName), options: .mappedIfSafe)
                } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
                    return nil
                }
            }
        } catch {
            return nil
        }
    }

    func deleteOrThrow(
        fileName: String,
        quarantineCategory: FileQuarantineCategory,
        event: String,
        source: String
    ) throws {
        let removed = try FileOps.removeIfExists(
            at: validatedFileURL(for: fileName),
            strategy: .quarantine(
                category: quarantineCategory,
                originalFileName: fileName
            ),
            context: .init(
                event: event,
                category: .fileStorage,
                source: source
            )
        )
        guard removed else { throw FileStorageError.deleteFailed(fileName) }
    }

    func exists(fileName: String) -> Bool {
        guard let url = try? validatedFileURL(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func fileSize(for fileName: String, failureEvent: String) -> Int {
        fileSize(at: fileURL(for: fileName), failureEvent: failureEvent)
    }

    func fileSize(at url: URL, failureEvent: String) -> Int {
        do {
            try AttachmentStoragePath.validateFile(url)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            DocumentStorageIssueLogger.record(failureEvent, fileName: url.lastPathComponent, error: error)
            return 0
        }
    }

    func allStoredFileNames(failureEvent: String) -> [String] {
        do {
            try AttachmentStoragePath.validateDirectory(directoryURL)
            let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            return files.filter { (try? AttachmentStoragePath.validateFile($0)) != nil }.map(\.lastPathComponent).sorted()
        } catch {
            DocumentStorageIssueLogger.record(failureEvent, error: error)
            return []
        }
    }

    func restoreOrThrow(_ files: [(fileName: String, data: Data)]) throws {
        // Validate the whole batch before touching any existing file.
        let targets = try files.map { try validatedFileURL(for: $0.fileName) }
        try ensureDirectoryExists()
        for (file, target) in zip(files, targets) {
            do {
                try AttachmentStoragePath.validateFile(target)
                try file.data.write(to: target, options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    private var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        DocumentStorageIssueLogger.record(
            "\(eventPrefix).base_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }
}

/// Attachment metadata stores a single leaf, never a path. Preserve historical names verbatim.
/// This boundary also protects legacy/local metadata that bypasses backup import validation.
enum AttachmentStoragePath {
    // No authority, host or filesystem path; URL consumers cannot read a local or remote resource.
    static let unavailableURL = URL(string: "sitekeeper-invalid-attachment:")!

    /// Treat names which may alias on the destination filesystem as the same
    /// attachment when planning backup restoration and cleanup.
    static func comparisonKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    static func isSafeLeaf(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    static func validateLeaf(_ name: String) throws {
        guard isSafeLeaf(name) else { throw FileStorageError.unsafeAttachmentPath(name) }
    }

    static func fileURL(for name: String, in directory: URL) throws -> URL {
        try validateLeaf(name)
        try validateDirectory(directory)
        let target = directory.appendingPathComponent(name)
        try validateFile(target)
        return target
    }

    static func validateFile(_ url: URL, boundaryPaths: Set<String> = sandboxRootBoundaries()) throws {
        guard url.isFileURL else { throw FileStorageError.unsafeAttachmentPath(url.lastPathComponent) }
        try validateDirectory(url.deletingLastPathComponent(), boundaryPaths: boundaryPaths)
        if let type = try existingType(at: url), type != .typeRegular {
            throw FileStorageError.unsafeAttachmentPath(url.lastPathComponent)
        }
    }

    static func validateDirectory(_ url: URL, boundaryPaths: Set<String> = sandboxRootBoundaries()) throws {
        guard url.isFileURL else { throw FileStorageError.unsafeAttachmentPath(url.lastPathComponent) }
        var cursor = url.standardizedFileURL
        while cursor.path != "/" {
            if boundaryPaths.contains(cursor.path) {
                break
            }
            if let type = try existingType(at: cursor), type != .typeDirectory {
                // These are OS-provided aliases, outside application-owned storage.
                guard type == .typeSymbolicLink, cursor.path == "/var" || cursor.path == "/tmp" else {
                    throw FileStorageError.unsafeAttachmentPath(cursor.lastPathComponent)
                }
            }
            cursor.deleteLastPathComponent()
        }
    }

    /// Stop ancestor traversal at OS-managed sandbox container roots so real iOS devices never call
    /// `lstat` on Seatbelt-restricted parent paths (`/private/var/mobile/Containers/Data/Application`).
    static func sandboxRootBoundaries() -> Set<String> {
        var roots: Set<String> = []
        let candidates: [URL] = [
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
            FileManager.default.temporaryDirectory
        ]
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL.path
            if standardized != "/" { roots.insert(standardized) }
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL.path
            if resolved != "/" { roots.insert(resolved) }
        }
        return roots
    }

    private static func existingType(at url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
