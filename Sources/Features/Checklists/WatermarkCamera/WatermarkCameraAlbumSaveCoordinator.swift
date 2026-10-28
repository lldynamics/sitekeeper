import Foundation
import Photos
import UIKit

struct WatermarkAlbumSaveOutcome: Sendable {
    let result: WatermarkCameraAlbumSaveResult
    let photo: WatermarkCapturedPhoto
    var requiresStatusRetry = false
}

/// A directory gate spans the actual Photos transaction, even when separate windows
/// own separate capture stores. An unresolved durable attempt is never retried silently.
actor WatermarkCameraAlbumSaveCoordinator {
    static let shared = WatermarkCameraAlbumSaveCoordinator()
    private var activeDirectories: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var unrecordedReceipts: [String: WatermarkAlbumReceipt] = [:]

    func acquire(directory: URL) async {
        let key = directory.standardizedFileURL.resolvingSymlinksInPath().path
        if activeDirectories.contains(key) {
            await withCheckedContinuation { waiters[key, default: []].append($0) }
        } else { activeDirectories.insert(key) }
    }

    func release(directory: URL) {
        let key = directory.standardizedFileURL.resolvingSymlinksInPath().path
        if var queued = waiters[key], !queued.isEmpty {
            let next = queued.removeFirst()
            waiters[key] = queued.isEmpty ? nil : queued
            next.resume()
        } else { activeDirectories.remove(key) }
    }

    func save(photo: WatermarkCapturedPhoto, storage: WatermarkCameraDraftStorage, quality: WatermarkExportQuality) async -> WatermarkAlbumSaveOutcome {
        await acquire(directory: storage.directory)
        defer { release(directory: storage.directory) }
        let receiptKey = storage.directory.standardizedFileURL.resolvingSymlinksInPath().path + "/" + photo.id.uuidString
        var current = photo
        do {
            try Task.checkCancellation()
            guard photo.isPersisted else { throw CocoaError(.fileWriteUnknown) }
            // Always re-read after acquiring the gate. A stale window may already be delivered or deleted.
            current = try await storage.latest(photo)
            if let receipt = unrecordedReceipts[receiptKey] {
                current.albumStatus = .completed
                current.albumFailure = nil
                current.albumAssetIdentifier = receipt.assetIdentifier
                current.albumAttemptID = nil
                do {
                    current = try await storage.completeAlbumAttempt(current, receipt: receipt)
                    unrecordedReceipts.removeValue(forKey: receiptKey)
                    return WatermarkAlbumSaveOutcome(result: .success(count: 0), photo: current)
                } catch {
                    return uncertainPersistence(photo: current, error: error)
                }
            }
            if current.albumStatus == .completed { return WatermarkAlbumSaveOutcome(result: .success(count: 0), photo: current) }
            guard current.albumAttemptID == nil else {
                return WatermarkAlbumSaveOutcome(result: .error(message: AppLocalization.string("上次保存相册的结果尚未确认。请先检查相册，再确认已保存或允许重新保存；重新保存可能产生重复照片。")), photo: current)
            }
            // Load/encode before writing the attempt: decoding failure cannot create an uncertain save.
            let data = try current.jpegDataForDelivery(compression: quality.compression)
            try Task.checkCancellation()
            let attemptID = UUID()
            current = try await storage.beginAlbumAttempt(current, attemptID: attemptID)
            if current.albumStatus == .completed { return WatermarkAlbumSaveOutcome(result: .success(count: 0), photo: current) }
            guard current.albumAttemptID == attemptID else {
                return WatermarkAlbumSaveOutcome(result: .error(message: AppLocalization.string("照片正在其他窗口保存，请稍后刷新。")), photo: current)
            }
            let identifier: String
            do {
                identifier = try await Self.write(data)
            } catch {
                if error is WatermarkAlbumUnknownResultError {
                    return uncertainPersistence(photo: current, error: error)
                }
                // Photos explicitly rejected the transaction. Clear the durable attempt before retry is allowed.
                do {
                    current = try await storage.resolveAlbumAttempt(current, retryConfirmed: true)
                    current.albumStatus = .failed
                    current.albumFailure = error.localizedDescription
                    current = try await storage.updateStatus(current)
                } catch let statusError {
                    return uncertainPersistence(photo: current, error: statusError)
                }
                return WatermarkAlbumSaveOutcome(result: .error(message: error.localizedDescription), photo: current)
            }
            let receipt = WatermarkAlbumReceipt(photoID: current.id, attemptID: attemptID, assetIdentifier: identifier, savedAt: Date())
            // Retain completion before touching disk so a failed status write cannot trigger another Photos write.
            unrecordedReceipts[receiptKey] = receipt
            current.albumStatus = .completed
            current.albumFailure = nil
            current.albumAssetIdentifier = identifier
            current.albumAttemptID = nil
            do {
                current = try await storage.completeAlbumAttempt(current, receipt: receipt)
                unrecordedReceipts.removeValue(forKey: receiptKey)
                return WatermarkAlbumSaveOutcome(result: .success(count: 1), photo: current)
            } catch { return uncertainPersistence(photo: current, error: error) }
        } catch {
            return WatermarkAlbumSaveOutcome(result: .error(message: error.localizedDescription), photo: current)
        }
    }

    func resolve(photo: WatermarkCapturedPhoto, storage: WatermarkCameraDraftStorage, retryConfirmed: Bool) async throws -> WatermarkCapturedPhoto {
        await acquire(directory: storage.directory)
        defer { release(directory: storage.directory) }
        let key = storage.directory.standardizedFileURL.resolvingSymlinksInPath().path + "/" + photo.id.uuidString
        if let receipt = unrecordedReceipts[key] {
            // A confirmed Photos success cannot be undone by a stale user retry action.
            let result = try await storage.completeAlbumAttempt(photo, receipt: receipt)
            unrecordedReceipts.removeValue(forKey: key)
            return result
        }
        return try await storage.resolveAlbumAttempt(photo, retryConfirmed: retryConfirmed)
    }

    private func uncertainPersistence(photo: WatermarkCapturedPhoto, error: Error) -> WatermarkAlbumSaveOutcome {
        WatermarkAlbumSaveOutcome(
            result: .error(message: String(format: AppLocalization.string("相册操作状态未能保存，已阻止自动重复保存：%@"), error.localizedDescription)),
            photo: photo, requiresStatusRetry: true
        )
    }

    private static func write(_ data: Data) async throws -> String {
        let identifier = AlbumAssetIdentifierBox()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                identifier.set(request.placeholderForCreatedAsset?.localIdentifier)
            } completionHandler: { success, error in
                if success {
                    if let value = identifier.get() { continuation.resume(returning: value) }
                    else { continuation.resume(throwing: WatermarkAlbumUnknownResultError()) }
                } else { continuation.resume(throwing: error ?? WatermarkPhotoAlbumWriter.WriteError()) }
            }
        }
    }
}

// Photos uses separate change/completion callbacks; every access to this bridge is locked.
private final class AlbumAssetIdentifierBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ value: String?) { lock.withLock { self.value = value } }
    func get() -> String? { lock.withLock { value } }
}

private struct WatermarkAlbumUnknownResultError: LocalizedError {
    var errorDescription: String? { AppLocalization.string("相册已报告保存成功，但未返回照片凭据。请检查相册后确认结果。") }
}
