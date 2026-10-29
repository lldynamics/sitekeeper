import SwiftUI

struct MaterialLibraryListView: View {
    let usesPhoneWorkspaceSurface: Bool
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
                Section(AppLocalization.string("materials.library.recentSearches.section")) {
                    ForEach(recentSearchKeywords, id: \.self) { term in
                        Button {
                            onSelectRecentSearch(term)
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(AppLocalization.string("materials.library.remove.button"), role: .destructive) {
                                onRemoveRecentSearch(term)
                            }
                        }
                    }
                }
                .listRowBackground(phoneRowBackground)
            }

            if !recentMaterials.isEmpty && searchText.isEmpty {
                Section(AppLocalization.string("materials.library.recentlyUsed.section")) {
                    ForEach(recentMaterials) { item in
                        switch item.source {
                        case .preset(let material):
                            presetRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(AppLocalization.string("materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(AppLocalization.string("materials.library.deleteMaterial.button"), role: .destructive) {
                                        onDeletePresetMaterial(material)
                                    }
                                }
                        case .user(let material):
                            userRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(AppLocalization.string("materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(AppLocalization.string("common.delete"), role: .destructive) {
                                        onDeleteUserMaterial(material)
                                    }
                                }
                        }
                    }
                }
                .listRowBackground(phoneRowBackground)
            }

            if !filteredUser.isEmpty {
                Section(AppLocalization.string("materials.library.customMaterials.section")) {
                    ForEach(filteredUser) { item in
                        userRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(AppLocalization.string("common.delete"), role: .destructive) {
                                    onDeleteUserMaterial(item)
                                }
                            }
                    }
                }
                .listRowBackground(phoneRowBackground)
            }

            Section(
                searchText.isEmpty
                    ? AppLocalization.string("materials.library.allMaterials.section")
                    : AppLocalization.string("materials.library.searchResults.section")
            ) {
                ForEach(filteredPreset) { item in
                    presetRow(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(AppLocalization.string("materials.library.deleteMaterial.button"), role: .destructive) {
                                onDeletePresetMaterial(item)
                            }
                        }
                }
            }
            .listRowBackground(phoneRowBackground)

            if showRecycleBin {
                Section(AppLocalization.string("materials.library.recycleBin.section")) {
                    ForEach(hiddenPresetKeys, id: \.self) { key in
                        deletedPresetRow(key)
                    }
                    ForEach(deletedUserMaterials) { item in
                        deletedUserRow(item)
                    }
                }
                .listRowBackground(phoneRowBackground)
            }
        }
        .scrollContentBackground(usesPhoneWorkspaceSurface ? .hidden : .automatic)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(AppLocalization.string("materials.library.search.prompt"))
        )
        .onSubmit(of: .search) {
            onSubmitSearch()
        }
    }

    private var phoneRowBackground: Color? {
        usesPhoneWorkspaceSurface ? Color(.secondarySystemBackground) : nil
    }
}
