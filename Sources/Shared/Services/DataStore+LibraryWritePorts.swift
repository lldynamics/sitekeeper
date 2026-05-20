import Foundation

@MainActor
extension DataStore {
    func replaceMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        withMutation(keyPath: \.materialPriceEntries) {
            materialLibraryStore.setMaterialPriceEntries(entries)
        }
    }

    func replaceMaterialSheetDrafts(_ drafts: [MaterialSheetDraft]) {
        withMutation(keyPath: \.materialSheetDrafts) {
            materialLibraryStore.setMaterialSheetDrafts(drafts)
        }
    }

    func replaceSupplierProfiles(_ profiles: [SupplierProfile]) {
        withMutation(keyPath: \.supplierProfiles) {
            materialLibraryStore.setSupplierProfiles(profiles)
        }
    }

    func replaceUserMaterials(_ materials: [UserMaterial]) {
        withMutation(keyPath: \.userMaterials) {
            materialLibraryStore.setUserMaterials(materials)
        }
    }

    func replaceDeletedUserMaterials(_ materials: [UserMaterial]) {
        withMutation(keyPath: \.deletedUserMaterials) {
            materialLibraryStore.setDeletedUserMaterials(materials)
        }
    }

    func replaceTemplates(_ templates: [ProjectTemplate]) {
        withMutation(keyPath: \.templates) {
            materialLibraryStore.setTemplates(templates)
        }
    }

    func replaceConstructionMethods(_ methods: [ConstructionMethod]) {
        withMutation(keyPath: \.constructionMethods) {
            materialLibraryStore.setConstructionMethods(methods)
        }
    }
}
