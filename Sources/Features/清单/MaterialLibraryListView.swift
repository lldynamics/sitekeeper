import SwiftUI

struct MaterialLibraryListView: View {
    let recentSearchKeywords: [String]
    @Binding var searchText: String
    let recentMaterials: [RecentMaterialItem]
    let filteredUser: [UserMaterial]
    let filteredPreset: [CommonMaterial]
    let showRecycleBin: Bool
    let hiddenPresetKeys: [String]
    let deletedUserMaterials: [UserMaterial]
    let onSelectRecentSearch: (String) -> Void
    let onRemoveRecentSearch: (String) -> Void
    let onRemoveRecentMaterial: (String) -> Void
    let onDeletePresetMaterial: (CommonMaterial) -> Void
    let onDeleteUserMaterial: (UserMaterial) -> Void
    let presetRow: (CommonMaterial) -> AnyView
    let userRow: (UserMaterial) -> AnyView
    let deletedPresetRow: (String) -> AnyView
    let deletedUserRow: (UserMaterial) -> AnyView
    let onSubmitSearch: () -> Void

    var body: some View {
        List {
            if !recentSearchKeywords.isEmpty && searchText.isEmpty {
                Section(String(localized: "materials.library.recentSearches.section")) {
                    ForEach(recentSearchKeywords, id: \.self) { term in
                        Button {
                            onSelectRecentSearch(term)
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(String(localized: "materials.library.remove.button"), role: .destructive) {
                                onRemoveRecentSearch(term)
                            }
                        }
                    }
                }
            }

            if !recentMaterials.isEmpty && searchText.isEmpty {
                Section(String(localized: "materials.library.recentlyUsed.section")) {
                    ForEach(recentMaterials) { item in
                        switch item.source {
                        case .preset(let material):
                            presetRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(String(localized: "materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(String(localized: "materials.library.deleteMaterial.button"), role: .destructive) {
                                        onDeletePresetMaterial(material)
                                    }
                                }
                        case .user(let material):
                            userRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(String(localized: "materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(String(localized: "common.delete"), role: .destructive) {
                                        onDeleteUserMaterial(material)
                                    }
                                }
                        }
                    }
                }
            }

            if !filteredUser.isEmpty {
                Section(String(localized: "materials.library.customMaterials.section")) {
                    ForEach(filteredUser) { item in
                        userRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(String(localized: "common.delete"), role: .destructive) {
                                    onDeleteUserMaterial(item)
                                }
                            }
                    }
                }
            }

            Section(
                searchText.isEmpty
                    ? String(localized: "materials.library.allMaterials.section")
                    : String(localized: "materials.library.searchResults.section")
            ) {
                ForEach(filteredPreset) { item in
                    presetRow(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(String(localized: "materials.library.deleteMaterial.button"), role: .destructive) {
                                onDeletePresetMaterial(item)
                            }
                        }
                }
            }

            if showRecycleBin {
                Section(String(localized: "materials.library.recycleBin.section")) {
                    ForEach(hiddenPresetKeys, id: \.self) { key in
                        deletedPresetRow(key)
                    }
                    ForEach(deletedUserMaterials) { item in
                        deletedUserRow(item)
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(String(localized: "materials.library.search.prompt"))
        )
        .onSubmit(of: .search) {
            onSubmitSearch()
        }
    }
}
