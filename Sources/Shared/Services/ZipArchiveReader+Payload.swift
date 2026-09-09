import Foundation

extension SimpleZipArchiveReader {
    struct Payload {
        let fileURL: URL
        let path: String
        let dataOffset: UInt64
        let compressedSize: UInt64
        let uncompressedSize: Int
        let method: UInt16
        let expectedCRC32: UInt32
    }

    static func readScanHeader(from handle: FileHandle, fileURL: URL, offset: UInt64, totalBytes: Int64) throws -> Payload? {
        try handle.seek(toOffset: offset)
        let signatureData = try readExactly(from: handle, count: 4)
        if signatureData.isEmpty {
            return nil
        }
        guard signatureData.count == 4 else { throw ZipReadError.invalidArchive }

        let signature = try signatureData.uint32LE(at: 0)
        if signature == 0x02014b50 || signature == 0x06054b50 {
            return nil
        }
        guard signature == 0x04034b50 else { throw ZipReadError.invalidArchive }

        let header = try readRequired(from: handle, count: 26)
        let flags = try header.uint16LE(at: 2)
        let method = try header.uint16LE(at: 4)
        let expectedCRC32 = try header.uint32LE(at: 10)
        let compressedSize32 = try header.uint32LE(at: 14)
        let uncompressedSize32 = try header.uint32LE(at: 18)
        let nameLength = Int(try header.uint16LE(at: 22))
        let extraLength = Int(try header.uint16LE(at: 24))

        guard method == 0 || method == 8 else { throw ZipReadError.unsupportedCompression }
        guard flags & 0x0008 == 0 else { throw ZipReadError.unsupportedDataDescriptor }

        let nameData = try readRequired(from: handle, count: nameLength)
        guard let path = String(data: nameData, encoding: .utf8) else {
            throw ZipReadError.invalidFileName
        }
        try validateArchivePath(path)

        let extra = try readRequired(from: handle, count: extraLength)
        let sizes = try resolvedSizes(
            compressedSize32: compressedSize32,
            uncompressedSize32: uncompressedSize32,
            extra: extra
        )
        let compressedSize = sizes.compressed
        let uncompressedSize = sizes.uncompressed
        guard compressedSize <= UInt64(Int.max),
              uncompressedSize <= UInt64(Int.max) else {
            throw ZipReadError.invalidArchive
        }

        let dataOffset = offset + UInt64(30 + nameLength + extraLength)
        let (nextOffset, overflow) = dataOffset.addingReportingOverflow(compressedSize)
        guard !overflow, nextOffset <= UInt64(totalBytes) else { throw ZipReadError.invalidArchive }

        return Payload(fileURL: fileURL, path: path, dataOffset: dataOffset,
                       compressedSize: compressedSize, uncompressedSize: Int(uncompressedSize),
                       method: method, expectedCRC32: expectedCRC32)
    }

    static func readPayload(_ payload: Payload, shouldCancel: (() -> Bool)?) throws -> Data {
        if shouldCancel?() == true { throw ZipReadError.cancelled }
        let handle = try FileHandle(forReadingFrom: payload.fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: payload.dataOffset)
        let data = try readExactly(from: handle, count: Int(payload.compressedSize))
        guard data.count == Int(payload.compressedSize) else { throw ZipReadError.invalidArchive }
        let decoded = try decodedEntryData(data, method: payload.method, expectedSize: payload.uncompressedSize)
        try validateChecksum(decoded, expectedCRC32: payload.expectedCRC32, path: payload.path)
        return decoded
    }

    static func writePayload(_ payload: Payload, to destinationURL: URL, shouldCancel: (() -> Bool)?) throws {
        if payload.method == 0 {
            try writeEntry(
                from: payload.fileURL, dataOffset: payload.dataOffset,
                dataSize: payload.compressedSize, to: destinationURL,
                expectedCRC32: payload.expectedCRC32, path: payload.path, shouldCancel: shouldCancel
            )
        } else {
            let decoded = try readPayload(payload, shouldCancel: shouldCancel)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try decoded.write(to: destinationURL, options: .atomic)
        }
    }

    static func verifyEntryChecksum(
        fileURL: URL, dataOffset: UInt64, dataSize: UInt64, method: UInt16,
        expectedSize: Int, expectedCRC32: UInt32, path: String, shouldCancel: (() -> Bool)?
    ) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: dataOffset)
        if method == 8 {
            let data = try readExactly(from: handle, count: Int(dataSize))
            let decoded = try decodedEntryData(data, method: method, expectedSize: expectedSize)
            try validateChecksum(decoded, expectedCRC32: expectedCRC32, path: path)
            return
        }
        var remaining = dataSize
        var crc = StreamingCRC32Accumulator()
        while remaining > 0 {
            if shouldCancel?() == true { throw ZipReadError.cancelled }
            let chunk = try handle.read(upToCount: Int(min(remaining, 256 * 1024))) ?? Data()
            guard !chunk.isEmpty else { throw ZipReadError.invalidArchive }
            crc.update(chunk)
            remaining -= UInt64(chunk.count)
        }
        guard crc.finalized == expectedCRC32 else { throw ZipReadError.checksumMismatch(path) }
    }

    private static func readRequired(from handle: FileHandle, count: Int) throws -> Data {
        let data = try readExactly(from: handle, count: count)
        guard data.count == count else { throw ZipReadError.invalidArchive }
        return data
    }
}
