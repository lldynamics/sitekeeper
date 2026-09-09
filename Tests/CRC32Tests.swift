import Foundation
import Testing
@testable import sitekeeper

struct CRC32Tests {
    @Test func standardZIPCRC32VectorAndEmptyData() {
        #expect(CRC32.calculate(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.calculate(Data()) == 0)
        #expect(CRC32.updating(0xCBF4_3926, with: Data()) == 0xCBF4_3926)
        var stream = StreamingCRC32Accumulator()
        stream.update(Data())
        #expect(stream.finalized == 0)
    }

    @Test func randomizedChunksMatchIndependentReferenceAndOneShotCRC() {
        var state: UInt64 = 0x59A4_F268_1073_BDEC
        let bytes = (0..<65_537).map { _ -> UInt8 in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return UInt8(truncatingIfNeeded: state >> 32)
        }
        let data = Data(bytes)
        let expected = referenceCRC(bytes)
        #expect(CRC32.calculate(data) == expected)
        var stream = StreamingCRC32Accumulator()
        var offset = 0
        while offset < data.count {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let length = min(Int(state % 4096) + 1, data.count - offset)
            stream.update(data.subdata(in: offset..<(offset + length)))
            stream.update(Data())
            offset += length
        }
        #expect(stream.finalized == expected)
    }

    @Test func streamingWriterUsesStandardCRCReadableByLegacyReader() throws {
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "crc-standard")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = try StreamingZipArchiveWriter(fileURL: url)
        try writer.addFile(path: "vector.txt", data: Data("123456789".utf8))
        try writer.addFile(path: "empty.bin", data: Data())
        _ = try writer.finish()
        let archive = try Data(contentsOf: url)
        // The first local header stores the interoperable CRC at byte offset 14.
        #expect(try archive.uint32LE(at: 14) == 0xCBF4_3926)
        let entries = try SimpleZipArchiveReader.read(archive)
        #expect(entries.map(\.data) == [Data("123456789".utf8), Data()])
        var scannedPaths: [String] = []
        try SimpleZipArchiveReader.scan(fileURL: url, verifyAllEntries: true) { entry, _, _ in
            scannedPaths.append(entry.path)
        }
        #expect(scannedPaths == ["vector.txt", "empty.bin"])
    }

    @Test func fixedLegacyZIPStillPassesStreamingChecksumValidation() throws {
        let url = try BackupImportExportTestSupport.writeFixedLegacyBackupZipFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try BackupArchiveService.validateArchive(at: url)
        let snapshot = try BackupArchiveService.decodeBackup(from: url)
        let attachment = snapshot.quickNoteAttachmentFiles.first {
            $0.fileName == BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentFileName
        }
        #expect(attachment?.data == BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentData)
    }

    private func referenceCRC(_ bytes: [UInt8]) -> UInt32 {
        var value = UInt32.max
        for byte in bytes {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = value & 1 == 0 ? value >> 1 : (value >> 1) ^ 0xEDB8_8320
            }
        }
        return value ^ UInt32.max
    }
}
