import Foundation
import UIKit
import Testing
@testable import sitekeeper

@MainActor
struct PhotoBatchTransactionTests {
    private enum InjectedFailure: Error, Equatable {
        case staging
        case commit
        case rollback
    }

    @Test func batchWritesEveryOriginalAndDecodableThumbnailWithStableNames() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let images = [makeJPEG(.red), makeJPEG(.blue), makeJPEG(.green)]
        let names = try PhotoStorage.saveManyOrThrow(originals: images, logId: id, directory: root)

        #expect(names == ["\(id.uuidString).jpg", "\(id.uuidString)-1.jpg", "\(id.uuidString)-2.jpg"])
        #expect(try snapshot(root).count == 6)
        for (index, name) in names.enumerated() {
            #expect(try Data(contentsOf: root.appendingPathComponent("Photos/\(name)")) == images[index])
            let thumbnail = try Data(contentsOf: root.appendingPathComponent("PhotoThumbnails/\(name)"))
            #expect(UIImage(data: thumbnail) != nil)
        }
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func invalidLaterImageDoesNotPublishEarlierPhotos() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.red), Data([0, 1, 2])], logId: UUID(), directory: root
            )
            Issue.record("Invalid later image unexpectedly succeeded")
        } catch let error as FileStorageError {
            #expect(error == .invalidImageData)
        }
        #expect(try snapshot(root).isEmpty)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test(arguments: Array(0..<6))
    func stagingFailurePreservesEveryExistingByte(failurePosition: Int) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        _ = try PhotoStorage.saveManyOrThrow(originals: [makeJPEG(.red), makeJPEG(.blue)], logId: id, directory: root)
        let before = try snapshot(root)
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.green), makeJPEG(.yellow), makeJPEG(.purple)], logId: id, directory: root
            ) { point in
                if point == .stagingWrite(failurePosition) { throw InjectedFailure.staging }
            }
            Issue.record("Injected staging failure unexpectedly succeeded")
        } catch let error as InjectedFailure {
            #expect(error == .staging)
        }
        #expect(try snapshot(root) == before)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test(arguments: Array(0..<6))
    func commitFailureRollsBackWholeBatchAndRetryLeavesNoAbandonedFiles(failurePosition: Int) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        _ = try PhotoStorage.saveManyOrThrow(originals: [makeJPEG(.red), makeJPEG(.blue)], logId: id, directory: root)
        // Unrelated files must survive both rollback and retry.
        let unrelated = root.appendingPathComponent("Photos/unrelated.jpg")
        try Data("existing unrelated original".utf8).write(to: unrelated)
        let before = try snapshot(root)
        let replacements = [makeJPEG(.green), makeJPEG(.yellow), makeJPEG(.purple)]
        do {
            _ = try PhotoStorage.saveManyOrThrow(originals: replacements, logId: id, directory: root) { point in
                if point == .commit(failurePosition) { throw InjectedFailure.commit }
            }
            Issue.record("Injected commit failure unexpectedly succeeded")
        } catch let error as InjectedFailure {
            #expect(error == .commit)
        }
        #expect(try snapshot(root) == before)
        #expect(try transactionDirectories(root).isEmpty)

        let firstRetry = try PhotoStorage.saveManyOrThrow(originals: replacements, logId: id, directory: root)
        let afterRetry = try snapshot(root)
        let secondRetry = try PhotoStorage.saveManyOrThrow(originals: replacements, logId: id, directory: root)
        #expect(firstRetry == secondRetry)
        #expect(try snapshot(root) == afterRetry)
        #expect(afterRetry.count == 7)
        #expect(afterRetry["Photos/unrelated.jpg"] == before["Photos/unrelated.jpg"])
        for (index, name) in firstRetry.enumerated() {
            #expect(afterRetry["Photos/\(name)"] == replacements[index])
        }
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func failedNewBatchLeavesNoOriginalOrThumbnail() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.red), makeJPEG(.blue)], logId: UUID(), directory: root
            ) { point in
                if point == .commit(3) { throw InjectedFailure.commit }
            }
            Issue.record("Injected commit failure unexpectedly succeeded")
        } catch let error as InjectedFailure {
            #expect(error == .commit)
        }
        #expect(try snapshot(root).isEmpty)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func rollbackPreservesOriginallyMissingCounterparts() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("PhotoThumbnails"), withIntermediateDirectories: true)
        try Data("original without thumbnail".utf8).write(to: root.appendingPathComponent("Photos/\(id.uuidString).jpg"))
        try Data("thumbnail without original".utf8).write(to: root.appendingPathComponent("PhotoThumbnails/\(id.uuidString)-1.jpg"))
        let before = try snapshot(root)
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.red), makeJPEG(.blue), makeJPEG(.green)], logId: id, directory: root
            ) { point in
                if point == .commit(5) { throw InjectedFailure.commit }
            }
            Issue.record("Injected commit failure unexpectedly succeeded")
        } catch let error as InjectedFailure {
            #expect(error == .commit)
        }
        #expect(try snapshot(root) == before)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func cancellationBetweenCommitsRestoresExistingPairs() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        _ = try PhotoStorage.saveManyOrThrow(originals: [makeJPEG(.red)], logId: id, directory: root)
        let before = try snapshot(root)
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.blue), makeJPEG(.green)], logId: id, directory: root
            ) { point in
                if point == .commit(3) { throw CancellationError() }
            }
            Issue.record("Cancelled batch unexpectedly succeeded")
        } catch is CancellationError {
            // Cancellation is preserved after complete rollback.
        }
        #expect(try snapshot(root) == before)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func taskCancellationDuringCommitRollsBackBeforeReturning() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        _ = try PhotoStorage.saveManyOrThrow(originals: [makeJPEG(.red)], logId: id, directory: root)
        let before = try snapshot(root)
        let replacements = [makeJPEG(.blue), makeJPEG(.green)]
        let task = Task.detached {
            try PhotoStorage.saveManyOrThrow(originals: replacements, logId: id, directory: root) { point in
                if point == .commit(3) {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled task unexpectedly published a batch")
        } catch is CancellationError {
            // The actual Task cancellation flag is observed by the commit loop.
        }
        #expect(try snapshot(root) == before)
        #expect(try transactionDirectories(root).isEmpty)
    }

    @Test func rollbackFailurePreservesOriginalErrorAndRecoverableOldBytesWithManifest() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let old = [makeJPEG(.red), makeJPEG(.blue)]
        _ = try PhotoStorage.saveManyOrThrow(originals: old, logId: id, directory: root)
        do {
            _ = try PhotoStorage.saveManyOrThrow(
                originals: [makeJPEG(.green), makeJPEG(.yellow)], logId: id, directory: root
            ) { point in
                if point == .commit(3) { throw InjectedFailure.commit }
                if point == .rollback(0) { throw InjectedFailure.rollback }
            }
            Issue.record("Injected rollback failure unexpectedly succeeded")
        } catch let error as PhotoStorage.BatchRecoveryError {
            #expect(error.originalError as? InjectedFailure == .commit)
            #expect(error.rollbackErrors.count == 1)
            #expect(error.rollbackErrors.first as? InjectedFailure == .rollback)
            #expect(try Data(contentsOf: error.recoveryDirectory.appendingPathComponent("previous-2")) == old[1])
            let manifestData = try Data(contentsOf: error.recoveryDirectory.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [[String: String]])
            #expect(manifest.count == 4)
            #expect(manifest[2]["destination"] == root.appendingPathComponent("Photos/\(id.uuidString)-1.jpg").path)
            #expect(manifest[2]["previous"] == "previous-2")
            // Rollback continues for the other targets after an individual restoration fails.
            #expect(try Data(contentsOf: root.appendingPathComponent("Photos/\(id.uuidString).jpg")) == old[0])
        }
        #expect(try transactionDirectories(root).count == 1)
    }

    @Test func emptyBatchCreatesNoFiles() throws {
        let root = temporaryRoot()
        let result = try PhotoStorage.saveManyOrThrow(originals: [], logId: UUID(), directory: root)
        #expect(result.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PhotoBatchTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeJPEG(_ color: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [:] }
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private func transactionDirectories(_ root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".photo-transaction-") }
    }
}
