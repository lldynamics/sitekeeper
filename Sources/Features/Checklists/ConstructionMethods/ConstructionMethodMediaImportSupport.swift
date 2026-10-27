import AVFoundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum ConstructionMethodMediaImportSupport {
    static var importingMessage: String {
        AppLocalization.string("正在导入教程媒体...")
    }

    static var checkingVideoMessage: String {
        AppLocalization.string("检查视频大小和时长...")
    }

    static var videoImportFailedMessage: String {
        AppLocalization.string("视频导入失败。")
    }

    static func imageSaveFailedMessage(_ error: Error) -> String {
        String(format: AppLocalization.string("教程图片保存失败：%@"), error.localizedDescription)
    }

    @MainActor static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await PermissionRequestTimeoutSupport.resolve(fallback: false) { resume in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    resume(granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func makeImageAttachment(from image: UIImage) throws -> QuickNoteAttachment {
        let fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
        return QuickNoteAttachment(kind: .photo, fileName: fileName)
    }

    static func removeAttachment(
        _ attachment: QuickNoteAttachment,
        from attachments: inout [QuickNoteAttachment],
        sessionAddedFileNames: inout Set<String>,
        summary: String
    ) {
        attachments.removeAll { $0.id == attachment.id }
        guard sessionAddedFileNames.contains(attachment.fileName) else { return }
        DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
            [attachment.fileName],
            summary: summary
        )?.perform()
        sessionAddedFileNames.remove(attachment.fileName)
    }

    static func importMediaItems(
        _ items: [PhotosPickerItem],
        setProgressMessage: @escaping @MainActor @Sendable (String) -> Void,
        appendAttachment: @escaping @MainActor @Sendable (QuickNoteAttachment) -> Void,
        reportError: @escaping @MainActor @Sendable (String) -> Void
    ) async -> Set<String> {
        var importedFileNames: Set<String> = []
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                await setProgressMessage(checkingVideoMessage)
                do {
                    guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                        await reportError(videoImportFailedMessage)
                        continue
                    }
                    let attachment = QuickNoteAttachment(
                        kind: .video,
                        fileName: transfer.fileName,
                        originalName: transfer.originalName,
                        durationSeconds: transfer.durationSeconds
                    )
                    await MainActor.run {
                        _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
                    }
                    await appendAttachment(attachment)
                    importedFileNames.insert(transfer.fileName)
                } catch let error as QuickNoteVideoTransferError {
                    await reportError(error.userMessage)
                } catch {
                    await reportError(videoImportFailedMessage)
                }
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await reportError(AppLocalization.string("有一项图片导入失败。"))
                continue
            }

            do {
                let attachment = try makeImageAttachment(from: image)
                await appendAttachment(attachment)
                importedFileNames.insert(attachment.fileName)
            } catch {
                await reportError(imageSaveFailedMessage(error))
            }
        }
        return importedFileNames
    }
}
