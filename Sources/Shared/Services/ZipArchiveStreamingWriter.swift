import Foundation

enum StreamingZipArchiveWriterError: LocalizedError {
    case invalidPath(String)
    case writerClosed
    case sourceFileMissing(String)
    case writeSizeMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "ZIP 路径无效：\(path)"
        case .writerClosed:
            return "ZIP 写入器已关闭。"
        case .sourceFileMissing(let name):
            return "源文件不存在：\(name)"
        case .writeSizeMismatch(let expected, let actual):
            return "ZIP 写入大小不一致（预期 \(expected) 字节，实际 \(actual) 字节）。"
        }
    }
}

struct StreamingZipArchiveWriter {
    private struct Entry {
        let path: String
        let size: UInt64
        let crc32: UInt32
        let offset: UInt64
        let dos: StreamingDOSDateTime
    }

    let fileURL: URL
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private var outputHandle: FileHandle?

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        outputHandle = try FileHandle(forWritingTo: fileURL)
    }

    static func makeTemporaryFileURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).zip")
    }

    mutating func addFile(path: String, data: Data) throws {
        let pathData = try normalizedPathData(path)
        let size = UInt64(data.count)
        let localOffset = offset
        let dos = StreamingDOSDateTime.now()
        let crc32 = StreamingCRC32.calculate(data)
        let localExtra = zip64LocalExtra(size: size)

        try write(localHeader(pathLength: pathData.count, extraLength: localExtra.count, crc32: crc32, size: size, dos: dos))
        try write(pathData)
        try write(localExtra)
        try write(data)

        entries.append(Entry(path: path, size: size, crc32: crc32, offset: localOffset, dos: dos))
    }

    mutating func addFile(path: String, sourceFileURL: URL) throws {
        let pathData = try normalizedPathData(path)
        guard FileManager.default.fileExists(atPath: sourceFileURL.path) else {
            throw StreamingZipArchiveWriterError.sourceFileMissing(sourceFileURL.lastPathComponent)
        }

        let size = try sourceFileSize(for: sourceFileURL)
        let localOffset = offset
        let dos = StreamingDOSDateTime.now()
        let localExtra = zip64LocalExtra(size: size)
        try write(localHeader(pathLength: pathData.count, extraLength: localExtra.count, crc32: 0, size: size, dos: dos))
        try write(pathData)
        try write(localExtra)

        let (crc32, written) = try copySourceFileData(from: sourceFileURL)
        guard written == size else {
            throw StreamingZipArchiveWriterError.writeSizeMismatch(expected: Int(clamping: size), actual: Int(clamping: written))
        }
        try patchLocalHeaderCRC32(crc32, localOffset: localOffset)

        entries.append(Entry(path: path, size: size, crc32: crc32, offset: localOffset, dos: dos))
    }

    mutating func finish() throws -> URL {
        let centralStart = offset
        for entry in entries {
            let pathData = try normalizedPathData(entry.path)
            let centralExtra = zip64CentralExtra(size: entry.size, offset: entry.offset)
            try write(
                centralHeader(
                    pathLength: pathData.count,
                    extraLength: centralExtra.count,
                    crc32: entry.crc32,
                    size: entry.size,
                    dos: entry.dos,
                    localOffset: entry.offset
                )
            )
            try write(pathData)
            try write(centralExtra)
        }
        let centralEnd = offset
        let centralSize = centralEnd - centralStart
        let needsZip64 = requiresZip64(
            entryCount: entries.count,
            centralSize: centralSize,
            centralOffset: centralStart
        )
        if needsZip64 {
            let zip64EndOffset = offset
            try write(zip64EndOfCentralDirectory(entryCount: UInt64(entries.count), centralSize: centralSize, centralOffset: centralStart))
            try write(zip64EndOfCentralDirectoryLocator(zip64EndOffset: zip64EndOffset))
        }
        try write(endOfCentralDirectory(entryCount: entries.count, centralSize: centralSize, centralOffset: centralStart, useZip64: needsZip64))
        try close()
        return fileURL
    }

    mutating func close() throws {
        if let handle = outputHandle {
            try handle.close()
            outputHandle = nil
        }
    }

    private mutating func copySourceFileData(from sourceFileURL: URL) throws -> (crc32: UInt32, written: UInt64) {
        let input = try FileHandle(forReadingFrom: sourceFileURL)
        defer {
            try? input.close()
        }
        let chunkSize = 256 * 1024
        var crc = StreamingCRC32()
        var total: UInt64 = 0
        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                break
            }
            crc.update(chunk)
            total += UInt64(chunk.count)
            try write(chunk)
        }
        return (crc.finalValue, total)
    }

    private func sourceFileSize(for sourceFileURL: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceFileURL.path)
        if let size = attributes[.size] as? NSNumber {
            return size.uint64Value
        }
        return UInt64(QuickNoteAttachmentStorage.fileSize(at: sourceFileURL))
    }

    private mutating func patchLocalHeaderCRC32(_ crc32: UInt32, localOffset: UInt64) throws {
        guard let outputHandle else {
            throw StreamingZipArchiveWriterError.writerClosed
        }
        let endOffset = offset
        try outputHandle.seek(toOffset: localOffset + 14)
        try outputHandle.write(contentsOf: uint32Data(crc32))
        try outputHandle.seek(toOffset: endOffset)
    }

    private mutating func write(_ data: Data) throws {
        guard let outputHandle else {
            throw StreamingZipArchiveWriterError.writerClosed
        }
        try outputHandle.write(contentsOf: data)
        offset += UInt64(data.count)
    }

    private func normalizedPathData(_ path: String) throws -> Data {
        guard !path.isEmpty, let pathData = path.data(using: .utf8), pathData.count <= Int(UInt16.max) else {
            throw StreamingZipArchiveWriterError.invalidPath(path)
        }
        return pathData
    }

    private func localHeader(pathLength: Int, extraLength: Int, crc32: UInt32, size: UInt64, dos: StreamingDOSDateTime) -> Data {
        let useZip64 = size > UInt64(UInt32.max)
        let size32 = useZip64 ? UInt32.max : UInt32(size)
        var data = Data()
        LEData.appendUInt32(0x04034b50, to: &data)
        LEData.appendUInt16(useZip64 ? 45 : 20, to: &data)
        LEData.appendUInt16(0x0800, to: &data) // UTF-8
        LEData.appendUInt16(0, to: &data) // store mode
        LEData.appendUInt16(dos.time, to: &data)
        LEData.appendUInt16(dos.date, to: &data)
        LEData.appendUInt32(crc32, to: &data)
        LEData.appendUInt32(size32, to: &data)
        LEData.appendUInt32(size32, to: &data)
        LEData.appendUInt16(UInt16(pathLength), to: &data)
        LEData.appendUInt16(UInt16(extraLength), to: &data)
        return data
    }

    private func centralHeader(pathLength: Int, extraLength: Int, crc32: UInt32, size: UInt64, dos: StreamingDOSDateTime, localOffset: UInt64) -> Data {
        let sizeNeedsZip64 = size > UInt64(UInt32.max)
        let offsetNeedsZip64 = localOffset > UInt64(UInt32.max)
        let useZip64 = sizeNeedsZip64 || offsetNeedsZip64
        let size32 = sizeNeedsZip64 ? UInt32.max : UInt32(size)
        let offset32 = offsetNeedsZip64 ? UInt32.max : UInt32(localOffset)
        var data = Data()
        LEData.appendUInt32(0x02014b50, to: &data)
        LEData.appendUInt16(useZip64 ? 45 : 20, to: &data)
        LEData.appendUInt16(useZip64 ? 45 : 20, to: &data)
        LEData.appendUInt16(0x0800, to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt16(dos.time, to: &data)
        LEData.appendUInt16(dos.date, to: &data)
        LEData.appendUInt32(crc32, to: &data)
        LEData.appendUInt32(size32, to: &data)
        LEData.appendUInt32(size32, to: &data)
        LEData.appendUInt16(UInt16(pathLength), to: &data)
        LEData.appendUInt16(UInt16(extraLength), to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt32(0, to: &data)
        LEData.appendUInt32(offset32, to: &data)
        return data
    }

    private func zip64LocalExtra(size: UInt64) -> Data {
        guard size > UInt64(UInt32.max) else { return Data() }
        var data = Data()
        LEData.appendUInt16(0x0001, to: &data)
        LEData.appendUInt16(16, to: &data)
        LEData.appendUInt64(size, to: &data)
        LEData.appendUInt64(size, to: &data)
        return data
    }

    private func zip64CentralExtra(size: UInt64, offset: UInt64) -> Data {
        let sizeNeedsZip64 = size > UInt64(UInt32.max)
        let offsetNeedsZip64 = offset > UInt64(UInt32.max)
        guard sizeNeedsZip64 || offsetNeedsZip64 else { return Data() }
        var payload = Data()
        if sizeNeedsZip64 {
            LEData.appendUInt64(size, to: &payload)
            LEData.appendUInt64(size, to: &payload)
        }
        if offsetNeedsZip64 {
            LEData.appendUInt64(offset, to: &payload)
        }
        var data = Data()
        LEData.appendUInt16(0x0001, to: &data)
        LEData.appendUInt16(UInt16(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private func requiresZip64(entryCount: Int, centralSize: UInt64, centralOffset: UInt64) -> Bool {
        entryCount > Int(UInt16.max)
            || centralSize > UInt64(UInt32.max)
            || centralOffset > UInt64(UInt32.max)
    }

    static func requiresZip64ForTesting(entrySize: UInt64, entryOffset: UInt64, entryCount: Int, centralSize: UInt64, centralOffset: UInt64) -> Bool {
        entrySize > UInt64(UInt32.max)
            || entryOffset > UInt64(UInt32.max)
            || entryCount > Int(UInt16.max)
            || centralSize > UInt64(UInt32.max)
            || centralOffset > UInt64(UInt32.max)
    }

    private func zip64EndOfCentralDirectory(entryCount: UInt64, centralSize: UInt64, centralOffset: UInt64) -> Data {
        var data = Data()
        LEData.appendUInt32(0x06064b50, to: &data)
        LEData.appendUInt64(44, to: &data)
        LEData.appendUInt16(45, to: &data)
        LEData.appendUInt16(45, to: &data)
        LEData.appendUInt32(0, to: &data)
        LEData.appendUInt32(0, to: &data)
        LEData.appendUInt64(entryCount, to: &data)
        LEData.appendUInt64(entryCount, to: &data)
        LEData.appendUInt64(centralSize, to: &data)
        LEData.appendUInt64(centralOffset, to: &data)
        return data
    }

    private func zip64EndOfCentralDirectoryLocator(zip64EndOffset: UInt64) -> Data {
        var data = Data()
        LEData.appendUInt32(0x07064b50, to: &data)
        LEData.appendUInt32(0, to: &data)
        LEData.appendUInt64(zip64EndOffset, to: &data)
        LEData.appendUInt32(1, to: &data)
        return data
    }

    private func endOfCentralDirectory(entryCount: Int, centralSize: UInt64, centralOffset: UInt64, useZip64: Bool) -> Data {
        var data = Data()
        LEData.appendUInt32(0x06054b50, to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt16(0, to: &data)
        LEData.appendUInt16(useZip64 ? UInt16.max : UInt16(clamping: entryCount), to: &data)
        LEData.appendUInt16(useZip64 ? UInt16.max : UInt16(clamping: entryCount), to: &data)
        LEData.appendUInt32(useZip64 ? UInt32.max : UInt32(clamping: centralSize), to: &data)
        LEData.appendUInt32(useZip64 ? UInt32.max : UInt32(clamping: centralOffset), to: &data)
        LEData.appendUInt16(0, to: &data)
        return data
    }

    private func uint32Data(_ value: UInt32) -> Data {
        var data = Data()
        LEData.appendUInt32(value, to: &data)
        return data
    }
}

private struct StreamingDOSDateTime {
    let date: UInt16
    let time: UInt16

    static func now() -> StreamingDOSDateTime {
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
        return StreamingDOSDateTime(date: dosDate, time: dosTime)
    }
}

private struct StreamingCRC32 {
    private var crc: UInt32 = 0xFFFF_FFFF

    mutating func update(_ data: Data) {
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
    }

    var finalValue: UInt32 {
        crc ^ 0xFFFF_FFFF
    }

    static func calculate(_ data: Data) -> UInt32 {
        var stream = StreamingCRC32()
        stream.update(data)
        return stream.finalValue
    }
}

private enum LEData {
    static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            data.append(contentsOf: buffer)
        }
    }

    static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            data.append(contentsOf: buffer)
        }
    }

    static func appendUInt64(_ value: UInt64, to data: inout Data) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { buffer in
            data.append(contentsOf: buffer)
        }
    }
}
