import Foundation

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
                return String(localized: "备份 ZIP 结构不正确。")
            case .unsupportedCompression:
                return String(localized: "备份 ZIP 使用了当前不支持的压缩方式。")
            case .unsupportedDataDescriptor:
                return String(localized: "备份 ZIP 使用了当前不支持的数据描述符。")
            case .invalidFileName:
                return String(localized: "备份 ZIP 内存在无法识别的文件名。")
            case .unsafePath(let path):
                return String(format: String(localized: "备份 ZIP 路径不安全：%@"), path)
            case .duplicateEntry(let path):
                return String(format: String(localized: "备份 ZIP 存在重复文件：%@"), path)
            case .checksumMismatch(let path):
                return String(format: String(localized: "备份 ZIP 文件校验失败：%@"), path)
            case .limitExceeded(let reason):
                return String(format: String(localized: "备份 ZIP 超出安全限制：%@"), reason)
            case .cancelled:
                return String(localized: "已取消导入。")
            }
        }
    }

    private static func recordIssue(
        _ event: String,
        fileURL: URL? = nil,
        path: String? = nil,
        error: Error? = nil
    ) {
        var details: [String: String] = [:]
        if let fileURL {
            details["file"] = fileURL.lastPathComponent
        }
        if let path, !path.isEmpty {
            details["path"] = path
        }
        StorageIssueLog.recordEvent(
            "zip_reader.\(event)",
            category: .zipArchive,
            details: details,
            error: error
        )
    }

    static func read(_ data: Data, limits: BackupArchiveLimits = .inMemory) throws -> [Entry] {
        var entries: [Entry] = []
        var seenPaths = Set<String>()
        var totalUncompressedBytes: UInt64 = 0
        var offset = 0
        while offset + 4 <= data.count {
            let signature = try data.uint32LE(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else { throw ZipReadError.invalidArchive }

            let flags = try data.uint16LE(at: offset + 6)
            let method = try data.uint16LE(at: offset + 8)
            let expectedCRC32 = try data.uint32LE(at: offset + 14)
            let compressedSize = Int(try data.uint32LE(at: offset + 18))
            let nameLength = Int(try data.uint16LE(at: offset + 26))
            let extraLength = Int(try data.uint16LE(at: offset + 28))
            guard method == 0 || method == 8 else { throw ZipReadError.unsupportedCompression }
            guard flags & 0x0008 == 0 else { throw ZipReadError.unsupportedDataDescriptor }

            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            let fileStart = nameEnd + extraLength
            let fileEnd = fileStart + compressedSize
            guard fileEnd <= data.count else { throw ZipReadError.invalidArchive }
            guard let path = String(data: data.slice(from: nameStart, count: nameLength), encoding: .utf8) else {
                throw ZipReadError.invalidFileName
            }
            try validateArchivePath(path)
            if !path.hasSuffix("/") {
                let uncompressedSize = Int(try data.uint32LE(at: offset + 22))
                try limits.validate(
                    path: path,
                    size: UInt64(uncompressedSize),
                    entryCount: entries.count + 1,
                    total: &totalUncompressedBytes
                )
                let compressedData = data.slice(from: fileStart, count: compressedSize)
                let entryData = try decodedEntryData(
                    compressedData,
                    method: method,
                    expectedSize: uncompressedSize
                )
                try validateChecksum(entryData, expectedCRC32: expectedCRC32, path: path)
                guard seenPaths.insert(path).inserted else {
                    throw ZipReadError.duplicateEntry(path)
                }
                entries.append(Entry(path: path, data: entryData))
            }
            offset = fileEnd
        }
        guard !entries.isEmpty else { throw ZipReadError.invalidArchive }
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
        let totalBytes = Int64(max(QuickNoteAttachmentStorage.fileSize(at: fileURL), 1))
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            do {
                try handle.close()
            } catch {
                recordIssue("scan_handle_close_failed", fileURL: fileURL, error: error)
            }
        }

        var offset: UInt64 = 0
        var entryCount = 0
        var totalUncompressedBytes: UInt64 = 0
        var seenPaths = Set<String>()
        while true {
            if shouldCancel?() == true {
                throw ZipReadError.cancelled
            }

            guard let payload = try readScanHeader(from: handle, fileURL: fileURL, offset: offset, totalBytes: totalBytes) else { break }
            let path = payload.path
            if !path.hasSuffix("/") {
                guard seenPaths.insert(path).inserted else {
                    throw ZipReadError.duplicateEntry(path)
                }
                try limits.validate(
                    path: path,
                    size: UInt64(payload.uncompressedSize),
                    entryCount: entryCount + 1,
                    total: &totalUncompressedBytes
                )
                if payload.method == 0, payload.compressedSize != UInt64(payload.uncompressedSize) { throw ZipReadError.invalidArchive }
                guard payload.compressedSize <= limits.maximumEntryBytes else { throw ZipReadError.limitExceeded(path) }
                try onEntry(
                    ScanEntry(path: path, dataSize: payload.uncompressedSize),
                    { try readPayload(payload, shouldCancel: shouldCancel) },
                    { try writePayload(payload, to: $0, shouldCancel: shouldCancel) }
                )
                if verifyAllEntries {
                    try verifyEntryChecksum(
                        fileURL: fileURL, dataOffset: payload.dataOffset, dataSize: payload.compressedSize,
                        method: payload.method, expectedSize: payload.uncompressedSize, expectedCRC32: payload.expectedCRC32,
                        path: path, shouldCancel: shouldCancel
                    )
                }
                entryCount += 1
            }

            offset = payload.dataOffset + payload.compressedSize
            onProgress?(Int64(min(offset, UInt64(totalBytes))), totalBytes, path)
        }

        guard entryCount > 0 else { throw ZipReadError.invalidArchive }
    }
}

extension SimpleZipArchiveReader {
    static func decodedEntryData(_ data: Data, method: UInt16, expectedSize: Int) throws -> Data {
        switch method {
        case 0:
            guard data.count == expectedSize else {
                throw ZipReadError.invalidArchive
            }
            return data
        case 8:
            do {
                let decoded = try (data as NSData).decompressed(using: .zlib) as Data
                guard decoded.count == expectedSize else {
                    throw ZipReadError.invalidArchive
                }
                return decoded
            } catch {
                throw ZipReadError.unsupportedCompression
            }
        default:
            throw ZipReadError.unsupportedCompression
        }
    }

    static func readExactly(from handle: FileHandle, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        while result.count < count {
            let chunk = try handle.read(upToCount: count - result.count) ?? Data()
            if chunk.isEmpty {
                break
            }
            result.append(chunk)
        }
        return result
    }

    static func writeEntry(
        from archiveURL: URL,
        dataOffset: UInt64,
        dataSize: UInt64,
        to destinationURL: URL,
        expectedCRC32: UInt32,
        path: String,
        shouldCancel: (() -> Bool)?
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try FileOps.removeIfExists(
            at: destinationURL,
            context: .init(
                event: "zip.reader.write_entry.prepare_destination",
                category: .zipArchive,
                source: "SimpleZipArchiveReader.writeEntry"
            )
        )

        guard manager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ZipReadError.invalidArchive
        }
        var completed = false
        defer {
            if !completed {
                try? manager.removeItem(at: destinationURL)
            }
        }

        let readHandle = try FileHandle(forReadingFrom: archiveURL)
        let writeHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            do {
                try readHandle.close()
            } catch {
                recordIssue("entry_copy_read_handle_close_failed", fileURL: archiveURL, error: error)
            }
            do {
                try writeHandle.close()
            } catch {
                recordIssue("entry_copy_write_handle_close_failed", fileURL: destinationURL, error: error)
            }
        }

        try readHandle.seek(toOffset: dataOffset)
        var remaining = dataSize
        var checksum = StreamingCRC32Accumulator()
        let chunkSize = 256 * 1024

        while remaining > 0 {
            if shouldCancel?() == true {
                throw ZipReadError.cancelled
            }
            let currentSize = Int(min(remaining, UInt64(chunkSize)))
            let chunk = try readHandle.read(upToCount: currentSize) ?? Data()
            guard !chunk.isEmpty else {
                throw ZipReadError.invalidArchive
            }
            try writeHandle.write(contentsOf: chunk)
            checksum.update(chunk)
            remaining -= UInt64(chunk.count)
        }
        guard checksum.finalized == expectedCRC32 else {
            throw ZipReadError.checksumMismatch(path)
        }
        completed = true
    }

    static func resolvedSizes(
        compressedSize32: UInt32,
        uncompressedSize32: UInt32,
        extra: Data
    ) throws -> (compressed: UInt64, uncompressed: UInt64) {
        guard compressedSize32 == UInt32.max || uncompressedSize32 == UInt32.max else {
            return (UInt64(compressedSize32), UInt64(uncompressedSize32))
        }
        var offset = 0
        while offset + 4 <= extra.count {
            let headerId = try extra.uint16LE(at: offset)
            let dataSize = Int(try extra.uint16LE(at: offset + 2))
            let dataStart = offset + 4
            let dataEnd = dataStart + dataSize
            guard dataEnd <= extra.count else { throw ZipReadError.invalidArchive }
            if headerId == 0x0001 {
                var valueOffset = dataStart
                var uncompressedSize: UInt64?
                var compressedSize: UInt64?
                if uncompressedSize32 == UInt32.max {
                    guard valueOffset + 8 <= dataEnd else { throw ZipReadError.invalidArchive }
                    uncompressedSize = try extra.uint64LE(at: valueOffset)
                    valueOffset += 8
                }
                if compressedSize32 == UInt32.max {
                    guard valueOffset + 8 <= dataEnd else { throw ZipReadError.invalidArchive }
                    compressedSize = try extra.uint64LE(at: valueOffset)
                }
                return (
                    compressedSize ?? UInt64(compressedSize32),
                    uncompressedSize ?? UInt64(uncompressedSize32)
                )
            }
            offset = dataEnd
        }
        throw ZipReadError.invalidArchive
    }

    static func validateChecksum(
        _ data: Data,
        expectedCRC32: UInt32,
        path: String
    ) throws {
        guard CRC32.calculate(data) == expectedCRC32 else {
            throw ZipReadError.checksumMismatch(path)
        }
    }

    static func validateArchivePath(_ path: String) throws {
        guard !path.isEmpty else {
            throw ZipReadError.invalidFileName
        }
        guard !path.hasPrefix("/") else {
            throw ZipReadError.unsafePath(path)
        }
        guard !path.hasPrefix("\\") else {
            throw ZipReadError.unsafePath(path)
        }
        guard !path.contains("\\") else {
            throw ZipReadError.unsafePath(path)
        }
        let isDirectory = path.hasSuffix("/")
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if isDirectory {
            guard parts.last == "" else {
                throw ZipReadError.unsafePath(path)
            }
            parts.removeLast()
        }
        guard !parts.isEmpty else {
            throw ZipReadError.invalidFileName
        }
        for part in parts {
            if part.isEmpty || part == "." || part == ".." {
                throw ZipReadError.unsafePath(path)
            }
        }
    }
}

struct StreamingCRC32Accumulator {
    private var value: UInt32 = 0

    mutating func update(_ data: Data) {
        value = CRC32.updating(value, with: data)
    }

    var finalized: UInt32 { value }
}
