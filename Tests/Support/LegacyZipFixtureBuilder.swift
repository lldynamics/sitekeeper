// Test-only legacy ZIP generator for fixed-format and malformed-archive regressions.
import Foundation
@testable import sitekeeper

struct SimpleZipArchiveBuilder {
    struct Entry {
        let path: String
        let size: Int
        let crc32: UInt32
        let offset: UInt32
    }

    var entries: [Entry] = []
    var blob = Data()

    mutating func addFile(path: String, data: Data) {
        guard let normalizedPath = normalizedArchivePath(path),
              let pathData = normalizedPath.data(using: .utf8) else {
            return
        }
        let offset = UInt32(clamping: blob.count)
        let crc = CRC32.calculate(data)
        let dos = DOSDateTime.now()
        appendLocalHeader(pathLength: UInt16(pathData.count), crc32: crc, size: UInt32(clamping: data.count), dos: dos)
        blob.append(pathData)
        blob.append(data)
        entries.append(Entry(path: normalizedPath, size: data.count, crc32: crc, offset: offset))
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

    private func normalizedArchivePath(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        guard path.utf8.count <= Int(UInt16.max) else { return nil }
        guard !path.hasPrefix("/") else { return nil }
        guard !path.hasPrefix("\\") else { return nil }
        guard !path.contains("\\") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        for part in parts {
            let piece = String(part)
            if piece.isEmpty || piece == "." || piece == ".." {
                return nil
            }
        }
        return path
    }
}
