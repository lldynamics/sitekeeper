import Foundation
import ZIPFoundation

enum StreamingZipArchiveWriterError: LocalizedError {
    case invalidPath(String)
    case duplicatePath(String)
    case writerClosed
    case sourceFileMissing(String)
    case writeSizeMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return String(format: AppLocalization.string("ZIP 路径无效：%@"), path)
        case .duplicatePath(let path):
            return String(format: AppLocalization.string("ZIP 路径重复：%@"), path)
        case .writerClosed:
            return AppLocalization.string("ZIP 写入器已关闭。")
        case .sourceFileMissing(let name):
            return String(format: AppLocalization.string("源文件不存在：%@"), name)
        case .writeSizeMismatch(let expected, let actual):
            return String(
                format: AppLocalization.string("ZIP 写入大小不一致（预期 %lld 字节，实际 %lld 字节）。"),
                Int64(expected),
                Int64(actual)
            )
        }
    }
}

/// Application limits and cancellation wrap ZIPFoundation's ZIP/ZIP64 implementation.
struct StreamingZipArchiveWriter {
    let fileURL: URL
    private var archive: Archive?
    private var entryPaths = Set<String>()
    private let limits: BackupArchiveLimits?
    private var totalUncompressedBytes: UInt64 = 0

    init(fileURL: URL, limits: BackupArchiveLimits? = nil) throws {
        self.fileURL = fileURL
        self.limits = limits
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try FileOps.removeIfExists(
            at: fileURL,
            context: .init(event: "zip.writer.cleanup_existing", category: .zipArchive, source: "StreamingZipArchiveWriter.init")
        )
        archive = try Archive(url: fileURL, accessMode: .create, pathEncoding: nil)
    }

    static func makeTemporaryFileURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).zip")
    }

    mutating func addFile(path: String, data: Data) throws {
        let archive = try prepareEntry(path: path, size: UInt64(data.count))
        do {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), bufferSize: 256 * 1024) { position, size in
                try Task.checkCancellation()
                let start = Int(position)
                return data.subdata(in: start..<(start + size))
            }
        } catch {
            self.archive = nil
            throw error
        }
    }

    mutating func addFile(path: String, sourceFileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: sourceFileURL.path) else {
            throw StreamingZipArchiveWriterError.sourceFileMissing(sourceFileURL.lastPathComponent)
        }
        let input = try FileHandle(forReadingFrom: sourceFileURL)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        try input.seek(toOffset: 0)
        guard size <= UInt64(Int64.max) else { throw SimpleZipArchiveReader.ZipReadError.limitExceeded(path) }
        let archive = try prepareEntry(path: path, size: size)
        do {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(size), bufferSize: 256 * 1024) { position, count in
                try Task.checkCancellation()
                try input.seek(toOffset: UInt64(position))
                let data = try input.read(upToCount: count) ?? Data()
                guard data.count == count else {
                    throw StreamingZipArchiveWriterError.writeSizeMismatch(expected: count, actual: data.count)
                }
                return data
            }
            // A source that grew during export must not silently become a truncated backup.
            guard try input.seekToEnd() == size else {
                throw StreamingZipArchiveWriterError.writeSizeMismatch(expected: Int(clamping: size), actual: Int(clamping: try input.offset()))
            }
        } catch {
            self.archive = nil
            throw error
        }
    }

    mutating func finish() throws -> URL {
        guard archive != nil else { throw StreamingZipArchiveWriterError.writerClosed }
        try close()
        return fileURL
    }

    mutating func close() throws {
        // ZIPFoundation finalizes the central directory on each entry and closes on deinit.
        archive = nil
    }

    private mutating func prepareEntry(path: String, size: UInt64) throws -> Archive {
        guard let archive else { throw StreamingZipArchiveWriterError.writerClosed }
        do { try SimpleZipArchiveReader.validateArchivePath(path) } catch { throw StreamingZipArchiveWriterError.invalidPath(path) }
        guard !path.hasSuffix("/") else { throw StreamingZipArchiveWriterError.invalidPath(path) }
        guard !entryPaths.contains(path) else { throw StreamingZipArchiveWriterError.duplicatePath(path) }
        var total = totalUncompressedBytes
        try limits?.validate(path: path, size: size, entryCount: entryPaths.count + 1, total: &total)
        try Task.checkCancellation()
        entryPaths.insert(path)
        totalUncompressedBytes = total
        return archive
    }
}
