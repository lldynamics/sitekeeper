import Foundation
import Testing
@testable import sitekeeper

struct CloudBackupUploadStateTests {
    @Test func successRequiresBothArchiveAndIntegrityFile() {
        let uploaded = CloudBackupUploadObservation(isUploaded: true)
        #expect(CloudBackupUploadState.evaluate(archive: uploaded, digest: uploaded) == .uploaded)
        #expect(CloudBackupUploadState.evaluate(archive: uploaded, digest: .init(isUploaded: false)) == .pending)
        #expect(CloudBackupUploadState.evaluate(archive: .init(isUploaded: nil), digest: uploaded) == .pending)
        #expect(CloudBackupUploadState.evaluate(archive: .init(isUploaded: false), digest: uploaded) == .pending)
    }

    @Test func uploadFailureTakesPrecedenceOverStaleUploadedFlag() {
        #expect(CloudBackupUploadState.evaluate(
            archive: .init(isUploaded: true),
            digest: .init(isUploaded: true, errorMessage: "Quota exceeded")
        ) == .failed("Quota exceeded"))
    }

    @Test func pendingNewBackupCannotEvictConfirmedOlderBackups() {
        let files = [file(5, .pending), file(4, .failed("offline")), file(3, .uploaded), file(2, .uploaded), file(1, .uploaded)]
        #expect(CloudBackupRetentionPolicy.removableBackups(files, keeping: 3).isEmpty)
        #expect(CloudBackupRetentionPolicy.latestConfirmedDate(files) == Date(timeIntervalSince1970: 3))
        #expect(CloudBackupRetentionPolicy.pendingUpload(in: files, fileName: "backup-5.zip") == files[0])
    }

    @Test func completedUploadEvictsOnlyOldestConfirmedFiles() {
        let files = [file(2, .uploaded), file(5, .uploaded), file(1, .uploaded), file(4, .pending), file(3, .uploaded)]
        #expect(CloudBackupRetentionPolicy.removableBackups(files, keeping: 3).map(\.fileName) == ["backup-1.zip"])
        #expect(CloudBackupRetentionPolicy.pendingUpload(in: files, fileName: "backup-5.zip") == nil)
        #expect(CloudBackupRetentionPolicy.removableBackups(files, keeping: 0).isEmpty)
    }

    @Test func sameSecondBackupsHaveUniqueNames() {
        let date = Date(timeIntervalSince1970: 100)
        #expect(CloudBackupService.makeBackupFileName(date: date) != CloudBackupService.makeBackupFileName(date: date))
    }

    @Test func missingOrUnreadablePendingFileDoesNotPermitRepeatedAutomaticArchives() {
        #expect(CloudBackupRetentionPolicy.automaticBackupBlockReason(in: [], pendingFileName: "backup-5.zip") != nil)
        #expect(CloudBackupRetentionPolicy.automaticBackupBlockReason(in: [file(5, .failed("offline"))], pendingFileName: "backup-5.zip") != nil)
        #expect(CloudBackupRetentionPolicy.automaticBackupBlockReason(in: [file(5, .uploaded)], pendingFileName: "backup-5.zip") == nil)
        #expect(CloudBackupRetentionPolicy.automaticBackupBlockReason(in: [], pendingFileName: "") == nil)
    }

    private func file(_ timestamp: Int, _ state: CloudBackupUploadState) -> CloudBackupFile {
        let name = "backup-\(timestamp).zip"
        return CloudBackupFile(id: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name,
                               byteSize: 100, modifiedAt: Date(timeIntervalSince1970: Double(timestamp)), uploadState: state)
    }
}
