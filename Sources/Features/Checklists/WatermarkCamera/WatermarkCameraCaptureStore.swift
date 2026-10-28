import Observation
import UIKit

@MainActor @Observable
final class WatermarkCameraCaptureStore {
    private(set) var photos: [WatermarkCapturedPhoto] = []
    private(set) var recoveryItems: [WatermarkRecoveredDraft] = []
    var selectedPhotoID: UUID?
    private(set) var busy = false
    private(set) var persistenceError: String?
    @ObservationIgnored private let storage: WatermarkCameraDraftStorage
    @ObservationIgnored private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var recoveryErrors: [String] = []
    @ObservationIgnored private var pendingStatusIDs: Set<UUID> = []

    init(storage: WatermarkCameraDraftStorage = WatermarkCameraDraftStorage()) {
        self.storage = storage
    }

    var selectedPhoto: WatermarkCapturedPhoto? {
        if let selectedPhotoID,
           let selected = photos.first(where: { $0.id == selectedPhotoID }) { return selected }
        return photos.first
    }

    var draftDirectory: URL { storage.directory }

    var hasMultiplePhotos: Bool { photos.count > 1 }
    var hasPendingDrafts: Bool { photos.contains { !$0.isPersisted } || !pendingStatusIDs.isEmpty }

    var selectedPhotoNumber: Int {
        guard let id = selectedPhoto?.id,
              let index = photos.firstIndex(where: { $0.id == id }) else { return 1 }
        return index + 1
    }

    func restore() async {
        await beginOperation()
        defer { endOperation() }
        guard !Task.isCancelled else { return }
        let result = await storage.restore()
        mergeRestored(result)
        reportErrors([])
    }

    @discardableResult
    func append(images: [UIImage], capturedAt: Date, context: CameraWatermarkContext, projectId: UUID? = nil) async -> Int {
        await beginOperation()
        defer { endOperation() }
        let result = await storage.capture(images: images, capturedAt: capturedAt, context: context, projectId: projectId)
        photos.append(contentsOf: result.photos)
        if let first = result.photos.first { selectedPhotoID = first.id }
        reportErrors(result.errors)
        return result.photos.count
    }

    @discardableResult
    func addAnnotatedCopy(image: UIImage, of source: WatermarkCapturedPhoto) async -> UUID? {
        await beginOperation()
        defer { endOperation() }
        let result = await storage.annotatedCopy(image: image, source: source)
        photos.append(contentsOf: result.photos)
        if let first = result.photos.first { selectedPhotoID = first.id }
        reportErrors(result.errors)
        return result.photos.first?.id
    }

    func retryPendingDrafts() async {
        await beginOperation()
        defer { endOperation() }
        let result = await storage.retry(photos.filter { !$0.isPersisted })
        for photo in result.photos {
            if let index = photos.firstIndex(where: { $0.id == photo.id }) { photos[index] = photo }
        }
        var errors = result.errors
        for photo in photos where pendingStatusIDs.contains(photo.id) {
            do {
                let merged = try await storage.updateStatus(photo)
                if let index = photos.firstIndex(where: { $0.id == photo.id }) { photos[index] = merged }
                pendingStatusIDs.remove(photo.id)
            } catch { errors.append(String(format: AppLocalization.string("照片操作状态未能保存：%@"), error.localizedDescription)) }
        }
        mergeRestored(await storage.restore())
        reportErrors(errors)
    }

    func remove(id: UUID) async {
        await beginOperation()
        defer { endOperation() }
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        await WatermarkCameraAlbumSaveCoordinator.shared.acquire(directory: storage.directory)
        do {
            try await storage.remove(photo)
            photos.removeAll { $0.id == id }
            pendingStatusIDs.remove(id)
            if selectedPhotoID == id { selectedPhotoID = photos.first?.id }
            reportErrors([])
        } catch { reportErrors([String(format: AppLocalization.string("删除照片草稿失败：%@"), error.localizedDescription)]) }
        await WatermarkCameraAlbumSaveCoordinator.shared.release(directory: storage.directory)
    }

    func clear() async {
        await beginOperation()
        defer { endOperation() }
        var errors: [String] = []
        await WatermarkCameraAlbumSaveCoordinator.shared.acquire(directory: storage.directory)
        for photo in photos {
            do {
                try await storage.remove(photo)
                photos.removeAll { $0.id == photo.id }
                pendingStatusIDs.remove(photo.id)
            } catch { errors.append(String(format: AppLocalization.string("删除照片草稿失败：%@"), error.localizedDescription)) }
        }
        await WatermarkCameraAlbumSaveCoordinator.shared.release(directory: storage.directory)
        if !photos.contains(where: { $0.id == selectedPhotoID }) { selectedPhotoID = photos.first?.id }
        reportErrors(errors)
    }

    func exportRecovery(id: String) async throws -> URL {
        await beginOperation()
        defer { endOperation() }
        return try await storage.exportRecovery(id: id)
    }

    func removeRecovery(id: String) async {
        await beginOperation()
        defer { endOperation() }
        await WatermarkCameraAlbumSaveCoordinator.shared.acquire(directory: storage.directory)
        do {
            try await storage.removeRecovery(id: id)
            mergeRestored(await storage.restore())
            reportErrors([])
        } catch { reportErrors([String(format: AppLocalization.string("删除照片草稿失败：%@"), error.localizedDescription)]) }
        await WatermarkCameraAlbumSaveCoordinator.shared.release(directory: storage.directory)
    }

    func resolveAlbumAttempt(id: UUID, retryConfirmed: Bool) async {
        await beginOperation()
        defer { endOperation() }
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        do {
            let resolved = try await WatermarkCameraAlbumSaveCoordinator.shared.resolve(photo: photo, storage: storage, retryConfirmed: retryConfirmed)
            if let index = photos.firstIndex(where: { $0.id == id }) { photos[index] = resolved }
            pendingStatusIDs.remove(id)
            reportErrors([])
        } catch { reportErrors([String(format: AppLocalization.string("照片操作状态未能保存：%@"), error.localizedDescription)]) }
    }

    func saveToAlbum(photo: WatermarkCapturedPhoto, quality: WatermarkExportQuality, coordinator: WatermarkCameraExportCoordinator) async -> WatermarkCameraAlbumSaveResult {
        await beginOperation()
        defer { endOperation() }
        guard var current = photos.first(where: { $0.id == photo.id }) else {
            return .error(message: AppLocalization.string("照片草稿已在其他窗口删除，请刷新后重试。"))
        }
        if !current.isPersisted {
            let result = await storage.retry([current])
            if let persisted = result.photos.first { current = persisted }
            reportErrors(result.errors)
            guard current.isPersisted else {
                return .error(message: AppLocalization.string("请先将照片保存到草稿，再保存到相册。"))
            }
        }
        let outcome = await coordinator.savePhotoToAlbum(current, storage: storage, quality: quality)
        current = outcome.photo
        if let index = photos.firstIndex(where: { $0.id == current.id }) { photos[index] = current }
        if outcome.requiresStatusRetry {
            pendingStatusIDs.insert(current.id)
        } else {
            pendingStatusIDs.remove(current.id)
        }
        reportErrors([])
        return outcome.result
    }

    private func mergeRestored(_ result: WatermarkDraftStorageResult) {
        recoveryErrors = result.errors
        guard result.scanSucceeded else { return }
        recoveryItems = result.recoveryItems
        let previous = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        var restored = result.photos.map { fresh in
            guard let pending = previous[fresh.id], pendingStatusIDs.contains(fresh.id) else { return fresh }
            var merged = fresh
            if pending.albumStatus == .completed || (fresh.albumStatus != .completed && pending.albumStatus != .pending) {
                merged.albumStatus = pending.albumStatus
                merged.albumFailure = pending.albumFailure
            }
            if pending.archiveStatus == .completed || (fresh.archiveStatus != .completed && pending.archiveStatus != .pending) {
                merged.archiveStatus = pending.archiveStatus
                merged.archiveFailure = pending.archiveFailure
            }
            merged.albumAssetIdentifier = fresh.albumAssetIdentifier ?? pending.albumAssetIdentifier
            if merged.albumStatus == .completed { merged.albumAttemptID = nil; merged.albumFailure = nil }
            if merged.archiveStatus == .completed { merged.archiveFailure = nil }
            return merged
        }
        let restoredIDs = Set(restored.map(\.id))
        // Only unsaved captures survive a missing disk record; fresh disk deletions remove stale persisted rows.
        restored.append(contentsOf: photos.filter { !$0.isPersisted && !restoredIDs.contains($0.id) })
        photos = restored.sorted { $0.capturedAt < $1.capturedAt }
        pendingStatusIDs.formIntersection(Set(photos.map(\.id)))
        if !photos.contains(where: { $0.id == selectedPhotoID }) { selectedPhotoID = photos.first?.id }
    }

    func markAlbumSaved(ids: [UUID]) async { await updateStatus(ids: ids, album: true, failure: nil) }
    func markAlbumFailed(ids: [UUID], message: String) async { await updateStatus(ids: ids, album: true, failure: message) }
    func markArchived(id: UUID) async { await updateStatus(ids: [id], album: false, failure: nil) }
    func markArchiveFailed(id: UUID, message: String) async { await updateStatus(ids: [id], album: false, failure: message) }

    private func updateStatus(ids: [UUID], album: Bool, failure: String?) async {
        await beginOperation()
        defer { endOperation() }
        var errors: [String] = []
        for id in Set(ids) {
            guard let index = photos.firstIndex(where: { $0.id == id }) else { continue }
            var photo = photos[index]
            // A failed repeat attempt does not undo a previously confirmed delivery.
            if album {
                if photo.albumStatus != .completed || failure == nil {
                    photo.albumStatus = failure == nil ? .completed : .failed
                    photo.albumFailure = failure
                }
            } else {
                if photo.archiveStatus != .completed || failure == nil {
                    photo.archiveStatus = failure == nil ? .completed : .failed
                    photo.archiveFailure = failure
                }
            }
            photos[index] = photo
            do {
                let merged = try await storage.updateStatus(photo)
                if let index = photos.firstIndex(where: { $0.id == photo.id }) { photos[index] = merged }
                pendingStatusIDs.remove(photo.id)
            } catch {
                pendingStatusIDs.insert(photo.id)
                errors.append(String(format: AppLocalization.string("照片操作状态未能保存：%@"), error.localizedDescription))
            }
        }
        reportErrors(errors)
    }

    private func reportErrors(_ errors: [String]) {
        var messages = recoveryErrors + errors
        if hasPendingDrafts && errors.isEmpty {
            messages.append(AppLocalization.string("部分照片尚未保存到草稿，请勿关闭应用并重试。"))
        }
        persistenceError = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private func beginOperation() async {
        if busy { await withCheckedContinuation { operationWaiters.append($0) } }
        else { busy = true }
    }

    private func endOperation() {
        if operationWaiters.isEmpty { busy = false }
        else { operationWaiters.removeFirst().resume() }
    }
}
