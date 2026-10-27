import Foundation

@MainActor
extension DataStore {
    func replaceMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        materialLibraryStore.setMaterialPriceEntries(entries)
    }

    func replaceMaterialSheetDrafts(_ drafts: [MaterialSheetDraft]) {
        materialLibraryStore.setMaterialSheetDrafts(drafts)
    }

    func replaceSupplierProfiles(_ profiles: [SupplierProfile]) {
        materialLibraryStore.setSupplierProfiles(profiles)
    }

    func replaceUserMaterials(_ materials: [UserMaterial]) {
        materialLibraryStore.setUserMaterials(materials)
    }

    func replaceDeletedUserMaterials(_ materials: [UserMaterial]) {
        materialLibraryStore.setDeletedUserMaterials(materials)
    }

    func replaceTemplates(_ templates: [ProjectTemplate]) {
        materialLibraryStore.setTemplates(templates)
    }

    func replaceConstructionMethods(_ methods: [ConstructionMethod]) {
        materialLibraryStore.setConstructionMethods(methods)
    }
}
