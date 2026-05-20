import SwiftUI

struct MaterialLibraryView: View {
    @Environment(DataStore.self) private var store
    @State private var categoryState = MaterialLibraryCategoryState()
    @State private var priceFilter: MaterialPriceFilter = .all
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var priceEditorContext: MaterialPriceEditorContext?
    @State private var appendState = MaterialLibraryAppendState()
    @State private var pendingDeleteTarget: MaterialLibraryPendingDeleteTarget?
    @State private var showDeleteConfirm = false
    @State private var operationMessage: String?
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var batchState = MaterialLibraryBatchSelectionState()
    @FocusState private var appendMaterialFocusedField: AppendMaterialField?
    @AppStorage("recentMaterialSearches") private var recentSearchKeywordsRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryPromptAfterAdd) private var promptAfterAdd = true
    @AppStorage(UserPreferenceKeys.materialLibraryLastTargetMode) private var lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
    @AppStorage(UserPreferenceKeys.materialLibraryLastDraftID) private var lastAppendDraftIDRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryLastProjectID) private var lastAppendProjectIDRaw = ""

    private var visiblePresetMaterials: [CommonMaterial] {
        MaterialLibrary.all.filter { !isPresetHidden($0) }
    }

    private var priceEntryByKey: [String: MaterialPriceEntry] {
        var map: [String: MaterialPriceEntry] = [:]
        for entry in store.materialPriceEntries {
            let key = materialKey(name: entry.name, specification: entry.specification, unit: entry.unit)
            if map[key] == nil {
                map[key] = entry
            }
        }
        return map
    }

    private var normalizedSearchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentSearchKeywords: [String] {
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
        store.userMaterials.filter { item in
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
            (store.userMaterials.map(\.category) + store.materialPriceEntries.map(\.category))
                .map(normalizedCategory)
                .filter { !$0.isEmpty }
        )
        let custom = dynamic.subtracting(presetSet).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return preset + custom
    }

    private var recentMaterials: [RecentMaterialItem] {
        store.recentMaterialKeys.prefix(5).compactMap { key in
            if let preset = MaterialLibrary.all.first(where: {
                materialKey($0) == key || legacyMaterialKey($0) == key
            }) {
                return RecentMaterialItem(key: key, source: .preset(preset))
            }
            if let userMaterial = store.userMaterials.first(where: {
                let normalized = materialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                let legacy = legacyMaterialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                return normalized == key || legacy == key
            }) {
                return RecentMaterialItem(key: key, source: .user(userMaterial))
            }
            return nil
        }
    }

    private var showRecycleBin: Bool {
        !store.deletedUserMaterials.isEmpty || !store.hiddenPresetKeys.isEmpty
    }

    private var selectedBatchMaterialContexts: [PendingMaterialAppendContext] {
        batchState.selectedMaterialContextsByKey.values
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    private var defaultTargetMaterialSheetDraft: MaterialSheetDraft? {
        MaterialLibraryLogicHelpers.defaultTargetDraft(
            activeDrafts: activeMaterialSheetDrafts,
            selectedDefaultDraftID: appendState.selectedDefaultMaterialSheetDraftID,
            rememberedDraftIDRaw: lastAppendDraftIDRaw
        )
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
                hiddenPresetKeys: Array(store.hiddenPresetKeys),
                deletedUserMaterials: store.deletedUserMaterials,
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
        .sheet(isPresented: $showAddSheet) {
            AddMaterialSheet(
                initialCategory: categoryState.selectedCategory,
                suggestedCategories: availableCategories
            ) { material, price in
                let key = materialKey(name: material.name, specification: material.specification, unit: material.unit)
                if !store.userMaterials.contains(where: { materialKey(name: $0.name, specification: $0.specification, unit: $0.unit) == key }) {
                    store.appendUserMaterial(material)
                }
                if !price.isEmpty {
                    let entry = MaterialPriceEntry(
                        name: material.name,
                        specification: material.specification,
                        unit: material.unit,
                        referencePrice: price,
                        category: material.category
                    )
                    upsertMaterialPriceEntry(entry)
                }
                let displayName = material.specification.isEmpty ? material.name : "\(material.name) \(material.specification)"
                store.appendMaterialItem(MaterialItem(
                    name: displayName,
                    quantity: "1",
                    unit: material.unit,
                    unitPrice: price,
                    specification: material.specification
                ))
                store.scheduleSave()
            }
        }
        .sheet(item: $priceEditorContext) { context in
            MaterialPriceEditSheet(
                entry: context.entry,
                suppliers: store.supplierProfiles,
                initialName: context.name,
                initialSpecification: context.specification,
                initialUnit: context.unit,
                initialCategory: context.category
            ) { updated in
                upsertMaterialPriceEntry(updated)
                priceEditorContext = nil
            } onDelete: { target in
                MaterialLibraryLogicHelpers.deleteMaterialPriceEntryWithUndo(
                    target,
                    store: store,
                    undoableDeletion: undoableDeletion,
                    notice: $operationNotice
                )
                priceEditorContext = nil
            }
        }
        .sheet(item: $appendState.pendingAddContext) { context in
            MaterialLibraryAppendToSheetModal(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: store.projects,
                draftPickerTitle: { draft in
                    MaterialLibraryLogicHelpers.materialSheetDraftPickerTitle(draft, projects: store.projects)
                },
                quantity: $appendState.pendingAddQuantity,
                unitPrice: $appendState.pendingAddUnitPrice,
                note: $appendState.pendingAddNote,
                targetMode: $appendState.pendingAddTargetMode,
                draftId: $appendState.pendingAddDraftId,
                draftTitle: $appendState.pendingAddDraftTitle,
                projectId: $appendState.pendingAddProjectId,
                focusedField: $appendMaterialFocusedField,
                operationMessage: $operationMessage,
                canAppendMaterialToSheet: canAppendMaterialToSheet,
                onCancel: {
                    appendState.pendingAddContext = nil
                },
                onConfirm: {
                    appendMaterialsToSheet(
                        [context],
                        quantityText: appendState.pendingAddQuantity,
                        showPostAddPrompt: false,
                        deferToastUntilSheetDismissal: true
                    ) { _ in
                        appendState.pendingAddUnitPrice
                    }
                },
                onEnsureExistingDraftSelection: {
                    appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
                }
            )
        }
        .sheet(item: $batchState.pendingBatchAddContext) { context in
            MaterialLibraryBatchAppendSheet(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: store.projects,
                draftPickerTitle: { draft in
                    MaterialLibraryLogicHelpers.materialSheetDraftPickerTitle(draft, projects: store.projects)
                },
                quantity: $batchState.pendingBatchAddQuantity,
                targetMode: $appendState.pendingAddTargetMode,
                draftId: $appendState.pendingAddDraftId,
                draftTitle: $appendState.pendingAddDraftTitle,
                projectId: $appendState.pendingAddProjectId,
                operationMessage: $operationMessage,
                canAppendMaterialToSheet: canAppendMaterialToSheet,
                onCancel: {
                    batchState.pendingBatchAddContext = nil
                },
                onConfirm: {
                    let appended = confirmAppendMaterials(
                        context.materials,
                        quantityText: batchState.pendingBatchAddQuantity,
                        deferToastUntilSheetDismissal: true
                    )
                    guard appended else { return false }
                    batchState.selectedMaterialContextsByKey = [:]
                    return true
                },
                onEnsureExistingDraftSelection: {
                    appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
                }
            )
        }
        .sheet(isPresented: $categoryState.showCategoryManager) {
            NavigationStack {
                MaterialCategoryManagementView()
            }
        }
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
        .onChange(of: appendState.pendingAddContext?.id) { _, newValue in
            guard newValue == nil else { return }
            flushDeferredOperationMessage()
        }
        .onChange(of: batchState.pendingBatchAddContext?.id) { _, newValue in
            guard newValue == nil else { return }
            flushDeferredOperationMessage()
        }
    }

    private var defaultMaterialSheetTargetBar: some View {
        MaterialLibraryDefaultTargetBar(
            draft: defaultTargetMaterialSheetDraft,
            activeDrafts: activeMaterialSheetDrafts,
            draftTitle: { draft in
                MaterialLibraryLogicHelpers.materialSheetDraftPickerTitle(draft, projects: store.projects)
            },
            projectName: { projectID in
                MaterialLibraryLogicHelpers.projectName(for: projectID, projects: store.projects)
            },
            recentlyAddedSummary: { draft in
                MaterialLibraryLogicHelpers.recentlyAddedSummary(
                    for: draft,
                    recentlyAddedDraftID: appendState.recentlyAddedDraftID,
                    recentlyAddedItemCount: appendState.recentlyAddedItemCount
                )
            },
            onSelectDraft: { draftID in
                appendState.selectedDefaultMaterialSheetDraftID = draftID
            },
            onCreateDraft: {
                createAndSelectDefaultMaterialSheetDraft()
            },
            onOpenDraft: { draftID in
                appendState.recentlyAddedDraftID = draftID
                appendState.navigateToMaterialSheet = true
            }
        )
    }

    // MARK: - Price lookup

    private func priceEntry(for item: CommonMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(item)]
    }

    private func priceEntry(forUser item: UserMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(name: item.name, specification: item.specification, unit: item.unit)]
    }

    // MARK: - Preset material row

    private func presetMaterialRow(_ item: CommonMaterial) -> some View {
        let entry = priceEntry(for: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(item),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            appendContext: context,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category.rawValue, entry: entry) },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    // MARK: - User material row

    private func userMaterialRow(_ item: UserMaterial) -> some View {
        let entry = priceEntry(forUser: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(name: item.name, specification: item.specification, unit: item.unit),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            appendContext: context,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category, entry: entry) },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    // MARK: - Shared row content

    private func materialRowContent(
        name: String, spec: String, unit: String,
        hasPrice: Bool, price: String?,
        appendContext: PendingMaterialAppendContext,
        onEdit: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) -> some View {
        let isSelected = batchState.selectedMaterialContextsByKey[appendContext.key] != nil
        return MaterialLibraryMaterialRowContent(
            name: name,
            spec: spec,
            unit: unit,
            hasPrice: hasPrice,
            price: price,
            isBatchSelectionMode: batchState.isBatchSelectionMode,
            isSelected: isSelected,
            onEdit: onEdit,
            onAdd: onAdd,
            onToggleSelection: {
                toggleBatchMaterialSelection(appendContext)
            }
        )
    }

    private func makeAppendContext(
        name: String,
        specification: String,
        unit: String,
        key: String,
        priceEntry: MaterialPriceEntry?
    ) -> PendingMaterialAppendContext {
        PendingMaterialAppendContext(
            name: name,
            specification: specification,
            unit: unit,
            key: key,
            defaultBrand: priceEntry?.brand ?? "",
            defaultSupplier: priceEntry?.supplier ?? "",
            defaultUnitPrice: priceEntry?.referencePrice ?? ""
        )
    }

    private func toggleBatchMaterialSelection(_ context: PendingMaterialAppendContext) {
        batchState.selectedMaterialContextsByKey = MaterialLibraryLogicHelpers.toggledBatchSelection(
            selectedByKey: batchState.selectedMaterialContextsByKey,
            context: context
        )
    }

    private func exitBatchSelectionMode() {
        batchState.isBatchSelectionMode = false
        batchState.selectedMaterialContextsByKey = [:]
        batchState.pendingBatchAddContext = nil
    }

    @ViewBuilder
    private var batchAppendActionBar: some View {
        MaterialLibraryBatchAppendActionBar(
            selectedCount: selectedBatchMaterialContexts.count,
            onClear: {
                batchState.selectedMaterialContextsByKey = [:]
            },
            onOpenBatchAppend: {
                openBatchAppendSheet()
            }
        )
    }

    private func openBatchAppendSheet() {
        let contexts = selectedBatchMaterialContexts
        guard !contexts.isEmpty else {
            operationMessage = "请先选择材料"
            return
        }
        batchState.pendingBatchAddQuantity = "1"
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyDefaultAppendTarget()
        appendState.pendingAddDraftTitle = MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
            projectId: appendState.pendingAddProjectId,
            projects: store.projects
        )
        batchState.pendingBatchAddContext = PendingBatchMaterialAppendContext(materials: contexts)
    }

    // MARK: - Recycle bin rows

    private func deletedPresetRow(key: String) -> some View {
        MaterialLibraryDeletedPresetRow(key: key) {
            store.hiddenPresetKeys.remove(key)
            store.scheduleSave()
        }
    }

    private func deletedUserRow(_ item: UserMaterial) -> some View {
        MaterialLibraryDeletedUserRow(item: item) {
            store.removeDeletedUserMaterials(ids: Set([item.id]))
            store.appendUserMaterial(item)
            store.scheduleSave()
        }
    }

    // MARK: - Actions

    private func openPriceEditSheet(name: String, spec: String, unit: String, category: String, entry: MaterialPriceEntry?) {
        if let existing = entry {
            priceEditorContext = MaterialPriceEditorContext(existing: existing)
        } else {
            priceEditorContext = MaterialPriceEditorContext(
                name: name,
                specification: spec,
                unit: unit,
                category: category
            )
        }
    }

    private func prepareAppendMaterial(_ context: PendingMaterialAppendContext) {
        appendState.pendingAddContext = context
        appendState.pendingAddQuantity = "1"
        appendState.pendingAddUnitPrice = context.defaultUnitPrice
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyDefaultAppendTarget()
        appendState.pendingAddDraftTitle = MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
            projectId: appendState.pendingAddProjectId,
            projects: store.projects
        )
    }

    @discardableResult
    private func confirmAppendMaterials(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false
    ) -> Bool {
        appendMaterialsToSheet(
            contexts,
            quantityText: quantityText,
            showPostAddPrompt: showPostAddPrompt,
            deferToastUntilSheetDismissal: deferToastUntilSheetDismissal
        ) { context in
            context.defaultUnitPrice
        }
    }

    @discardableResult
    private func appendMaterialsToSheet(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false,
        unitPriceResolver: (PendingMaterialAppendContext) -> String
    ) -> Bool {
        guard !contexts.isEmpty else { return false }
        let computation = MaterialLibraryLogicHelpers.computeAppendComputation(
            contexts: contexts,
            quantityText: quantityText,
            noteText: appendState.pendingAddNote,
            targetMode: appendState.pendingAddTargetMode,
            targetDraftID: appendState.pendingAddDraftId,
            targetProjectID: appendState.pendingAddProjectId,
            draftTitleInput: appendState.pendingAddDraftTitle,
            drafts: store.materialSheetDrafts,
            projects: store.projects,
            now: Formatters.now(),
            unitPriceResolver: unitPriceResolver
        )

        switch computation {
        case .failure(let message, let nextPendingTargetMode, let nextPendingDraftID):
            operationMessage = message
            appendState.pendingAddTargetMode = nextPendingTargetMode
            appendState.pendingAddDraftId = nextPendingDraftID
            return false
        case .success(let output):
            store.replaceMaterialSheetDrafts(output.drafts)
            contexts.forEach { appendRecentMaterialKey($0.key) }
            store.scheduleSave()

            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = output.targetDraftID.uuidString
            lastAppendProjectIDRaw = output.lastProjectIDRaw

            appendState.pendingAddTargetMode = output.nextPendingTargetMode
            appendState.pendingAddDraftId = output.nextPendingDraftID
            appendState.selectedDefaultMaterialSheetDraftID = output.nextSelectedDefaultDraftID
            showOperationMessage(
                MaterialLibraryLogicHelpers.appendSuccessMessage(
                    itemCount: contexts.count,
                    draftTitle: output.targetTitle
                ),
                deferUntilDismissal: deferToastUntilSheetDismissal
            )
            appendState.selectedDefaultMaterialSheetDraftID = output.targetDraftID
            appendState.recentlyAddedDraftID = output.targetDraftID
            appendState.recentlyAddedDraftTitle = output.targetTitle
            appendState.recentlyAddedItemCount = contexts.count
            appendState.showOpenMaterialSheetPrompt = promptAfterAdd && showPostAddPrompt
            return true
        }
    }

    private func showOperationMessage(_ message: String, deferUntilDismissal: Bool = false) {
        if deferUntilDismissal {
            appendState.deferredOperationMessage = message
        } else {
            operationMessage = message
        }
    }

    private func flushDeferredOperationMessage() {
        guard let message = appendState.deferredOperationMessage else { return }
        appendState.deferredOperationMessage = nil
        operationMessage = message
    }

    private var activeMaterialSheetDrafts: [MaterialSheetDraft] {
        MaterialLibraryLogicHelpers.activeMaterialSheetDrafts(from: store.materialSheetDrafts)
    }

    private func applyDefaultAppendTarget() {
        if let draft = defaultTargetMaterialSheetDraft {
            appendState.pendingAddTargetMode = .existing
            appendState.pendingAddDraftId = draft.id
            appendState.pendingAddProjectId = nil
            return
        }
        let target = MaterialLibraryLogicHelpers.rememberedTargetState(
            lastModeRaw: lastAppendTargetModeRaw,
            lastDraftIDRaw: lastAppendDraftIDRaw,
            lastProjectIDRaw: lastAppendProjectIDRaw,
            activeDrafts: activeMaterialSheetDrafts,
            projects: store.projects
        )
        appendState.pendingAddTargetMode = target.mode
        appendState.pendingAddDraftId = target.draftID
        appendState.pendingAddProjectId = target.projectID
    }

    private func ensureDefaultMaterialSheetSelection() {
        appendState.selectedDefaultMaterialSheetDraftID = MaterialLibraryLogicHelpers.ensureDefaultSelection(
            selectedDefaultDraftID: appendState.selectedDefaultMaterialSheetDraftID,
            rememberedDraftIDRaw: lastAppendDraftIDRaw,
            activeDrafts: activeMaterialSheetDrafts
        )
    }

    @discardableResult
    private func createAndSelectDefaultMaterialSheetDraft() -> UUID {
        let now = Formatters.now()
        let newDraft = MaterialSheetDraft(
            title: MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
                projectId: nil,
                projects: store.projects
            ),
            items: [],
            createdAt: now,
            updatedAt: now
        )
        store.insertMaterialSheetDraftAtTop(newDraft)
        store.scheduleSave()
        appendState.selectedDefaultMaterialSheetDraftID = newDraft.id
        lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
        lastAppendDraftIDRaw = newDraft.id.uuidString
        lastAppendProjectIDRaw = ""
        operationMessage = "已创建默认材料单「\(newDraft.title)」"
        return newDraft.id
    }

    private var canAppendMaterialToSheet: Bool {
        switch appendState.pendingAddTargetMode {
        case .existing:
            return appendState.pendingAddDraftId != nil
        case .create:
            return true
        }
    }

    private func appendRecentMaterialKey(_ key: String) {
        store.recentMaterialKeys = MaterialLibraryLogicHelpers.appendingRecentMaterialKey(
            key,
            to: store.recentMaterialKeys
        )
    }

    private func removeRecentKey(_ key: String) {
        store.recentMaterialKeys = MaterialLibraryLogicHelpers.removingRecentMaterialKey(
            key,
            from: store.recentMaterialKeys
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

    private var deleteConfirmMessage: String {
        MaterialLibraryLogicHelpers.deleteConfirmMessage(for: pendingDeleteTarget)
    }

    private func requestDeletePresetMaterial(_ item: CommonMaterial) {
        pendingDeleteTarget = .preset(item)
        showDeleteConfirm = true
    }

    private func requestDeleteUserMaterial(_ item: UserMaterial) {
        pendingDeleteTarget = .user(item)
        showDeleteConfirm = true
    }

    private func confirmPendingDeleteMaterial() {
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

    private func materialKey(_ item: CommonMaterial) -> String {
        MaterialLibraryLogicHelpers.materialKey(item)
    }

    private func legacyMaterialKey(_ item: CommonMaterial) -> String {
        MaterialLibraryLogicHelpers.legacyMaterialKey(item)
    }

    private func materialKey(name: String, specification: String, unit: String) -> String {
        MaterialLibraryLogicHelpers.materialKey(name: name, specification: specification, unit: unit)
    }

    private func legacyMaterialKey(name: String, specification: String, unit: String) -> String {
        MaterialLibraryLogicHelpers.legacyMaterialKey(name: name, specification: specification, unit: unit)
    }

    private func isPresetHidden(_ item: CommonMaterial) -> Bool {
        MaterialLibraryLogicHelpers.isPresetHidden(item, hiddenPresetKeys: store.hiddenPresetKeys)
    }

    private func normalizedCategory(_ value: String) -> String {
        MaterialLibraryLogicHelpers.normalizedCategory(value)
    }

    private func matchesPriceFilter(_ entry: MaterialPriceEntry?) -> Bool {
        MaterialLibraryLogicHelpers.matchesPriceFilter(entry, priceFilter: priceFilter)
    }

    private func matchesSearch<Item: Searchable>(_ item: Item, extraFields: [String]) -> Bool {
        MaterialLibraryLogicHelpers.matchesSearch(
            item: item,
            normalizedKeyword: normalizedSearchKeyword,
            extraFields: extraFields
        )
    }

    private func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        store.upsertMaterialPriceEntry(entry)
        store.scheduleSave()
    }
}
