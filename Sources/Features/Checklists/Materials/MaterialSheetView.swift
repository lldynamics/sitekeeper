import SwiftUI
import PhotosUI

// MARK: - Material Sheet View

struct MaterialSheetView: View {
    @Environment(DataStore.self) var store
    @State var sheetItems: [MaterialSheetItem] = []
    @State var selectedDraftID: UUID?
    @State var isApplyingDraftState = false
    @State var showCreateDraftSheet = false
    @State var showRenameDraftSheet = false
    @State var draftTitleInput = ""
    @State var renameDraftTitleInput = ""
    @State var draftProjectIdInput: UUID?
    @State var searchText = ""
    @State private var showClearConfirm = false
    @State var pendingDeleteSheetItemIDs: Set<UUID> = []
    @State var showDeleteItemConfirm = false
    @State var exportFileURL: URL?
    @State var showExporter = false
    @State var showExportChoice = false
    @State var isExporting = false
    @State var exportOptions = MaterialSheetExportOptions()
    @State var rowPhotoSelections: [UUID: [PhotosPickerItem]] = [:]
    @State var itemExpanded: Set<UUID> = []
    @State var exportProjectName = ""
    @State var exportPreparer = ""
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @FocusState var isMaterialSearchFocused: Bool

    init(initialDraftID: UUID? = nil) {
        _selectedDraftID = State(initialValue: initialDraftID)
    }

    var activeMaterialSheetDrafts: [MaterialSheetDraft] {
        MaterialSheetLogicHelpers.activeDrafts(from: store.materialSheetDrafts)
    }

    var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    var selectedDraft: MaterialSheetDraft? {
        MaterialSheetLogicHelpers.selectedDraft(
            selectedDraftID: selectedDraftID,
            activeDrafts: activeMaterialSheetDrafts
        )
    }

    var priceSuggestions: [MaterialPriceEntry] {
        MaterialSheetLogicHelpers.priceSuggestions(
            keyword: searchText,
            entries: store.materialPriceEntries
        )
    }
    var librarySuggestions: [CommonMaterial] {
        MaterialSheetLogicHelpers.librarySuggestions(
            keyword: searchText,
            materials: MaterialLibrary.all
        )
    }
    var hasSearchResults: Bool { !priceSuggestions.isEmpty || !librarySuggestions.isEmpty }

    private var totals: MaterialSheetTotals {
        MaterialSheetLogicHelpers.totals(for: sheetItems)
    }

    private var totalEstimateValue: MoneyValue {
        totals.estimate
    }
    private var totalLaborValue: MoneyValue {
        totals.labor
    }
    private var grandTotalValue: MoneyValue {
        totals.grand
    }
    private var totalEstimateText: String {
        totals.estimateText
    }
    private var totalLaborText: String {
        totals.laborText
    }
    private var grandTotalText: String {
        totals.grandText
    }
    private var exportDateLabelText: String {
        let localizedTemplate = AppLocalization.string("导出日期: %@")
        let dateText = Formatters.date.string(from: Date())
        return String(format: localizedTemplate, dateText)
    }

    var body: some View {
        AppReviewWorkspace(primaryTitle: AppLocalization.string("编辑材料"), secondaryTitle: AppLocalization.string("核对明细")) {
            materialSheetList
        } secondary: {
            MaterialSheetReviewView(items: sheetItems)
        }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !sheetItems.isEmpty {
                    MaterialSheetReviewTotal(items: sheetItems)
                }
            }
            .navigationTitle(AppLocalization.string("材料单"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                materialSheetToolbar
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
            .materialSheetPresentations(
                showExportChoice: $showExportChoice,
                exportFileURL: $exportFileURL,
                showExporter: $showExporter,
                onCleanupExportFile: cleanupExportFileIfNeeded,
                showCreateDraftSheet: $showCreateDraftSheet,
                draftTitleInput: $draftTitleInput,
                draftProjectIdInput: $draftProjectIdInput,
                projects: store.projects,
                onCreateDraft: { title, projectId in
                    createDraftAndSelect(title: title, projectId: projectId)
                },
                showRenameDraftSheet: $showRenameDraftSheet,
                renameDraftTitleInput: $renameDraftTitleInput,
                onRenameDraft: { title in
                    renameSelectedDraft(to: title)
                },
                showClearConfirm: $showClearConfirm,
                sheetItemCount: sheetItems.count,
                onConfirmClear: {
                    clearCurrentSheetItemsWithUndo()
                },
                showDeleteItemConfirm: $showDeleteItemConfirm,
                pendingDeleteItemCount: pendingDeleteSheetItemIDs.count,
                onConfirmDeleteItems: confirmDeleteSheetItems,
                onCancelDeleteItems: {
                    pendingDeleteSheetItemIDs.removeAll()
                }
            )
            .onAppear {
                ensureDraftSelection()
            }
            .onChange(of: activeMaterialSheetDraftIDs) { _, _ in
                ensureDraftSelection()
            }
            .onChange(of: selectedDraftID) { _, _ in
                loadSelectedDraftIntoEditor()
            }
            .onChange(of: sheetItems) { _, _ in
                persistCurrentDraft()
            }
            .onChange(of: exportProjectName) { _, _ in
                persistCurrentDraft()
            }
            .onChange(of: exportPreparer) { _, _ in
                persistCurrentDraft()
            }
            .operationToast(notice: $operationNotice)
            .onDisappear {
                undoableDeletion.flushPendingCommit()
            }
    }

    @ToolbarContentBuilder
    private var materialSheetToolbar: some ToolbarContent {
        if !sheetItems.isEmpty {
            ToolbarItem(id: "material-sheet-more", placement: .topBarTrailing) {
                materialSheetMoreMenu
                    .accessibilityIdentifier("material-sheet-more-menu")
            }
        }
        ToolbarItem(id: "material-sheet-create", placement: .topBarTrailing) {
            Button {
                prepareCreateDraftSheet()
            } label: {
                Label(AppLocalization.string("新建材料单"), systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel(AppLocalization.string("新建材料单"))
            .accessibilityIdentifier("material-sheet-create")
        }
    }

    private var materialSheetList: some View {
        List {
            AnyView(materialSheetDraftSelector)
            AnyView(materialSheetSearch)
            AnyView(currentMaterialSection)
            if !sheetItems.isEmpty {
                AnyView(exportHeaderSection)
            }
            if !sheetItems.isEmpty {
                AnyView(exportColumnToggleSection)
            }
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                AnyView(summarySection)
            }
        }
    }

    private var materialSheetDraftSelector: some View {
        MaterialSheetDraftSelectorSection(
            activeDrafts: activeMaterialSheetDrafts,
            selectedDraftID: $selectedDraftID,
            selectedDraft: selectedDraft,
            draftDisplayName: { draft in
                draftDisplayName(draft)
            },
            projectName: { projectId in
                projectName(for: projectId)
            },
            onCreateDraft: {
                prepareCreateDraftSheet()
            },
            onFocusMaterialSearch: {
                focusMaterialSearch()
            },
            onPrepareRenameDraft: {
                prepareRenameDraftSheet()
            },
            onArchiveSelectedDraft: {
                archiveSelectedDraft()
            }
        )
    }

    private var materialSheetSearch: some View {
        MaterialSheetSearchSection(
            searchText: $searchText,
            isMaterialSearchFocused: $isMaterialSearchFocused,
            hasSearchResults: hasSearchResults,
            priceSuggestions: priceSuggestions,
            librarySuggestions: librarySuggestions,
            librarySearchRow: { entry in
                AnyView(librarySearchRow(entry: entry))
            },
            presetSearchRow: { material in
                AnyView(presetSearchRow(material: material))
            }
        )
    }

    private var exportHeaderSection: some View {
        MaterialSheetExportHeaderSection(
            exportProjectName: $exportProjectName,
            exportPreparer: $exportPreparer,
            exportDateLabelText: exportDateLabelText
        )
    }

    private var materialSheetMoreMenu: some View {
        MaterialSheetMoreMenu(
            isExporting: isExporting,
            onExportPDF: exportAsPDF,
            onExportCSV: exportAsCSV,
            onExportImage: exportAsImage,
            onSaveToMaterialList: saveSheetToMaterialListAndClear,
            onClearSheet: {
                showClearConfirm = true
            }
        )
    }
}

extension MaterialSheetView {
    private func saveSheetToMaterialListAndClear() {
        guard !sheetItems.isEmpty else { return }
        saveToMaterialList()
        clearCurrentSheetItemsWithUndo(
            message: AppLocalization.string("已保存到材料清单并清空材料单"),
            auditSummary: AppLocalization.string("保存并清空材料单")
        )
    }

    // MARK: - Helpers

    private func focusMaterialSearch() {
        searchText = ""
        isMaterialSearchFocused = true
    }

    func addToSheet(name: String, spec: String, unit: String, price: String = "") {
        let newItem = MaterialSheetItem(
            name: name, specification: spec, unit: unit,
            quantity: "1", unitPrice: price
        )
        if selectedDraft == nil {
            let now = BusinessDateValue.now()
            let newDraft = MaterialSheetDraft(
                title: defaultDraftTitle(projectId: nil),
                projectId: nil,
                items: [newItem.draftItem],
                createdAt: now,
                updatedAt: now
            )
            var drafts = store.materialSheetDrafts
            drafts.insert(newDraft, at: 0)
            store.replaceMaterialSheetDrafts(drafts)
            store.scheduleSave()
            selectedDraftID = newDraft.id
            sheetItems = [newItem]
            exportProjectName = ""
            return
        }
        sheetItems.append(newItem)
    }

    private func saveToMaterialList() {
        let projectId = selectedDraft?.projectId
        for item in sheetItems {
            let finalQty = MaterialSheetLogicHelpers.normalizedMaterialListQuantity(item.quantity)
            let price = item.unitPrice.trimmingCharacters(in: .whitespacesAndNewlines)
            store.appendMaterialItem(MaterialItem(
                name: item.name, quantity: NumericInputSupport.quantity(finalQty),
                unit: item.unit.isEmpty ? "个" : item.unit,
                unitPrice: NumericInputSupport.money(price),
                specification: item.specification,
                supplier: item.supplier,
                projectId: projectId
            ))
        }
        store.scheduleSave()
    }
}

private extension MaterialSheetView {
    var exportColumnToggleSection: some View {
        MaterialSheetExportColumnToggleSection(exportOptions: $exportOptions)
    }

    var summarySection: some View {
        MaterialSheetSummarySection(
            totalEstimateValue: totalEstimateValue,
            totalLaborValue: totalLaborValue,
            totalEstimateText: totalEstimateText,
            totalLaborText: totalLaborText,
            grandTotalText: grandTotalText
        )
    }
}
