import Foundation

struct SimpleZipArchiveBuilder {
    private struct Entry {
        let path: String
        let size: Int
        let crc32: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var blob = Data()

    mutating func addFile(path: String, data: Data) {
        guard let pathData = path.data(using: .utf8) else { return }
        let offset = UInt32(clamping: blob.count)
        let crc = CRC32.calculate(data)
        let dos = DOSDateTime.now()
        appendLocalHeader(pathLength: UInt16(pathData.count), crc32: crc, size: UInt32(clamping: data.count), dos: dos)
        blob.append(pathData)
        blob.append(data)
        entries.append(Entry(path: path, size: data.count, crc32: crc, offset: offset))
    }

    mutating func build() -> Data {
        let centralStart = UInt32(clamping: blob.count)
        let dos = DOSDateTime.now()
        for entry in entries {
            guard let pathData = entry.path.data(using: .utf8) else { continue }
            appendCentralHeader(
                pathLength: UInt16(pathData.count),
                crc32: entry.crc32,
                size: UInt32(clamping: entry.size),
                dos: dos,
                localOffset: entry.offset
            )
            blob.append(pathData)
        }
        let centralSize = UInt32(clamping: blob.count) - centralStart
        appendEndOfCentralDirectory(entryCount: UInt16(clamping: entries.count), centralSize: centralSize, centralOffset: centralStart)
        return blob
    }

    private mutating func appendLocalHeader(pathLength: UInt16, crc32: UInt32, size: UInt32, dos: DOSDateTime) {
        blob.appendLE(UInt32(0x04034b50))
        blob.appendLE(UInt16(20))
        blob.appendLE(UInt16(0x0800)) // UTF-8 filename
        blob.appendLE(UInt16(0)) // store mode
        blob.appendLE(dos.time)
        blob.appendLE(dos.date)
        blob.appendLE(crc32)
        blob.appendLE(size)
        blob.appendLE(size)
        blob.appendLE(pathLength)
        blob.appendLE(UInt16(0))
    }

    private mutating func appendCentralHeader(pathLength: UInt16, crc32: UInt32, size: UInt32, dos: DOSDateTime, localOffset: UInt32) {
        blob.appendLE(UInt32(0x02014b50))
        blob.appendLE(UInt16(20))
        blob.appendLE(UInt16(20))
        blob.appendLE(UInt16(0x0800)) // UTF-8 filename
        blob.appendLE(UInt16(0))
        blob.appendLE(dos.time)
        blob.appendLE(dos.date)
        blob.appendLE(crc32)
        blob.appendLE(size)
        blob.appendLE(size)
        blob.appendLE(pathLength)
        blob.appendLE(UInt16(0))
        blob.appendLE(UInt16(0))
        blob.appendLE(UInt16(0))
        blob.appendLE(UInt16(0))
        blob.appendLE(UInt32(0))
        blob.appendLE(localOffset)
    }

    private mutating func appendEndOfCentralDirectory(entryCount: UInt16, centralSize: UInt32, centralOffset: UInt32) {
        blob.appendLE(UInt32(0x06054b50))
        blob.appendLE(UInt16(0))
        blob.appendLE(UInt16(0))
        blob.appendLE(entryCount)
        blob.appendLE(entryCount)
        blob.appendLE(centralSize)
        blob.appendLE(centralOffset)
        blob.appendLE(UInt16(0))
    }
}

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
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                return "备份 ZIP 结构不正确。"
            case .unsupportedCompression:
                return "备份 ZIP 使用了当前不支持的压缩方式。"
            case .unsupportedDataDescriptor:
                return "备份 ZIP 使用了当前不支持的数据描述符。"
            case .invalidFileName:
                return "备份 ZIP 内存在无法识别的文件名。"
            case .cancelled:
                return "已取消导入。"
            }
        }
    }

    static func read(_ data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        var offset = 0
        while offset + 4 <= data.count {
            let signature = try data.uint32LE(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else { throw ZipReadError.invalidArchive }

            let flags = try data.uint16LE(at: offset + 6)
            let method = try data.uint16LE(at: offset + 8)
            let compressedSize = Int(try data.uint32LE(at: offset + 18))
            let nameLength = Int(try data.uint16LE(at: offset + 26))
            let extraLength = Int(try data.uint16LE(at: offset + 28))
            guard method == 0 else { throw ZipReadError.unsupportedCompression }
            guard flags & 0x0008 == 0 else { throw ZipReadError.unsupportedDataDescriptor }

            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            let fileStart = nameEnd + extraLength
            let fileEnd = fileStart + compressedSize
            guard fileEnd <= data.count else { throw ZipReadError.invalidArchive }
            guard let path = String(data: data.slice(from: nameStart, count: nameLength), encoding: .utf8) else {
                throw ZipReadError.invalidFileName
            }
            if !path.hasSuffix("/") {
                entries.append(Entry(path: path, data: data.slice(from: fileStart, count: compressedSize)))
            }
            offset = fileEnd
        }
        guard !entries.isEmpty else { throw ZipReadError.invalidArchive }
        return entries
    }

    static func scan(
        fileURL: URL,
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
                StorageIssueLog.record("ZIP 扫描句柄关闭失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }

        var offset: UInt64 = 0
        var entryCount = 0
        while true {
            if shouldCancel?() == true {
                throw ZipReadError.cancelled
            }

            try handle.seek(toOffset: offset)
            let signatureData = try readExactly(from: handle, count: 4)
            if signatureData.isEmpty {
                break
            }
            guard signatureData.count == 4 else { throw ZipReadError.invalidArchive }

            let signature = try signatureData.uint32LE(at: 0)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else { throw ZipReadError.invalidArchive }

            let header = try readExactly(from: handle, count: 26)
            guard header.count == 26 else { throw ZipReadError.invalidArchive }
            let flags = try header.uint16LE(at: 2)
            let method = try header.uint16LE(at: 4)
            let compressedSize32 = try header.uint32LE(at: 14)
            let uncompressedSize32 = try header.uint32LE(at: 18)
            let nameLength = Int(try header.uint16LE(at: 22))
            let extraLength = Int(try header.uint16LE(at: 24))

            guard method == 0 else { throw ZipReadError.unsupportedCompression }
            guard flags & 0x0008 == 0 else { throw ZipReadError.unsupportedDataDescriptor }

            let nameData = try readExactly(from: handle, count: nameLength)
            guard nameData.count == nameLength else { throw ZipReadError.invalidArchive }
            guard let path = String(data: nameData, encoding: .utf8) else {
                throw ZipReadError.invalidFileName
            }

            let extra = try readExactly(from: handle, count: extraLength)
            guard extra.count == extraLength else { throw ZipReadError.invalidArchive }
            let compressedSize = try resolvedCompressedSize(
                compressedSize32: compressedSize32,
                uncompressedSize32: uncompressedSize32,
                extra: extra
            )
            guard compressedSize <= UInt64(Int.max) else { throw ZipReadError.invalidArchive }

            let dataOffset = offset + UInt64(30 + nameLength + extraLength)
            let nextOffset = dataOffset + compressedSize

            if !path.hasSuffix("/") {
                let dataSize = Int(compressedSize)
                let entry = ScanEntry(path: path, dataSize: dataSize)
                try onEntry(
                    entry,
                    {
                        if shouldCancel?() == true {
                            throw ZipReadError.cancelled
                        }
                        let readHandle = try FileHandle(forReadingFrom: fileURL)
                        defer {
                            do {
                                try readHandle.close()
                            } catch {
                                StorageIssueLog.record("ZIP 条目读取句柄关闭失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                            }
                        }
                        try readHandle.seek(toOffset: dataOffset)
                        let data = try readExactly(from: readHandle, count: dataSize)
                        guard data.count == dataSize else { throw ZipReadError.invalidArchive }
                        return data
                    },
                    { destinationURL in
                        try writeEntry(
                            from: fileURL,
                            dataOffset: dataOffset,
                            dataSize: compressedSize,
                            to: destinationURL,
                            shouldCancel: shouldCancel
                        )
                    }
                )
                entryCount += 1
            }

            offset = nextOffset
            onProgress?(Int64(min(offset, UInt64(totalBytes))), totalBytes, path)
        }

        guard entryCount > 0 else { throw ZipReadError.invalidArchive }
    }

    private static func readExactly(from handle: FileHandle, count: Int) throws -> Data {
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

    private static func writeEntry(
        from archiveURL: URL,
        dataOffset: UInt64,
        dataSize: UInt64,
        to destinationURL: URL,
        shouldCancel: (() -> Bool)?
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destinationURL.path) {
            try manager.removeItem(at: destinationURL)
        }

        guard manager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ZipReadError.invalidArchive
        }

        let readHandle = try FileHandle(forReadingFrom: archiveURL)
        let writeHandle = try FileHandle(forWritingTo: destinationURL)
        defer {
            do {
                try readHandle.close()
            } catch {
                StorageIssueLog.record("ZIP 读取句柄关闭失败：\(archiveURL.lastPathComponent)，\(error.localizedDescription)")
            }
            do {
                try writeHandle.close()
            } catch {
                StorageIssueLog.record("ZIP 写入句柄关闭失败：\(destinationURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }

        try readHandle.seek(toOffset: dataOffset)
        var remaining = dataSize
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
            remaining -= UInt64(chunk.count)
        }
    }

    private static func resolvedCompressedSize(compressedSize32: UInt32, uncompressedSize32: UInt32, extra: Data) throws -> UInt64 {
        guard compressedSize32 == UInt32.max || uncompressedSize32 == UInt32.max else {
            return UInt64(compressedSize32)
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
                return compressedSize ?? uncompressedSize ?? UInt64(compressedSize32)
            }
            offset = dataEnd
        }
        throw ZipReadError.invalidArchive
    }
}

private struct DOSDateTime {
    let date: UInt16
    let time: UInt16

    static func now() -> DOSDateTime {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, comps.year ?? 1980)
        let month = max(1, min(12, comps.month ?? 1))
        let day = max(1, min(31, comps.day ?? 1))
        let hour = max(0, min(23, comps.hour ?? 0))
        let minute = max(0, min(59, comps.minute ?? 0))
        let second = max(0, min(59, comps.second ?? 0))
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return DOSDateTime(date: dosDate, time: dosTime)
    }
}

private enum CRC32 {
    static func calculate(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                if (value & 1) != 0 {
                    value = (value >> 1) ^ 0xEDB8_8320
                } else {
                    value >>= 1
                }
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            append(contentsOf: buffer)
        }
    }

    mutating func appendLE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            append(contentsOf: buffer)
        }
    }

    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let i0 = index(startIndex, offsetBy: offset)
        let i1 = index(after: i0)
        return UInt16(self[i0]) | (UInt16(self[i1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let i0 = index(startIndex, offsetBy: offset)
        let i1 = index(after: i0)
        let i2 = index(after: i1)
        let i3 = index(after: i2)
        return UInt32(self[i0])
            | (UInt32(self[i1]) << 8)
            | (UInt32(self[i2]) << 16)
            | (UInt32(self[i3]) << 24)
    }

    func uint64LE(at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        var value: UInt64 = 0
        for indexOffset in 0..<8 {
            let i = index(startIndex, offsetBy: offset + indexOffset)
            value |= UInt64(self[i]) << UInt64(indexOffset * 8)
        }
        return value
    }

    func slice(from offset: Int, count length: Int) -> Data {
        let start = index(startIndex, offsetBy: offset)
        let end = index(start, offsetBy: length)
        return Data(self[start..<end])
    }
}
