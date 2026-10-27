import Foundation

@MainActor
extension DataStore {
    // 用户偏好
    var favoriteMaterialKeys: [String] {
        get {
            return materialLibraryPreferencesStore.favoriteMaterialKeys
        }
        set {
            materialLibraryPreferencesStore.setFavoriteMaterialKeys(newValue)
        }
    }

    var recentMaterialKeys: [String] {
        get {
            return materialLibraryPreferencesStore.recentMaterialKeys
        }
        set {
            materialLibraryPreferencesStore.setRecentMaterialKeys(newValue)
        }
    }

    var hiddenPresetKeys: Set<String> {
        get {
            return materialLibraryPreferencesStore.hiddenPresetKeys
        }
        set {
            materialLibraryPreferencesStore.setHiddenPresetKeys(newValue)
        }
    }
}
