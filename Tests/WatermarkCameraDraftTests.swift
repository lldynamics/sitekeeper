import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct WatermarkCameraDraftTests {
    @Test func batchesAppendAndRestoreImmutableCaptureMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = WatermarkCameraDraftStorage(directory: directory)
        let store = WatermarkCameraCaptureStore(storage: storage)
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstProject = UUID()
        let firstContext = context(project: "工程 A", tag: "整改前")
        #expect(await store.append(images: [image()], capturedAt: firstDate, context: firstContext, projectId: firstProject) == 1)
        let firstID = try #require(store.photos.first?.id)
        #expect(await store.append(images: [image(), image()], capturedAt: firstDate.addingTimeInterval(1), context: context(project: "工程 B", tag: "整改后"), projectId: UUID()) == 2)
        #expect(store.photos.count == 3)
        #expect(store.photos[0].id == firstID)
        #expect(store.photos[0].pendingOriginalData == nil)
        #expect(store.photos[0].thumbnail.size.width <= 720)
        let restored = WatermarkCameraCaptureStore(storage: storage)
        await restored.restore()
        let original = try #require(restored.photos.first(where: { $0.id == firstID }))
        #expect(restored.photos.count == 3)
        #expect(original.capturedAt == firstDate)
        #expect(original.projectId == firstProject)
        #expect(original.context.projectName == "工程 A")
        #expect(original.context.tag == "整改前")
        #expect(original.context.photographer == "张工")
        #expect(original.originalImage != nil)
        #expect(try original.imageForDelivery().size.width == 900)
    }

    @Test func failedWriteRetainsCaptureAndCanRetryWithoutChangingIdentity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = WriteFault()
        fault.fail = true
        let store = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory, writeData: { @Sendable [fault] data, url in try fault.write(data, to: url) }))
        await store.append(images: [image()], capturedAt: .now, context: context())
        let photo = try #require(store.photos.first)
        #expect(store.hasPendingDrafts)
        #expect(store.persistenceError != nil)
        #expect(photo.pendingOriginalData != nil)
        #expect(photo.pendingWatermarkedData != nil)
        #expect(!photo.isPersisted)
        // Recovery must not replace the in-memory pending capture with an empty result.
        await store.restore()
        #expect(store.photos.first?.id == photo.id)
        fault.fail = false
        await store.retryPendingDrafts()
        #expect(store.photos.first?.id == photo.id)
        #expect(store.photos.first?.isPersisted == true)
        #expect(!store.hasPendingDrafts)
        #expect(store.persistenceError == nil)
        let recovered = await WatermarkCameraDraftStorage(directory: directory).restore()
        #expect(recovered.photos.map(\.id) == [photo.id])
        #expect(recovered.errors.isEmpty)
    }

    @Test func removingFailedDraftAlsoRemovesItsIncompleteFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = WriteFault()
        fault.fail = true
        let storage = WatermarkCameraDraftStorage(directory: directory, writeData: { @Sendable [fault] data, url in try fault.write(data, to: url) })
        let store = WatermarkCameraCaptureStore(storage: storage)
        await store.append(images: [image()], capturedAt: .now, context: context())
        let id = try #require(store.photos.first?.id)
        await store.remove(id: id)
        #expect(store.photos.isEmpty)
        #expect(await storage.restore().errors.isEmpty)
    }

    @Test func corruptOrMissingDraftNeverOverwritesHealthyOrRecoverableFiles() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await store.append(images: [image(), image()], capturedAt: .now, context: context())
        let damaged = store.photos[0]
        let metadata = directory.appendingPathComponent(damaged.id.uuidString).appendingPathComponent("metadata.json")
        let corruptBytes = Data("recover me".utf8)
        try corruptBytes.write(to: metadata)
        let restored = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await restored.restore()
        #expect(restored.photos.count == 1)
        #expect(restored.persistenceError != nil)
        await restored.append(images: [image()], capturedAt: .now, context: context())
        #expect(try Data(contentsOf: metadata) == corruptBytes)
        await restored.clear()
        #expect(try Data(contentsOf: metadata) == corruptBytes)
        #expect(restored.persistenceError != nil)
    }

    @Test func removeAndClearDeleteOnlyExplicitlySelectedDrafts() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = WatermarkCameraDraftStorage(directory: directory)
        let store = WatermarkCameraCaptureStore(storage: storage)
        await store.append(images: [image(), image()], capturedAt: .now, context: context())
        let removedID = store.photos[0].id
        let remainingID = store.photos[1].id
        await store.remove(id: removedID)
        #expect(store.photos.map(\.id) == [remainingID])
        #expect(await storage.restore().photos.map(\.id) == [remainingID])
        await store.clear()
        #expect(store.photos.isEmpty)
        #expect(store.selectedPhotoID == nil)
        #expect(await storage.restore().photos.isEmpty)
    }

    @Test func deliveryStatusIsIdempotentAndSurvivesReopening() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = WatermarkCameraDraftStorage(directory: directory)
        let store = WatermarkCameraCaptureStore(storage: storage)
        await store.append(images: [image()], capturedAt: .now, context: context())
        let id = try #require(store.photos.first?.id)
        await store.markAlbumFailed(ids: [id], message: "denied")
        #expect(store.photos[0].albumFailure == "denied")
        await store.markAlbumSaved(ids: [id, id])
        await store.markAlbumSaved(ids: [id])
        await store.markAlbumFailed(ids: [id], message: "later failure")
        await store.markArchived(id: id)
        await store.markArchived(id: id)
        let restored = await storage.restore()
        #expect(restored.photos.count == 1)
        #expect(restored.photos[0].albumStatus == .completed)
        #expect(restored.photos[0].albumFailure == nil)
        #expect(restored.photos[0].archiveStatus == .completed)
    }

    @Test func failedStatusWriteRetriesWithoutPretendingItWasDurable() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fault = WriteFault()
        let storage = WatermarkCameraDraftStorage(directory: directory, writeData: { @Sendable [fault] data, url in try fault.write(data, to: url) })
        let store = WatermarkCameraCaptureStore(storage: storage)
        await store.append(images: [image()], capturedAt: .now, context: context())
        let id = try #require(store.photos.first?.id)
        fault.fail = true
        await store.markAlbumSaved(ids: [id])
        #expect(store.hasPendingDrafts)
        #expect(store.persistenceError != nil)
        #expect(await storage.restore().photos[0].albumStatus == .pending)
        fault.fail = false
        await store.retryPendingDrafts()
        #expect(!store.hasPendingDrafts)
        #expect(await storage.restore().photos[0].albumStatus == .completed)
    }

    @Test func annotationCreatesNewIdentityButKeepsOriginalAndMetadata() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await store.append(images: [image()], capturedAt: Date(timeIntervalSince1970: 400), context: context(), projectId: UUID())
        let source = try #require(store.photos.first)
        let derivativeID = try #require(await store.addAnnotatedCopy(image: image(color: .red), of: source))
        let derivative = try #require(store.photos.first(where: { $0.id == derivativeID }))
        #expect(derivative.id != source.id)
        #expect(derivative.projectId == source.projectId)
        #expect(derivative.capturedAt == source.capturedAt)
        #expect(derivative.context.projectName == source.context.projectName)
        #expect(try Data(contentsOf: #require(derivative.originalURL)) == Data(contentsOf: #require(source.originalURL)))
        #expect(derivative.albumStatus == .pending)
        #expect(derivative.archiveStatus == .pending)
    }

    @Test func missingFullImageCannotSilentlyDeliverThumbnail() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await store.append(images: [image()], capturedAt: .now, context: context())
        let photo = try #require(store.photos.first)
        try FileManager.default.removeItem(at: #require(photo.watermarkedURL))
        #expect(throws: WatermarkDraftImageError.self) { try photo.imageForDelivery() }
        #expect(throws: WatermarkDraftImageError.self) { try photo.jpegDataForDelivery(compression: 0.9) }
        let restored = await WatermarkCameraDraftStorage(directory: directory).restore()
        #expect(restored.photos.isEmpty)
        #expect(!restored.errors.isEmpty)
        #expect(FileManager.default.fileExists(atPath: try #require(photo.originalURL).path))
    }

    @Test func separateWindowsCannotRegressEachOthersDeliveryStatus() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStorage = WatermarkCameraDraftStorage(directory: directory)
        let first = WatermarkCameraCaptureStore(storage: firstStorage)
        await first.append(images: [image()], capturedAt: .now, context: context())
        let second = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await second.restore()
        let id = try #require(first.photos.first?.id)
        await first.markAlbumSaved(ids: [id])
        await second.markArchived(id: id)
        #expect(second.photos[0].albumStatus == .completed)
        // The first window's archive status is stale, but its later failed retry must
        // retain both confirmed channels from the latest metadata on disk.
        await first.markAlbumFailed(ids: [id], message: "stale failed attempt")
        let record = try #require(await firstStorage.restore().photos.first)
        #expect(record.albumStatus == .completed)
        #expect(record.archiveStatus == .completed)
        #expect(record.albumFailure == nil)
    }

    @Test func statusUpdatePreservesCorruptMetadataInsteadOfOverwritingIt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
        await store.append(images: [image()], capturedAt: .now, context: context())
        let id = try #require(store.photos.first?.id)
        let metadata = directory.appendingPathComponent(id.uuidString).appendingPathComponent("metadata.json")
        let evidence = Data("metadata needs recovery".utf8)
        try evidence.write(to: metadata)
        await store.markAlbumSaved(ids: [id])
        #expect(store.hasPendingDrafts)
        #expect(store.persistenceError != nil)
        #expect(try Data(contentsOf: metadata) == evidence)
    }

    @Test func scopedDraftDirectoriesFollowDataStoreProfiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appendingPathComponent("profile-a/sitekeeper.json")
        let secondURL = root.appendingPathComponent("profile-b/sitekeeper.json")
        let firstDirectory = WatermarkCameraDraftStorage.scopedDirectory(for: firstURL)
        let secondDirectory = WatermarkCameraDraftStorage.scopedDirectory(for: secondURL)
        #expect(firstDirectory != secondDirectory)
        #expect(firstDirectory == firstURL.deletingLastPathComponent().appendingPathComponent("BusinessDrafts/WatermarkCamera", isDirectory: true))
        let first = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: firstDirectory))
        let second = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: secondDirectory))
        await first.append(images: [image()], capturedAt: .now, context: context())
        await second.restore()
        #expect(second.photos.isEmpty)
        let reopened = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: WatermarkCameraDraftStorage.scopedDirectory(for: firstURL)))
        await reopened.restore()
        #expect(reopened.photos.map(\.id) == first.photos.map(\.id))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WatermarkDraftTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func context(project: String = "工程 A", tag: String = "现场") -> CameraWatermarkContext {
        CameraWatermarkContext(projectName: project, template: .constructionLog, tag: tag, photographer: "张工", locationText: "测试位置")
    }

    private func image(color: UIColor = .blue) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).image { renderer in
            color.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        }
    }
}

/// The injected fault is shared across actors; every access is guarded by the same lock.
private final class WriteFault: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = false
    var fail: Bool {
        get { lock.withLock { shouldFail } }
        set { lock.withLock { shouldFail = newValue } }
    }
    func write(_ data: Data, to url: URL) throws {
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: url, options: .atomic)
    }
}
