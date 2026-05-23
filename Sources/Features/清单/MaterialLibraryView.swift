import SwiftUI

struct MaterialLibraryView: View {
    @Environment(DataStore.self) var store
    @Environment(MaterialLibraryStore.self) private var materialLibraryStore
    @Environment(ProjectStore.self) private var projectStore
    @Environment(UserPreferenceStore.self) private var userPreferenceStore
    @State private var categoryState = MaterialLibraryCategoryState()
    @State var priceFilter: MaterialPriceFilter = .all
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State var priceEditorContext: MaterialPriceEditorContext?
    @State var appendState = MaterialLibraryAppendState()
    @State var pendingDeleteTarget: MaterialLibraryPendingDeleteTarget?
    @State var showDeleteConfirm = false
    @State var operationMessage: String?
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var batchState = MaterialLibraryBatchSelectionState()
    @FocusState private var appendMaterialFocusedField: AppendMaterialField?
    @AppStorage(UserPreferenceKeys.recentMaterialSearches) private var recentSearchKeywordsRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryPromptAfterAdd) var promptAfterAdd = true
    @AppStorage(UserPreferenceKeys.materialLibraryLastTargetMode) var lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
    @AppStorage(UserPreferenceKeys.materialLibraryLastDraftID) var lastAppendDraftIDRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryLastProjectID) var lastAppendProjectIDRaw = ""

    var materialPriceEntries: [MaterialPriceEntry] { materialLibraryStore.materialPriceEntries }
    var userMaterials: [UserMaterial] { materialLibraryStore.userMaterials }
    var deletedUserMaterials: [UserMaterial] { materialLibraryStore.deletedUserMaterials }
    private var supplierProfiles: [SupplierProfile] { materialLibraryStore.supplierProfiles }
    var materialSheetDrafts: [MaterialSheetDraft] { materialLibraryStore.materialSheetDrafts }
    var recentMaterialKeys: [String] { userPreferenceStore.recentMaterialKeys }
    var hiddenPresetKeys: Set<String> { userPreferenceStore.hiddenPresetKeys }
    var projects: [Project] { projectStore.projects }

    private var visiblePresetMaterials: [CommonMaterial] {
        MaterialLibrary.all.filter { !isPresetHidden($0) }
    }

    var priceEntryByKey: [String: MaterialPriceEntry] {
        var map: [String: MaterialPriceEntry] = [:]
        for entry in materialPriceEntries {
            let key = materialKey(name: entry.name, specification: entry.specification, unit: entry.unit)
            if map[key] == nil {
                map[key] = entry
            }
        }
        return map
    }

    var normalizedSearchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var recentSearchKeywords: [String] {
        MaterialLibraryLogicHelpers.recentSearchKeywords(from: recentSearchKeywordsRaw)
    }

    private var filteredPreset: [CommonMaterial] {
        visiblePresetMaterials.filter { item in
            if let cat = categoryState.selectedCategory, item.category.rawValue != cat {
                return false
            }
            let entry = priceEntry(for: item)
            guard matchesPriceFilter(entry) else { return false }
            return matchesSearch(
                item,
                extraFields: [
                    entry?.brand ?? "",
                    entry?.supplier ?? "",
                    entry?.category ?? "",
                    entry?.note ?? "",
                ]
            )
        }
    }

    private var filteredUser: [UserMaterial] {
        userMaterials.filter { item in
            if let cat = categoryState.selectedCategory, normalizedCategory(item.category) != cat {
                return false
            }
            let entry = priceEntry(forUser: item)
            guard matchesPriceFilter(entry) else { return false }
            return matchesSearch(
                item,
                extraFields: [
                    entry?.brand ?? "",
                    entry?.supplier ?? "",
                    entry?.category ?? "",
                    entry?.note ?? "",
                ]
            )
        }
    }

    private var availableCategories: [String] {
        let preset = MaterialCategory.allCases.map(\.rawValue)
        let presetSet = Set(preset)
        let dynamic = Set(
            (userMaterials.map(\.category) + materialPriceEntries.map(\.category))
                .map(normalizedCategory)
                .filter { !$0.isEmpty }
        )
        let custom = dynamic.subtracting(presetSet).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return preset + custom
    }

    private var recentMaterials: [RecentMaterialItem] {
        recentMaterialKeys.prefix(5).compactMap { key in
            if let preset = MaterialLibrary.all.first(where: {
                materialKey($0) == key || legacyMaterialKey($0) == key
            }) {
                return RecentMaterialItem(key: key, source: .preset(preset))
            }
            if let userMaterial = userMaterials.first(where: {
                let normalized = materialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                let legacy = legacyMaterialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                return normalized == key || legacy == key
            }) {
                return RecentMaterialItem(key: key, source: .user(userMaterial))
            }
            return nil
        }
    }

    var showRecycleBin: Bool {
        !deletedUserMaterials.isEmpty || !hiddenPresetKeys.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            MaterialLibraryFilterBar(
                selectedCategory: categoryState.selectedCategory,
                availableCategories: availableCategories,
                priceFilter: priceFilter,
                onSelectCategory: { category in
                    categoryState.selectedCategory = category
                },
                onSelectPriceFilter: { filter in
                    priceFilter = filter
                },
                onOpenCategoryManager: {
                    categoryState.showCategoryManager = true
                }
            )
            .background(.ultraThinMaterial)

            defaultMaterialSheetTargetBar

            MaterialLibraryListView(
                recentSearchKeywords: recentSearchKeywords,
                searchText: $searchText,
                recentMaterials: recentMaterials,
                filteredUser: filteredUser,
                filteredPreset: filteredPreset,
                showRecycleBin: showRecycleBin,
                hiddenPresetKeys: Array(hiddenPresetKeys),
                deletedUserMaterials: deletedUserMaterials,
                onSelectRecentSearch: { term in
                    searchText = term
                },
                onRemoveRecentSearch: { term in
                    removeRecentSearchKeyword(term)
                },
                onRemoveRecentMaterial: { key in
                    removeRecentKey(key)
                },
                onDeletePresetMaterial: { item in
                    requestDeletePresetMaterial(item)
                },
                onDeleteUserMaterial: { item in
                    requestDeleteUserMaterial(item)
                },
                presetRow: { item in
                    AnyView(presetMaterialRow(item))
                },
                userRow: { item in
                    AnyView(userMaterialRow(item))
                },
                deletedPresetRow: { key in
                    AnyView(deletedPresetRow(key: key))
                },
                deletedUserRow: { item in
                    AnyView(deletedUserRow(item))
                },
                onSubmitSearch: {
                    rememberRecentSearchKeyword()
                }
            )
        }
        .navigationTitle(String(localized: "materials.library.title"))
        .toolbar {
            if batchState.isBatchSelectionMode {
                Button(String(localized: "common.cancel")) {
                    exitBatchSelectionMode()
                }
                Button {
                    openBatchAppendSheet()
                } label: {
                    Label(String(localized: "materials.library.batchAppend.button"), systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(selectedBatchMaterialContexts.isEmpty)
            } else {
                Button(String(localized: "materials.library.batchSelection.button")) {
                    batchState.isBatchSelectionMode = true
                }
                Button { showAddSheet = true } label: { Image(systemName: "plus").visibleIconStyle() }.accessibilityLabel(String(localized: "materials.library.addCustomMaterial.accessibility"))
            }
        }
        .materialLibrarySheetPresentations(
            showAddSheet: $showAddSheet,
            initialCategory: categoryState.selectedCategory,
            availableCategories: availableCategories,
            onAddMaterial: handleAddMaterialSave,
            priceEditorContext: $priceEditorContext,
            supplierProfiles: supplierProfiles,
            onSavePriceEntry: { updated in
                upsertMaterialPriceEntry(updated)
                priceEditorContext = nil
            },
            onDeletePriceEntry: { target in
                handleDeletePriceEntry(target)
                priceEditorContext = nil
            },
            pendingAddContext: $appendState.pendingAddContext,
            activeMaterialSheetDrafts: activeMaterialSheetDrafts,
            projects: projects,
            draftPickerTitle: { draft in
                MaterialLibraryLogicHelpers.materialSheetDraftPickerTitle(draft, projects: projects)
            },
            pendingAddQuantity: $appendState.pendingAddQuantity,
            pendingAddUnitPrice: $appendState.pendingAddUnitPrice,
            pendingAddNote: $appendState.pendingAddNote,
            pendingAddTargetMode: $appendState.pendingAddTargetMode,
            pendingAddDraftID: $appendState.pendingAddDraftId,
            pendingAddDraftTitle: $appendState.pendingAddDraftTitle,
            pendingAddProjectID: $appendState.pendingAddProjectId,
            appendMaterialFocusedField: $appendMaterialFocusedField,
            operationMessage: $operationMessage,
            canAppendMaterialToSheet: canAppendMaterialToSheet,
            onCancelAppend: {
                appendState.pendingAddContext = nil
            },
            onConfirmAppend: { context in
                appendMaterialsToSheet(
                    [context],
                    quantityText: appendState.pendingAddQuantity,
                    showPostAddPrompt: false,
                    deferToastUntilSheetDismissal: true
                ) { _ in
                    appendState.pendingAddUnitPrice
                }
            },
            onEnsureExistingDraftSelectionForAppend: {
                appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
            },
            pendingBatchAddContext: $batchState.pendingBatchAddContext,
            pendingBatchAddQuantity: $batchState.pendingBatchAddQuantity,
            onCancelBatchAppend: {
                batchState.pendingBatchAddContext = nil
            },
            onConfirmBatchAppend: { context in
                let appended = confirmAppendMaterials(
                    context.materials,
                    quantityText: batchState.pendingBatchAddQuantity,
                    deferToastUntilSheetDismissal: true
                )
                guard appended else { return false }
                batchState.selectedMaterialContextsByKey = [:]
                return true
            },
            onEnsureExistingDraftSelectionForBatch: {
                appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
            },
            showCategoryManager: $categoryState.showCategoryManager
        )
        .onChange(of: categoryState.showCategoryManager) { _, isShowing in
            if !isShowing, let selectedCategory = categoryState.selectedCategory, !availableCategories.contains(selectedCategory) {
                categoryState.selectedCategory = nil
            }
        }
        .confirmationDialog(String(localized: "materials.library.deleteDialog.title"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(String(localized: "common.delete"), role: .destructive) {
                confirmPendingDeleteMaterial()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingDeleteTarget = nil
            }
        } message: {
            Text(deleteConfirmMessage)
        }
        .operationToast(message: $operationMessage)
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .safeAreaInset(edge: .bottom) {
            if batchState.isBatchSelectionMode {
                batchAppendActionBar
            }
        }
        .alert(String(localized: "materials.library.addedAlert.title"), isPresented: $appendState.showOpenMaterialSheetPrompt) {
            Button(String(localized: "materials.library.doNotShowAgain.button")) {
                promptAfterAdd = false
            }
            Button(String(localized: "materials.library.later.button"), role: .cancel) {}
            Button(String(localized: "materials.library.goToMaterialSheet.button")) {
                appendState.navigateToMaterialSheet = true
            }
        } message: {
            let title = appendState.recentlyAddedDraftTitle.isEmpty ? String(localized: "materials.library.untitledMaterialSheet") : appendState.recentlyAddedDraftTitle
            if appendState.recentlyAddedItemCount > 1 {
                Text(
                    String(
                        format: String(localized: "materials.library.addedMultiple.format"),
                        appendState.recentlyAddedItemCount,
                        title
                    )
                )
            } else {
                Text(String(format: String(localized: "materials.library.addedSingle.format"), title))
            }
        }
        .navigationDestination(isPresented: $appendState.navigateToMaterialSheet) {
            MaterialSheetView(initialDraftID: appendState.recentlyAddedDraftID)
        }
        .onAppear {
            ensureDefaultMaterialSheetSelection()
        }
        .onChange(of: activeMaterialSheetDraftIDs) { _, _ in
            ensureDefaultMaterialSheetSelection()
        }
        .onChange(of: appendState.selectedDefaultMaterialSheetDraftID) { _, newValue in
            guard let newValue else {
                lastAppendDraftIDRaw = ""
                return
            }
            guard let draft = activeMaterialSheetDrafts.first(where: { $0.id == newValue }) else { return }
            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = newValue.uuidString
            lastAppendProjectIDRaw = draft.projectId?.uuidString ?? ""
        }
        .onChange(of: pendingAddContextID, initial: false, handlePendingAddContextChange)
        .onChange(of: pendingBatchAddContextID, initial: false, handlePendingBatchAddContextChange)
    }

    func appendRecentMaterialKey(_ key: String) {
        store.recentMaterialKeys = MaterialLibraryLogicHelpers.appendingRecentMaterialKey(
            key,
            to: recentMaterialKeys
        )
    }

    private func removeRecentKey(_ key: String) {
        store.recentMaterialKeys = MaterialLibraryLogicHelpers.removingRecentMaterialKey(
            key,
            from: recentMaterialKeys
        )
        store.scheduleSave()
    }

    private func rememberRecentSearchKeyword() {
        recentSearchKeywordsRaw = MaterialLibraryLogicHelpers.rememberRecentSearchKeyword(
            searchText: normalizedSearchKeyword,
            currentRaw: recentSearchKeywordsRaw
        )
    }

    private func removeRecentSearchKeyword(_ term: String) {
        recentSearchKeywordsRaw = MaterialLibraryLogicHelpers.removeRecentSearchKeyword(
            term: term,
            from: recentSearchKeywordsRaw
        )
    }
}
