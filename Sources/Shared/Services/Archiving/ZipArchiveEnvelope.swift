import Foundation

/// A small completeness gate around ZIPFoundation's non-throwing entry iterator.
/// ZIP payloads, compression, CRCs, entry headers and ZIP64 writing belong to the library.
enum ZipArchiveEnvelope {
    static func entryCount(at url: URL) throws -> UInt64 {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 22 else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let tailSize = Int(min(size, 22 + UInt64(UInt16.max)))
        try file.seek(toOffset: size - UInt64(tailSize))
        let tail = try file.read(upToCount: tailSize) ?? Data()
        for offset in stride(from: tail.count - 22, through: 0, by: -1) {
            guard number(tail, at: offset, bytes: 4) == 0x06054b50,
                  offset + 22 + Int(number(tail, at: offset + 20, bytes: 2)) == tail.count else { continue }
            guard number(tail, at: offset + 4, bytes: 2) == 0,
                  number(tail, at: offset + 6, bytes: 2) == 0 else { break }
            let count = number(tail, at: offset + 10, bytes: 2)
            guard count == number(tail, at: offset + 8, bytes: 2) else { break }
            let endOffset = size - UInt64(tail.count - offset)
            if count != UInt64(UInt16.max),
               number(tail, at: offset + 12, bytes: 4) != UInt64(UInt32.max),
               number(tail, at: offset + 16, bytes: 4) != UInt64(UInt32.max) {
                return count
            }
            return try zip64EntryCount(file: file, endOffset: endOffset)
        }
        throw SimpleZipArchiveReader.ZipReadError.invalidArchive
    }

    private static func zip64EntryCount(file: FileHandle, endOffset: UInt64) throws -> UInt64 {
        // ZIP64 locator immediately precedes the ordinary end record.
        guard endOffset >= 20 else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        try file.seek(toOffset: endOffset - 20)
        let locator = try file.read(upToCount: 20) ?? Data()
        guard locator.count == 20, number(locator, at: 0, bytes: 4) == 0x07064b50,
              number(locator, at: 4, bytes: 4) == 0, number(locator, at: 16, bytes: 4) == 1 else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        let recordOffset = number(locator, at: 8, bytes: 8)
        guard recordOffset <= endOffset - 20, endOffset - 20 - recordOffset >= 56 else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        try file.seek(toOffset: recordOffset)
        let record = try file.read(upToCount: 56) ?? Data()
        guard record.count == 56, number(record, at: 0, bytes: 4) == 0x06064b50,
              number(record, at: 4, bytes: 8) >= 44,
              number(record, at: 16, bytes: 4) == 0, number(record, at: 20, bytes: 4) == 0,
              number(record, at: 24, bytes: 8) == number(record, at: 32, bytes: 8) else { throw SimpleZipArchiveReader.ZipReadError.invalidArchive }
        return number(record, at: 32, bytes: 8)
    }

    private static func number(_ data: Data, at offset: Int, bytes: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<bytes { value |= UInt64(data[offset + index]) << (index * 8) }
        return value
    }
}
