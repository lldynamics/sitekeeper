import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Observation

@MainActor
@Observable
final class ProjectWarehouseMovementMediaImportHelper {
    var selectedItems: [PhotosPickerItem] = []
    var showImagePicker = false
    var errorMessage = ""
    var showError = false
    private(set) var isImporting = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var status = ""

    @ObservationIgnored
    private var importTask: Task<Void, Never>?

    var progressValue: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    func startImport(
        _ items: [PhotosPickerItem],
        onImported: @escaping @MainActor ([ProjectWarehouseAttachmentDraft]) -> Void
    ) {
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            await self.importMediaItems(items, onImported: onImported)
        }
    }

    func cancelImport() {
        status = String(localized: "正在取消...")
        importTask?.cancel()
    }

    func handleDisappear() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
    }

    private func importMediaItems(
        _ items: [PhotosPickerItem],
        onImported: @escaping @MainActor ([ProjectWarehouseAttachmentDraft]) -> Void
    ) async {
        isImporting = true
        completedCount = 0
        totalCount = items.count
        status = String(format: String(localized: "正在导入 %lld/%lld"), Int64(0), Int64(max(items.count, 1)))

        var imported: [ProjectWarehouseAttachmentDraft] = []
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                break
            }
            status = String(format: String(localized: "正在导入 %lld/%lld"), Int64(index + 1), Int64(max(items.count, 1)))

            if isVideoItem(item) {
                do {
                    if let videoTransfer = try await item.loadTransferable(type: ProjectWarehouseVideoTransfer.self) {
                        imported.append(
                            ProjectWarehouseAttachmentDraft(
                                fileURL: videoTransfer.fileURL,
                                title: videoTransfer.originalName,
                                note: String(localized: "来源: 相册视频"),
                                cleanupAfterImport: true
                            )
                        )
                    }
                } catch let error as ProjectWarehouseVideoTransferError {
                    presentError(error.userMessage)
                } catch {
                    presentError(String(localized: "视频导入失败。"))
                }
            } else {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    presentError(String(localized: "图片导入失败。"))
                    completedCount = index + 1
                    continue
                }
                imported.append(ProjectWarehouseAttachmentDraft(image: image, title: String(localized: "相册照片")))
            }

            completedCount = index + 1
        }

        if !Task.isCancelled {
            onImported(imported)
        }
        selectedItems = []
        completedCount = totalCount
        status = Task.isCancelled ? String(localized: "已取消导入") : String(localized: "导入完成")
        importTask = nil
        isImporting = false
    }

    private func isVideoItem(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
