import Testing
import Foundation
@testable import sitekeeper

@MainActor
enum BackupArchiveValidationTestSupport {
    static func makeValidBackupMetadataData() throws -> Data {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "恶意 ZIP 测试项目", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        return try JSONEncoder().encode(snapshot)
    }

    static func archiveDataByReplacingPath(
        _ oldPath: String,
        with newPath: String,
        in data: Data
    ) throws -> Data {
        let oldBytes = Array(oldPath.utf8)
        let newBytes = Array(newPath.utf8)
        #expect(oldBytes.count == newBytes.count)
        guard oldBytes.count == newBytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }

        var bytes = Array(data)
        var index = 0
        var replacementCount = 0
        while index + oldBytes.count <= bytes.count {
            if Array(bytes[index..<(index + oldBytes.count)]) == oldBytes {
                bytes.replaceSubrange(index..<(index + oldBytes.count), with: newBytes)
                replacementCount += 1
                index += newBytes.count
            } else {
                index += 1
            }
        }
        #expect(replacementCount >= 2)
        guard replacementCount >= 2 else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        return Data(bytes)
    }

    static func archiveDataByCorruptingPayload(
        for path: String,
        in data: Data
    ) throws -> Data {
        var bytes = Array(data)
        let headerOffset = try localHeaderOffset(for: path, in: bytes)
        let nameLength = Int(try data.uint16LE(at: headerOffset + 26))
        let extraLength = Int(try data.uint16LE(at: headerOffset + 28))
        let payloadOffset = headerOffset + 30 + nameLength + extraLength
        guard payloadOffset < bytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        bytes[payloadOffset] ^= 0xFF
        return Data(bytes)
    }

    static func archiveDataByReplacingLocalUncompressedSize(
        for path: String,
        with size: UInt32,
        in data: Data
    ) throws -> Data {
        var bytes = Array(data)
        let headerOffset = try localHeaderOffset(for: path, in: bytes)
        let valueOffset = headerOffset + 22
        guard valueOffset + 4 <= bytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        bytes[valueOffset] = UInt8(truncatingIfNeeded: size)
        bytes[valueOffset + 1] = UInt8(truncatingIfNeeded: size >> 8)
        bytes[valueOffset + 2] = UInt8(truncatingIfNeeded: size >> 16)
        bytes[valueOffset + 3] = UInt8(truncatingIfNeeded: size >> 24)
        let name = Array(path.utf8)
        for offset in 0..<max(0, bytes.count - 46 - name.count + 1) {
            guard Array(bytes[offset..<(offset + 4)]) == [0x50, 0x4B, 0x01, 0x02],
                  Array(bytes[(offset + 46)..<(offset + 46 + name.count)]) == name else { continue }
            for index in 0..<4 { bytes[offset + 24 + index] = UInt8(truncatingIfNeeded: size >> (index * 8)) }
        }
        return Data(bytes)
    }

    private static func localHeaderOffset(for path: String, in bytes: [UInt8]) throws -> Int {
        let pathBytes = Array(path.utf8)
        guard let pathOffset = bytes.indices.first(where: { index in
            guard index + pathBytes.count <= bytes.count else { return false }
            return Array(bytes[index..<(index + pathBytes.count)]) == pathBytes
        }) else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        let headerOffset = pathOffset - 30
        guard headerOffset >= 0,
              headerOffset + 4 <= bytes.count,
              bytes[headerOffset] == 0x50,
              bytes[headerOffset + 1] == 0x4B,
              bytes[headerOffset + 2] == 0x03,
              bytes[headerOffset + 3] == 0x04 else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        return headerOffset
    }
}
