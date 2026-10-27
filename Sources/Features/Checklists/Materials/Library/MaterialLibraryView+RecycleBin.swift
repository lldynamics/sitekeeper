import SwiftUI

extension MaterialLibraryView {
    var deleteConfirmMessage: String {
        MaterialLibraryLogicHelpers.deleteConfirmMessage(for: pendingDeleteTarget)
    }

    func deletedPresetRow(key: String) -> some View {
        MaterialLibraryDeletedPresetRow(key: key) {
            store.hiddenPresetKeys.remove(key)
            store.scheduleSave()
        }
    }

    func deletedUserRow(_ item: UserMaterial) -> some View {
        MaterialLibraryDeletedUserRow(item: item) {
            store.removeDeletedUserMaterials(ids: Set([item.id]))
            store.appendUserMaterial(item)
            store.scheduleSave()
        }
    }

    func requestDeletePresetMaterial(_ item: CommonMaterial) {
        pendingDeleteTarget = .preset(item)
        showDeleteConfirm = true
    }

    func requestDeleteUserMaterial(_ item: UserMaterial) {
        pendingDeleteTarget = .user(item)
        showDeleteConfirm = true
    }

    func confirmPendingDeleteMaterial() {
        guard let pendingDeleteTarget else { return }
        switch pendingDeleteTarget {
        case .preset(let item):
            MaterialLibraryLogicHelpers.hidePresetMaterial(item, store: store)
        case .user(let item):
            MaterialLibraryLogicHelpers.deleteUserMaterial(
                item,
                store: store,
                undoableDeletion: undoableDeletion,
                notice: $operationNotice
            )
        }
        self.pendingDeleteTarget = nil
    }
}
