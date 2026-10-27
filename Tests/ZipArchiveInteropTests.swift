import Foundation
import Testing
@testable import sitekeeper

struct ZipArchiveInteropTests {
    @Test func pythonStoredDeflatedAndZIP64ArchivesRoundTrip() throws {
        for data in [ZipInteropFixtures.stored, ZipInteropFixtures.zip64] {
            let entries = try SimpleZipArchiveReader.read(data)
            #expect(entries.map(\.path) == ["资料/读我.txt"])
            #expect(entries.map(\.data) == [Data("123456789".utf8)])
        }
        let entries = try SimpleZipArchiveReader.read(ZipInteropFixtures.deflated)
        #expect(entries.first?.data == Data(repeating: 65, count: 1_048_576))
    }

    @Test func fixedHistoricalBackupRetainsMetadataAndOriginalAttachment() throws {
        let data = try #require(Data(base64Encoded: ZipInteropFixtures.legacy, options: .ignoreUnknownCharacters))
        let entries = try SimpleZipArchiveReader.read(data)
        #expect(entries.contains(where: { $0.path == "data/backup.json" }))
        #expect(entries.first(where: { $0.path.hasSuffix("legacy-fixture-note.bin") })?.data == Data("SK-LEGACY".utf8))
    }

    @Test func traversalDuplicatesAndSymlinksAreRejectedBeforeCallbacks() throws {
        for data in [ZipInteropFixtures.traversal, ZipInteropFixtures.duplicate, ZipInteropFixtures.symlink] {
            let url = try archiveURL(data)
            defer { try? FileManager.default.removeItem(at: url) }
            var called = false
            #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
                try SimpleZipArchiveReader.scan(fileURL: url) { _, _, _ in called = true }
            }
            #expect(!called)
        }
    }

    @Test func malformedIndexCannotSilentlyBecomeAPartialRestore() throws {
        var data = ZipInteropFixtures.stored
        // Claim two entries in a central directory that contains one.
        data[data.count - 14] = 2
        data[data.count - 12] = 2
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) { try SimpleZipArchiveReader.read(data) }
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) { try SimpleZipArchiveReader.read(Data(data.dropLast(5))) }
    }

    @Test func compressedPayloadCannotExceedAdvertisedBudget() throws {
        let url = try archiveURL(ZipInteropFixtures.deflated)
        defer { try? FileManager.default.removeItem(at: url) }
        let limits = BackupArchiveLimits(maximumEntryBytes: 1024, maximumTotalBytes: 2048, maximumEntryCount: 10)
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try SimpleZipArchiveReader.scan(fileURL: url, limits: limits) { _, _, _ in Issue.record("Oversized entry reached callback") }
        }
        // Lie about the decoded size in the central header; bound actual consumer output too.
        var forged = ZipInteropFixtures.deflated
        let central = try #require(forged.range(of: Data([0x50, 0x4B, 0x01, 0x02])))
        forged.replaceSubrange((central.lowerBound + 24)..<(central.lowerBound + 28), with: [1, 0, 0, 0])
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) { try SimpleZipArchiveReader.read(forged) }
    }

    @Test func cancellationAndCRCFailureKeepExistingDestination() throws {
        var corrupt = ZipInteropFixtures.stored
        let nameLength = Int(corrupt[26]) | (Int(corrupt[27]) << 8)
        corrupt[30 + nameLength] ^= 0xFF
        let url = try archiveURL(corrupt)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = Data("keep destination".utf8)
        try original.write(to: destination)
        defer { try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: destination) }
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try SimpleZipArchiveReader.scan(fileURL: url) { _, _, write in try write(destination) }
        }
        #expect(try Data(contentsOf: destination) == original)
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try SimpleZipArchiveReader.scan(fileURL: url, shouldCancel: { true }) { _, _, _ in Issue.record("Cancelled scan reached callback") }
        }
    }

    @Test func streamedFileAndUTF8NameSurviveWriterAndReader() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "interop-write")
        let data = Data(repeating: 0xA5, count: 600_001)
        try data.write(to: source)
        defer { try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: output) }
        var writer = try StreamingZipArchiveWriter(fileURL: output, limits: .backup)
        try writer.addFile(path: "项目/照片.bin", sourceFileURL: source)
        try writer.addFile(path: "empty", data: Data())
        _ = try writer.finish()
        let entries = try SimpleZipArchiveReader.read(Data(contentsOf: output))
        #expect(entries.map(\.path) == ["项目/照片.bin", "empty"])
        #expect(entries.map(\.data) == [data, Data()])
        #expect(throws: StreamingZipArchiveWriterError.self) { try writer.addFile(path: "closed", data: Data()) }
    }

    #if os(macOS)
    @Test func systemUnzipAcceptsLibraryWriterOutput() throws {
        let output = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "system-unzip")
        defer { try? FileManager.default.removeItem(at: output) }
        var writer = try StreamingZipArchiveWriter(fileURL: output)
        try writer.addFile(path: "项目/说明.txt", data: Data("independent ZIP compatibility".utf8))
        try writer.addFile(path: "empty", data: Data())
        _ = try writer.finish()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", output.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let diagnostic = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "System unzip rejected archive: \(String(decoding: diagnostic, as: UTF8.self))")
    }
    #endif

    private func archiveURL(_ data: Data) throws -> URL {
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "interop-fixture")
        try data.write(to: url)
        return url
    }
}

// Generated independently with Python zipfile; ZIP64 end records follow PKWARE APPNOTE.
private enum ZipInteropFixtures {
    static let legacy = """
    UEsDBBQAAAAAAABIoVzEbp1rrQAAAK0AAAANAAAAbWFuaWZlc3QuanNvbnsKICAiYXBwQnVpbGQi
    OiAiMTAwIiwKICAiYXBwTmFtZSI6ICLlt6XlnLDmjozmn5wiLAogICJhcHBWZXJzaW9uIjogIjEu
    MC4wIiwKICAiZXhwb3J0ZWRBdCI6ICIyMDI2LTA1LTAxIDA5OjAwIiwKICAibWV0YWRhdGFQYXRo
    IjogImRhdGEvYmFja3VwLmpzb24iLAogICJzY2hlbWFWZXJzaW9uIjogMgp9UEsDBBQAAAAAAABI
    oVyxYdCRkgUAAJIFAAAQAAAAZGF0YS9iYWNrdXAuanNvbnsKICAiYXBwQnVpbGQiOiAiMTAwIiwK
    ICAiYXBwVmVyc2lvbiI6ICIxLjAuMCIsCiAgImJhY2t1cENyZWF0ZWRBdCI6ICIyMDI2LTA1LTAx
    IDA5OjAwIiwKICAiY29uc3RydWN0aW9uTWV0aG9kcyI6IFtdLAogICJkYWlseUxvZ3MiOiBbXSwK
    ICAiZGVsZXRlZFVzZXJNYXRlcmlhbHMiOiBbXSwKICAiZmF2b3JpdGVNYXRlcmlhbEtleXMiOiBb
    XSwKICAiaGlkZGVuUHJlc2V0S2V5cyI6IFtdLAogICJoaXN0b3J5UmVjb3JkcyI6IFtdLAogICJs
    YWJvclJlY29yZHMiOiBbXSwKICAibWF0ZXJpYWxJdGVtcyI6IFtdLAogICJtYXRlcmlhbFByaWNl
    RW50cmllcyI6IFtdLAogICJtYXRlcmlhbFNoZWV0RHJhZnRzIjogW10sCiAgInByb2dyZXNzVGFz
    a3MiOiBbXSwKICAicHJvamVjdENvbnRhY3RzIjogW10sCiAgInByb2plY3REb2N1bWVudHMiOiBb
    XSwKICAicHJvamVjdERyYXdpbmdzIjogW10sCiAgInByb2plY3RGaW5hbmNpYWxSZWNvcmRzIjog
    W10sCiAgInByb2plY3RXYXJlaG91c2VNb3ZlbWVudHMiOiBbXSwKICAicHJvamVjdHMiOiBbCiAg
    ICB7CiAgICAgICJpZCI6ICIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLAog
    ICAgICAibG9jYXRpb24iOiAi5LiA5Y+35qW8IiwKICAgICAgIm5hbWUiOiAi5penWklQ5qC35pys
    6aG555uuIiwKICAgICAgInN0YXR1cyI6ICLov5vooYzkuK0iCiAgICB9CiAgXSwKICAicXVpY2tO
    b3RlcyI6IFsKICAgIHsKICAgICAgImF0dGFjaG1lbnRzIjogWwogICAgICAgIHsKICAgICAgICAg
    ICJjcmVhdGVkQXQiOiAiMjAyNi0wNS0wMSAwOTowMSIsCiAgICAgICAgICAiZmlsZU5hbWUiOiAi
    bGVnYWN5LWZpeHR1cmUtbm90ZS5iaW4iLAogICAgICAgICAgImlkIjogIjMzMzMzMzMzLTMzMzMt
    MzMzMy0zMzMzLTMzMzMzMzMzMzMzMyIsCiAgICAgICAgICAia2luZCI6ICJmaWxlIiwKICAgICAg
    ICAgICJvcmlnaW5hbE5hbWUiOiAibGVnYWN5LW5vdGUudHh0IgogICAgICAgIH0KICAgICAgXSwK
    ICAgICAgImNvbnRlbnQiOiAi5p2l6Ieq5Zu65a6aWklQIGZpeHR1cmUiLAogICAgICAiY3JlYXRl
    ZEF0IjogIjIwMjYtMDUtMDEgMDk6MDEiLAogICAgICAiaWQiOiAiMjIyMjIyMjItMjIyMi0yMjIy
    LTIyMjItMjIyMjIyMjIyMjIyIiwKICAgICAgInByb2plY3RJZCI6ICIxMTExMTExMS0xMTExLTEx
    MTEtMTExMS0xMTExMTExMTExMTEiLAogICAgICAidGl0bGUiOiAi5pen5aSH5Lu96ZmE5Lu2IiwK
    ICAgICAgInVwZGF0ZWRBdCI6ICIyMDI2LTA1LTAxIDA5OjAyIgogICAgfQogIF0sCiAgInF1b3Rl
    SXRlbXMiOiBbXSwKICAicmVjZW50TWF0ZXJpYWxLZXlzIjogW10sCiAgInNjaGVtYVZlcnNpb24i
    OiAyLAogICJzaXRlVG9kb3MiOiBbXSwKICAic3VwcGxpZXJQcm9maWxlcyI6IFtdLAogICJ0ZW1w
    bGF0ZXMiOiBbXSwKICAidXNlck1hdGVyaWFscyI6IFtdCn1QSwMEFAAAAAAAAEihXDGAuiEJAAAA
    CQAAADQAAABmaWxlcy9xdWljay1ub3RlLWF0dGFjaG1lbnRzL2xlZ2FjeS1maXh0dXJlLW5vdGUu
    YmluU0stTEVHQUNZUEsBAhQDFAAAAAAAAEihXMRunWutAAAArQAAAA0AAAAAAAAAAAAAAIABAAAA
    AG1hbmlmZXN0Lmpzb25QSwECFAMUAAAAAAAASKFcsWHQkZIFAACSBQAAEAAAAAAAAAAAAAAAgAHY
    AAAAZGF0YS9iYWNrdXAuanNvblBLAQIUAxQAAAAAAABIoVwxgLohCQAAAAkAAAA0AAAAAAAAAAAA
    AACAAZgGAABmaWxlcy9xdWljay1ub3RlLWF0dGFjaG1lbnRzL2xlZ2FjeS1maXh0dXJlLW5vdGUu
    YmluUEsFBgAAAAADAAMA2wAAAPMGAAAAAA==
    """

    static let stored = Data(base64Encoded: "UEsDBBQAAAgAAHiVWF0mOfTLCQAAAAkAAAARAAAA6LWE5paZL+ivu+aIkS50eHQxMjM0NTY3ODlQSwECFAMUAAAIAAB4lVhdJjn0ywkAAAAJAAAAEQAAAAAAAAAAAAAAgAEAAAAA6LWE5paZL+ivu+aIkS50eHRQSwUGAAAAAAEAAQA/AAAAOAAAAAAA")!
    static let deflated = Data(base64Encoded: "UEsDBBQAAAgIAHiVWF3JvvaBCgQAAAAAEAARAAAA6LWE5paZL+ivu+aIkS50eHTtwTEBAAAAwqBs61/KEL5AAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB8BlBLAQIUAxQAAAgIAHiVWF3JvvaBCgQAAAAAEAARAAAAAAAAAAAAAACAAQAAAADotYTmlpkv6K+75oiRLnR4dFBLBQYAAAAAAQABAD8AAAA5BAAAAAA=")!
    static let zip64 = Data(base64Encoded: "UEsDBBQAAAgAAHiVWF0mOfTLCQAAAAkAAAARAAAA6LWE5paZL+ivu+aIkS50eHQxMjM0NTY3ODlQSwECFAMUAAAIAAB4lVhdJjn0ywkAAAAJAAAAEQAAAAAAAAAAAAAAgAEAAAAA6LWE5paZL+ivu+aIkS50eHRQSwYGLAAAAAAAAAAtAC0AAAAAAAAAAAABAAAAAAAAAAEAAAAAAAAAPwAAAAAAAAA4AAAAAAAAAFBLBgcAAAAAdwAAAAAAAAABAAAAUEsFBgAAAAD///////////////8AAA==")!
    static let symlink = Data(base64Encoded: "UEsDBBQAAAAAAAAAIQBASv+xDQAAAA0AAAAEAAAAbGluay4uLy4uL291dHNpZGVQSwECFAMUAAAAAAAAACEAQEr/sQ0AAAANAAAABAAAAAAAAAAAAAAA/6EAAAAAbGlua1BLBQYAAAAAAQABADIAAAAvAAAAAAA=")!
    static let traversal = Data(base64Encoded: "UEsDBBQAAAAAAHiVWF0mOfTLCQAAAAkAAAANAAAALi4vZXNjYXBlLnR4dDEyMzQ1Njc4OVBLAQIUAxQAAAAAAHiVWF0mOfTLCQAAAAkAAAANAAAAAAAAAAAAAACAAQAAAAAuLi9lc2NhcGUudHh0UEsFBgAAAAABAAEAOwAAADQAAAAAAA==")!
    static let duplicate = Data(base64Encoded: "UEsDBBQAAAAAAHiVWF1DvrfoAQAAAAEAAAAIAAAAc2FtZS50eHRhUEsDBBQAAAAAAHiVWF35775xAQAAAAEAAAAIAAAAc2FtZS50eHRiUEsBAhQDFAAAAAAAeJVYXUO+t+gBAAAAAQAAAAgAAAAAAAAAAAAAAIABAAAAAHNhbWUudHh0UEsBAhQDFAAAAAAAeJVYXfnvvnEBAAAAAQAAAAgAAAAAAAAAAAAAAIABJwAAAHNhbWUudHh0UEsFBgAAAAACAAIAbAAAAE4AAAAAAA==")!
}
