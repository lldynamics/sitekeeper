import Foundation

struct DocumentStorageFileFamily {
    let directoryName: String
    let eventPrefix: String

    var directoryURL: URL {
        baseDirectory.appendingPathComponent(directoryName)
    }

    func fileURL(for fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed(directoryName)
        }
    }

    func writeDataOrThrow(_ data: Data, fileName: String, failureFileName: String? = nil) throws {
        try ensureDirectoryExists()
        do {
            try data.write(to: fileURL(for: fileName), options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(failureFileName ?? fileName)
        }
    }

    func copyFileOrThrow(from sourceURL: URL, fileName: String, failureFileName: String? = nil) throws {
        try ensureDirectoryExists()
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL(for: fileName))
        } catch {
            throw FileStorageError.copyFailed(failureFileName ?? sourceURL.lastPathComponent)
        }
    }

    func data(for fileName: String, failureEvent: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
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
                    return try Data(contentsOf: fileURL(for: fileName), options: .mappedIfSafe)
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
            at: fileURL(for: fileName),
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
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    func fileSize(for fileName: String, failureEvent: String) -> Int {
        fileSize(at: fileURL(for: fileName), failureEvent: failureEvent)
    }

    func fileSize(at url: URL, failureEvent: String) -> Int {
        do {
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
            let files = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            DocumentStorageIssueLogger.record(failureEvent, error: error)
            return []
        }
    }

    func restoreOrThrow(_ files: [(fileName: String, data: Data)]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
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
