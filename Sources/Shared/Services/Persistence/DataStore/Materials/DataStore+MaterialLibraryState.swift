import Foundation

@MainActor
extension DataStore {
    private(set) var templates: [ProjectTemplate] {
        get {
            return materialLibraryStore.templates
        }
        set {
            materialLibraryStore.setTemplates(newValue)
        }
    }

    private(set) var materialPriceEntries: [MaterialPriceEntry] {
        get {
            return materialLibraryStore.materialPriceEntries
        }
        set {
            materialLibraryStore.setMaterialPriceEntries(newValue)
        }
    }

    private(set) var materialSheetDrafts: [MaterialSheetDraft] {
        get {
            return materialLibraryStore.materialSheetDrafts
        }
        set {
            materialLibraryStore.setMaterialSheetDrafts(newValue)
        }
    }

    private(set) var supplierProfiles: [SupplierProfile] {
        get {
            return materialLibraryStore.supplierProfiles
        }
        set {
            materialLibraryStore.setSupplierProfiles(newValue)
        }
    }

    private(set) var constructionMethods: [ConstructionMethod] {
        get {
            return materialLibraryStore.constructionMethods
        }
        set {
            materialLibraryStore.setConstructionMethods(newValue)
        }
    }

    private(set) var userMaterials: [UserMaterial] {
        get {
            return materialLibraryStore.userMaterials
        }
        set {
            materialLibraryStore.setUserMaterials(newValue)
        }
    }

    private(set) var deletedUserMaterials: [UserMaterial] {
        get {
            return materialLibraryStore.deletedUserMaterials
        }
        set {
            materialLibraryStore.setDeletedUserMaterials(newValue)
        }
    }
}
