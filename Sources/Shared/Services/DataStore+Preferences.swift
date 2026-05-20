import Foundation

@MainActor
extension DataStore {
    // 用户偏好
    var favoriteMaterialKeys: [String] {
        get {
            access(keyPath: \.favoriteMaterialKeys)
            return userPreferenceStore.favoriteMaterialKeys
        }
        set {
            withMutation(keyPath: \.favoriteMaterialKeys) {
                userPreferenceStore.setFavoriteMaterialKeys(newValue)
            }
        }
    }

    var recentMaterialKeys: [String] {
        get {
            access(keyPath: \.recentMaterialKeys)
            return userPreferenceStore.recentMaterialKeys
        }
        set {
            withMutation(keyPath: \.recentMaterialKeys) {
                userPreferenceStore.setRecentMaterialKeys(newValue)
            }
        }
    }

    var hiddenPresetKeys: Set<String> {
        get {
            access(keyPath: \.hiddenPresetKeys)
            return userPreferenceStore.hiddenPresetKeys
        }
        set {
            withMutation(keyPath: \.hiddenPresetKeys) {
                userPreferenceStore.setHiddenPresetKeys(newValue)
            }
        }
    }
}
