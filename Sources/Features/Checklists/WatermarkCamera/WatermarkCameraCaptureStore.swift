import Observation
import UIKit

@MainActor @Observable
final class WatermarkCameraCaptureStore {
    private(set) var photos: [WatermarkCapturedPhoto] = []
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
        let result = await storage.restore()
        // Merge by identity so reopening cannot discard a pending write or an in-flight capture.
        let existingIDs = Set(photos.map(\.id))
        photos.append(contentsOf: result.photos.filter { !existingIDs.contains($0.id) })
        photos.sort { $0.capturedAt < $1.capturedAt }
        if selectedPhotoID == nil { selectedPhotoID = photos.first?.id }
        recoveryErrors = result.errors
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
            } catch { errors.append("照片操作状态未能保存：\(error.localizedDescription)") }
        }
        recoveryErrors = await storage.restore().errors
        reportErrors(errors)
    }

    func remove(id: UUID) async {
        await beginOperation()
        defer { endOperation() }
        guard let photo = photos.first(where: { $0.id == id }) else { return }
        do {
            try await storage.remove(photo)
            photos.removeAll { $0.id == id }
            pendingStatusIDs.remove(id)
            if selectedPhotoID == id { selectedPhotoID = photos.first?.id }
            reportErrors([])
        } catch { reportErrors(["删除照片草稿失败：\(error.localizedDescription)"]) }
    }

    func clear() async {
        await beginOperation()
        defer { endOperation() }
        var errors: [String] = []
        for photo in photos {
            do {
                try await storage.remove(photo)
                photos.removeAll { $0.id == photo.id }
                pendingStatusIDs.remove(photo.id)
            } catch { errors.append("删除照片草稿失败：\(error.localizedDescription)") }
        }
        if !photos.contains(where: { $0.id == selectedPhotoID }) { selectedPhotoID = photos.first?.id }
        reportErrors(errors)
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
                errors.append("照片操作状态未能保存：\(error.localizedDescription)")
            }
        }
        reportErrors(errors)
    }

    private func reportErrors(_ errors: [String]) {
        var messages = recoveryErrors + errors
        if hasPendingDrafts && errors.isEmpty {
            messages.append("部分照片尚未保存到草稿，请勿关闭应用并重试。")
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
