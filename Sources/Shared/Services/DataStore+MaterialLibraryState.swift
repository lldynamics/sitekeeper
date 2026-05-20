import Foundation

@MainActor
extension DataStore {
    private(set) var templates: [ProjectTemplate] {
        get {
            access(keyPath: \.templates)
            return materialLibraryStore.templates
        }
        set {
            withMutation(keyPath: \.templates) {
                materialLibraryStore.setTemplates(newValue)
            }
        }
    }

    private(set) var materialPriceEntries: [MaterialPriceEntry] {
        get {
            access(keyPath: \.materialPriceEntries)
            return materialLibraryStore.materialPriceEntries
        }
        set {
            withMutation(keyPath: \.materialPriceEntries) {
                materialLibraryStore.setMaterialPriceEntries(newValue)
            }
        }
    }

    private(set) var materialSheetDrafts: [MaterialSheetDraft] {
        get {
            access(keyPath: \.materialSheetDrafts)
            return materialLibraryStore.materialSheetDrafts
        }
        set {
            withMutation(keyPath: \.materialSheetDrafts) {
                materialLibraryStore.setMaterialSheetDrafts(newValue)
            }
        }
    }

    private(set) var supplierProfiles: [SupplierProfile] {
        get {
            access(keyPath: \.supplierProfiles)
            return materialLibraryStore.supplierProfiles
        }
        set {
            withMutation(keyPath: \.supplierProfiles) {
                materialLibraryStore.setSupplierProfiles(newValue)
            }
        }
    }

    private(set) var constructionMethods: [ConstructionMethod] {
        get {
            access(keyPath: \.constructionMethods)
            return materialLibraryStore.constructionMethods
        }
        set {
            withMutation(keyPath: \.constructionMethods) {
                materialLibraryStore.setConstructionMethods(newValue)
            }
        }
    }

    private(set) var userMaterials: [UserMaterial] {
        get {
            access(keyPath: \.userMaterials)
            return materialLibraryStore.userMaterials
        }
        set {
            withMutation(keyPath: \.userMaterials) {
                materialLibraryStore.setUserMaterials(newValue)
            }
        }
    }

    private(set) var deletedUserMaterials: [UserMaterial] {
        get {
            access(keyPath: \.deletedUserMaterials)
            return materialLibraryStore.deletedUserMaterials
        }
        set {
            withMutation(keyPath: \.deletedUserMaterials) {
                materialLibraryStore.setDeletedUserMaterials(newValue)
            }
        }
    }
}
