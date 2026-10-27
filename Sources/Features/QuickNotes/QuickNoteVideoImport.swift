import Foundation
import CoreTransferable

struct QuickNoteVideoTransfer: Transferable {
    static let maxVideoBytes = ImportLimitPolicy.maxImportBytes
    static let maxDurationSeconds: Double = 5 * 60

    let fileName: String
    let originalName: String
    let byteSize: Int
    let durationSeconds: Double?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let source = received.file
            let sourceSize = QuickNoteAttachmentStorage.fileSize(at: source)
            if sourceSize > maxVideoBytes {
                throw QuickNoteVideoTransferError.tooLarge(sourceSize)
            }
            let result = try await QuickNoteAttachmentStorage.importVideoOrThrow(from: source)
            if let duration = result.durationSeconds, duration > maxDurationSeconds {
                do {
                    try DataStoreDeferredFileCleanup.deleteQuickNoteAttachmentFilesOrThrow(
                        [result.fileName],
                        summary: "quickNoteVideoImport.durationRollback"
                    )
                } catch {
                    StorageIssueLog.recordEvent(
                        "quick_note.video_duration_rollback_delete_failed",
                        category: .fileStorage,
                        details: [
                            "source": "QuickNoteVideoTransfer.transferRepresentation",
                            "file_name": result.fileName
                        ],
                        error: error
                    )
                }
                throw QuickNoteVideoTransferError.tooLong(duration)
            }
            return QuickNoteVideoTransfer(
                fileName: result.fileName,
                originalName: result.originalName,
                byteSize: result.byteSize,
                durationSeconds: result.durationSeconds
            )
        }
    }
}

enum QuickNoteVideoTransferError: LocalizedError {
    case tooLarge(Int)
    case tooLong(Double)

    var userMessage: String {
        switch self {
        case .tooLarge(let size):
            return ImportLimitPolicy.genericTooLargeMessage(itemName: "视频", size: size, limit: QuickNoteVideoTransfer.maxVideoBytes)
        case .tooLong(let seconds):
            let minutes = Int(ceil(seconds / 60))
            return "视频过长（约 \(minutes) 分钟），请控制在 5 分钟内。"
        }
    }
}
