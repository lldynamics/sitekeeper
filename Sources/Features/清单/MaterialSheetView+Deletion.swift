import SwiftUI
import PhotosUI

extension MaterialSheetView {
    func photoSelectionBinding(for itemId: UUID) -> Binding<[PhotosPickerItem]> {
        Binding(
            get: { rowPhotoSelections[itemId] ?? [] },
            set: { newItems in
                rowPhotoSelections[itemId] = newItems
                guard !newItems.isEmpty else { return }
                Task {
                    await attachSelectedPhoto(itemId: itemId, items: newItems)
                }
            }
        )
    }

    @MainActor
    func attachSelectedPhoto(itemId: UUID, items: [PhotosPickerItem]) async {
        defer {
            rowPhotoSelections[itemId] = []
        }
        guard let first = items.first else { return }
        guard let data = try? await first.loadTransferable(type: Data.self) else { return }
        guard let idx = sheetItems.firstIndex(where: { $0.id == itemId }) else { return }
        sheetItems[idx].attachmentData = data
        sheetItems[idx].attachmentFileName = "照片.jpg"
    }

    func requestDeleteSheetItems(ids: [UUID]) {
        let normalizedIDs = MaterialSheetLogicHelpers.normalizedDeleteIDs(ids)
        guard !normalizedIDs.isEmpty else { return }
        pendingDeleteSheetItemIDs = normalizedIDs
        showDeleteItemConfirm = true
    }

    func confirmDeleteSheetItems() {
        let ids = pendingDeleteSheetItemIDs
        guard !ids.isEmpty else { return }
        let count = MaterialSheetLogicHelpers.deletedItemCount(ids: ids, sheetItems: sheetItems)
        queueSheetItemDeletion(
            ids: ids,
            message: String(format: String(localized: "已删除 %lld 项材料单项目"), Int64(count)),
            auditSummary: String(format: String(localized: "删除材料单项目 %lld 项"), Int64(count))
        )
        pendingDeleteSheetItemIDs.removeAll()
    }

    func clearCurrentSheetItemsWithUndo(
        message: String = String(localized: "已清空材料单"),
        auditSummary: String? = nil
    ) {
        let ids = Set(sheetItems.map(\.id))
        guard !ids.isEmpty else { return }
        queueSheetItemDeletion(
            ids: ids,
            message: message,
            auditSummary: auditSummary ?? String(format: String(localized: "清空材料单 %lld 项"), Int64(ids.count))
        )
    }

    func queueSheetItemDeletion(ids: Set<UUID>, message: String, auditSummary: String) {
        let snapshot = sheetItems
        let deletedItems = snapshot.filter { ids.contains($0.id) }
        guard !deletedItems.isEmpty else { return }

        let previousExpanded = itemExpanded
        let previousPhotoSelections = rowPhotoSelections
        sheetItems.removeAll { ids.contains($0.id) }
        itemExpanded.subtract(ids)
        rowPhotoSelections = rowPhotoSelections.filter { !ids.contains($0.key) }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            undoMessage: String(localized: "已恢复材料单内容"),
            commit: {
                persistCurrentDraft()
            },
            undo: {
                sheetItems = UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: sheetItems,
                    deletedIDs: ids
                )
                itemExpanded = previousExpanded
                rowPhotoSelections = previousPhotoSelections
                persistCurrentDraft()
            },
            audit: UndoableDeletionAuditContext(
                summary: auditSummary,
                detail: materialSheetItemAuditDetail(deletedItems),
                source: "MaterialSheetView"
            )
        )
    }

    func materialSheetItemAuditDetail(_ items: [MaterialSheetItem]) -> String {
        MaterialSheetLogicHelpers.materialSheetItemAuditDetail(items)
    }
}
