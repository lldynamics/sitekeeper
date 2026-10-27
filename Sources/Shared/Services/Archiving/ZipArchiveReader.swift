import Foundation
import ZIPFoundation

struct SimpleZipArchiveReader {
    struct Entry {
        let path: String
        let data: Data
    }

    struct ScanEntry {
        let path: String
        let dataSize: Int
    }

    enum ZipReadError: LocalizedError {
        case invalidArchive
        case unsupportedCompression
        case unsupportedDataDescriptor
        case invalidFileName
        case unsafePath(String)
        case duplicateEntry(String)
        case checksumMismatch(String)
        case limitExceeded(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return AppLocalization.string("备份 ZIP 结构不正确。")
            case .unsupportedCompression:
                return AppLocalization.string("备份 ZIP 使用了当前不支持的压缩方式。")
            case .unsupportedDataDescriptor:
                return AppLocalization.string("备份 ZIP 使用了当前不支持的数据描述符。")
            case .invalidFileName:
                return AppLocalization.string("备份 ZIP 内存在无法识别的文件名。")
            case .unsafePath(let path):
                return String(format: AppLocalization.string("备份 ZIP 路径不安全：%@"), path)
            case .duplicateEntry(let path):
                return String(format: AppLocalization.string("备份 ZIP 存在重复文件：%@"), path)
            case .checksumMismatch(let path):
                return String(format: AppLocalization.string("备份 ZIP 文件校验失败：%@"), path)
            case .limitExceeded(let reason):
                return String(format: AppLocalization.string("备份 ZIP 超出安全限制：%@"), reason)
            case .cancelled:
                return AppLocalization.string("已取消导入。")
            }
        }
    }

    static func read(_ data: Data, limits: BackupArchiveLimits = .inMemory) throws -> [Entry] {
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "zip-memory-read")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        var entries: [Entry] = []
        try scan(fileURL: url, limits: limits) { entry, read, _ in
            entries.append(Entry(path: entry.path, data: try read()))
        }
        return entries
    }

    static func scan(
        fileURL: URL,
        limits: BackupArchiveLimits = .inMemory,
        verifyAllEntries: Bool = false,
        shouldCancel: (() -> Bool)? = nil,
        onProgress: ((Int64, Int64, String) -> Void)? = nil,
        onEntry: (ScanEntry, () throws -> Data, (URL) throws -> Void) throws -> Void
    ) throws {
        if shouldCancel?() == true { throw ZipReadError.cancelled }
        let expectedCount = try ZipArchiveEnvelope.entryCount(at: fileURL)
        guard expectedCount <= UInt64(max(limits.maximumEntryCount, 0)) else {
            throw ZipReadError.limitExceeded("文件数量过多")
        }
        let archive: Archive
        do { archive = try Archive(url: fileURL, accessMode: .read, pathEncoding: nil) } catch { throw ZipReadError.invalidArchive }
        let (entries, total) = try validatedEntries(in: archive, expectedCount: expectedCount, limits: limits, shouldCancel: shouldCancel)
        var completed: Int64 = 0
        for entry in entries where entry.type == .file {
            var consumed = false
            try onEntry(
                ScanEntry(path: entry.path, dataSize: Int(entry.uncompressedSize)),
                {
                    var data = Data()
                    try extract(entry, from: archive, shouldCancel: shouldCancel) { data.append($0) }
                    consumed = true
                    return data
                },
                { destination in
                    try write(entry, from: archive, to: destination, shouldCancel: shouldCancel)
                    consumed = true
                }
            )
            if verifyAllEntries && !consumed {
                try extract(entry, from: archive, shouldCancel: shouldCancel) { _ in }
            }
            completed += Int64(entry.uncompressedSize)
            onProgress?(completed, Int64(total), entry.path)
        }
    }

    private static func validatedEntries(
        in archive: Archive, expectedCount: UInt64, limits: BackupArchiveLimits, shouldCancel: (() -> Bool)?
    ) throws -> ([ZIPFoundation.Entry], UInt64) {
        var paths = Set<String>()
        var total: UInt64 = 0
        var entries: [ZIPFoundation.Entry] = []
        // Validate the entire index before exposing any payload to a restore stage.
        for entry in archive {
            if shouldCancel?() == true { throw ZipReadError.cancelled }
            try validateArchivePath(entry.path)
            guard paths.insert(entry.path).inserted else { throw ZipReadError.duplicateEntry(entry.path) }
            guard entry.type != .symlink else { throw ZipReadError.unsafePath(entry.path) }
            try limits.validate(path: entry.path, size: entry.uncompressedSize, entryCount: entries.count + 1, total: &total)
            guard entry.compressedSize <= limits.maximumEntryBytes else { throw ZipReadError.limitExceeded(entry.path) }
            guard entry.uncompressedSize <= UInt64(Int.max), total <= UInt64(Int64.max) else { throw ZipReadError.limitExceeded(entry.path) }
            entries.append(entry)
        }
        // The upstream iterator stops at malformed/encrypted headers; never accept a partial index.
        guard UInt64(entries.count) == expectedCount, entries.contains(where: { $0.type == .file }) else {
            throw ZipReadError.invalidArchive
        }
        return (entries, total)
    }

    static func validateArchivePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= Int(UInt16.max), !path.contains("\0") else { throw ZipReadError.invalidFileName }
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":") else { throw ZipReadError.unsafePath(path) }
        var parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if path.hasSuffix("/") { parts.removeLast() }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ZipReadError.unsafePath(path)
        }
    }

    private static func extract(
        _ entry: ZIPFoundation.Entry, from archive: Archive, shouldCancel: (() -> Bool)?, consumer: (Data) throws -> Void
    ) throws {
        var written: UInt64 = 0
        let checksum = try archive.extract(entry, bufferSize: 256 * 1024) { chunk in
            if shouldCancel?() == true { throw ZipReadError.cancelled }
            let (next, overflow) = written.addingReportingOverflow(UInt64(chunk.count))
            guard !overflow, next <= entry.uncompressedSize else { throw ZipReadError.limitExceeded(entry.path) }
            written = next
            try consumer(chunk)
        }
        guard written == entry.uncompressedSize else { throw ZipReadError.invalidArchive }
        guard checksum == entry.checksum else { throw ZipReadError.checksumMismatch(entry.path) }
    }

    private static func write(
        _ entry: ZIPFoundation.Entry, from archive: Archive, to destination: URL, shouldCancel: (() -> Bool)?
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".zip-extract-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw ZipReadError.invalidArchive }
        let output = try FileHandle(forWritingTo: temporary)
        do {
            try extract(entry, from: archive, shouldCancel: shouldCancel) { try output.write(contentsOf: $0) }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }
}
