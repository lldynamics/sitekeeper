import SwiftUI
import PhotosUI

// MARK: - Material Sheet View

struct MaterialSheetView: View {
    @Environment(DataStore.self) private var store
    @State private var sheetItems: [MaterialSheetItem] = []
    @State private var selectedDraftID: UUID?
    @State private var isApplyingDraftState = false
    @State private var showCreateDraftSheet = false
    @State private var showRenameDraftSheet = false
    @State private var draftTitleInput = ""
    @State private var renameDraftTitleInput = ""
    @State private var draftProjectIdInput: UUID?
    @State private var searchText = ""
    @State private var showClearConfirm = false
    @State private var pendingDeleteSheetItemIDs: Set<UUID> = []
    @State private var showDeleteItemConfirm = false
    @State private var exportFileURL: URL?
    @State private var showExporter = false
    @State private var showExportChoice = false
    @State private var isExporting = false
    @State private var exportOptions = MaterialSheetExportOptions()
    @State private var rowPhotoSelections: [UUID: [PhotosPickerItem]] = [:]
    @State private var itemExpanded: Set<UUID> = []
    @State private var exportProjectName = ""
    @State private var exportPreparer = ""
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @FocusState private var isMaterialSearchFocused: Bool

    init(initialDraftID: UUID? = nil) {
        _selectedDraftID = State(initialValue: initialDraftID)
    }

    private var activeMaterialSheetDrafts: [MaterialSheetDraft] {
        MaterialSheetLogicHelpers.activeDrafts(from: store.materialSheetDrafts)
    }

    private var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    private var selectedDraft: MaterialSheetDraft? {
        MaterialSheetLogicHelpers.selectedDraft(
            selectedDraftID: selectedDraftID,
            activeDrafts: activeMaterialSheetDrafts
        )
    }

    private var priceSuggestions: [MaterialPriceEntry] {
        MaterialSheetLogicHelpers.priceSuggestions(
            keyword: searchText,
            entries: store.materialPriceEntries
        )
    }
    private var librarySuggestions: [CommonMaterial] {
        MaterialSheetLogicHelpers.librarySuggestions(
            keyword: searchText,
            materials: MaterialLibrary.all
        )
    }
    private var hasSearchResults: Bool { !priceSuggestions.isEmpty || !librarySuggestions.isEmpty }

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

    var body: some View {
        List {
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

            // Sheet items
            Section {
                if sheetItems.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text(String(localized: "材料单为空")).foregroundStyle(.secondary)
                            Text(String(localized: "在上方搜索材料库添加")).font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    ForEach($sheetItems) { $item in materialItemRow($item) }
                        .onDelete { offsets in
                            let ids = offsets.compactMap { sheetItems.indices.contains($0) ? sheetItems[$0].id : nil }
                            requestDeleteSheetItems(ids: ids)
                        }
                }
            } header: {
                HStack {
                    Text(String(localized: "当前材料单"))
                    Spacer()
                    if !sheetItems.isEmpty {
                        Text(String(format: String(localized: "%d 项"), sheetItems.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Export header info
            if !sheetItems.isEmpty {
                Section(String(localized: "导出表头信息")) {
                    TextField(String(localized: "项目名称"), text: $exportProjectName)
                    TextField(String(localized: "编制人"), text: $exportPreparer)
                    Text(String(format: String(localized: "导出日期: %@"), Formatters.date.string(from: Date())))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Export column toggles
            if !sheetItems.isEmpty {
                exportColumnToggleSection
            }

            // Summary
            if totalEstimateValue.isPositive || totalLaborValue.isPositive {
                summarySection
            }

        }
        .navigationTitle(String(localized: "材料单"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !sheetItems.isEmpty {
                    materialSheetMoreMenu
                }

                Button {
                    prepareCreateDraftSheet()
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "新建材料单"))
            }

            KeyboardDismissToolbar {
                AppKeyboard.dismiss()
            }
        }
        .confirmationDialog(String(localized: "导出方式"), isPresented: $showExportChoice) {
            if let url = exportFileURL {
                Button { showExporter = true } label: { Label(String(localized: "保存到文件"), systemImage: "folder") }
                ShareLink(item: url) { Label(String(localized: "分享"), systemImage: "square.and.arrow.up") }
            }
            Button(String(localized: "关闭"), role: .cancel) { cleanupExportFileIfNeeded() }
        } message: {
            Text(String(localized: "选择保存位置或分享给其他人"))
        }
        .sheet(isPresented: $showExporter) {
            if let exportFileURL {
                FileURLDocumentExporter(fileURL: exportFileURL) { _ in
                    showExporter = false
                    cleanupExportFileIfNeeded()
                }
            } else {
                ProgressView(String(localized: "正在准备导出文件..."))
                    .padding()
            }
        }
        .sheet(isPresented: $showCreateDraftSheet) {
            MaterialSheetCreateDraftSheet(
                titleInput: $draftTitleInput,
                projectIdInput: $draftProjectIdInput,
                projects: store.projects,
                onCancel: {
                    showCreateDraftSheet = false
                },
                onCreate: {
                    createDraftAndSelect(title: draftTitleInput, projectId: draftProjectIdInput)
                    showCreateDraftSheet = false
                }
            )
        }
        .sheet(isPresented: $showRenameDraftSheet) {
            MaterialSheetRenameDraftSheet(
                renameTitleInput: $renameDraftTitleInput,
                onCancel: {
                    showRenameDraftSheet = false
                },
                onSave: {
                    renameSelectedDraft(to: renameDraftTitleInput)
                    showRenameDraftSheet = false
                }
            )
        }
        .alert(String(localized: "清空材料单？"), isPresented: $showClearConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "清空"), role: .destructive) {
                clearCurrentSheetItemsWithUndo()
            }
        } message: {
            Text(String(format: String(localized: "当前材料单中的 %d 项材料将被移除。"), sheetItems.count))
        }
        .confirmationDialog(String(localized: "删除材料项"), isPresented: $showDeleteItemConfirm, titleVisibility: .visible) {
            Button(String(localized: "删除"), role: .destructive) {
                confirmDeleteSheetItems()
            }
            Button(String(localized: "取消"), role: .cancel) {
                pendingDeleteSheetItemIDs.removeAll()
            }
        } message: {
            Text(String(format: String(localized: "确认删除 %d 项材料吗？"), pendingDeleteSheetItemIDs.count))
        }
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

    private var materialSheetMoreMenu: some View {
        Menu {
            Section(String(localized: "导出")) {
                Button(action: exportAsPDF) {
                    Label(String(localized: "导出 PDF"), systemImage: "doc.richtext.fill")
                }
                Button(action: exportAsCSV) {
                    Label(String(localized: "导出 CSV"), systemImage: "tablecells.fill")
                }
                Button(action: exportAsImage) {
                    Label(String(localized: "导出图片"), systemImage: "photo")
                }
            }

            Section(String(localized: "材料单操作")) {
                Button(action: saveSheetToMaterialListAndClear) {
                    Label(String(localized: "保存到材料清单"), systemImage: "shippingbox.fill")
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(String(localized: "清空材料单"), systemImage: "trash")
                }
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "ellipsis.circle").visibleIconStyle()
            }
        }
        .disabled(isExporting)
        .accessibilityLabel(String(localized: "更多操作"))
    }

    private var exportColumnToggleSection: some View {
        Section(String(localized: "导出列设置")) {
            Toggle(String(localized: "估价"), isOn: $exportOptions.showPrice)
            Toggle(String(localized: "人工费"), isOn: $exportOptions.showLabor)
            Toggle(String(localized: "使用部位"), isOn: $exportOptions.showLocation)
            Toggle(String(localized: "供应商"), isOn: $exportOptions.showSupplier)
            Toggle(String(localized: "备注"), isOn: $exportOptions.showNote)
        }
    }

    private var summarySection: some View {
        Section(String(localized: "合计")) {
            if totalEstimateValue.isPositive {
                HStack {
                    Text(String(localized: "材料估价")).font(.callout)
                    Spacer()
                    Text(totalEstimateText).font(.body.weight(.semibold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
            if totalLaborValue.isPositive {
                HStack {
                    Text(String(localized: "人工费")).font(.callout)
                    Spacer()
                    Text(totalLaborText).font(.body.weight(.semibold)).foregroundStyle(Color.appSuccess)
                }
            }
            if totalEstimateValue.isPositive, totalLaborValue.isPositive {
                HStack {
                    Text(String(localized: "总计")).font(.body.weight(.bold))
                    Spacer()
                    Text(grandTotalText).font(.title3.weight(.bold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
        }
    }

    private func draftDisplayName(_ draft: MaterialSheetDraft) -> String {
        MaterialSheetLogicHelpers.draftDisplayName(draft)
    }

    private func projectName(for projectId: UUID) -> String? {
        MaterialSheetLogicHelpers.projectName(for: projectId, projects: store.projects)
    }

    private func defaultDraftTitle(projectId: UUID?) -> String {
        MaterialSheetLogicHelpers.defaultDraftTitle(
            projectId: projectId,
            projects: store.projects
        )
    }

    private func prepareCreateDraftSheet() {
        let input = MaterialSheetLogicHelpers.createDraftSheetInput(
            selectedDraft: selectedDraft,
            projects: store.projects
        )
        draftProjectIdInput = input.projectID
        draftTitleInput = input.title
        showCreateDraftSheet = true
    }

    private func prepareRenameDraftSheet() {
        guard let selectedDraft else { return }
        renameDraftTitleInput = draftDisplayName(selectedDraft)
        showRenameDraftSheet = true
    }

    private func createDraftAndSelect(title: String, projectId: UUID?) {
        let newDraft = MaterialSheetLogicHelpers.makeDraft(
            title: title,
            projectId: projectId,
            projects: store.projects,
            now: Formatters.now(),
            items: []
        )
        store.replaceMaterialSheetDrafts(
            MaterialSheetLogicHelpers.insertingDraftAtTop(newDraft, drafts: store.materialSheetDrafts)
        )
        store.scheduleSave()
        selectedDraftID = newDraft.id
    }

    private func renameSelectedDraft(to title: String) {
        guard let drafts = MaterialSheetLogicHelpers.renamedDrafts(
            selectedDraftID: selectedDraftID,
            title: title,
            drafts: store.materialSheetDrafts,
            now: Formatters.now()
        ) else { return }
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
    }

    private func archiveSelectedDraft() {
        guard let context = MaterialSheetLogicHelpers.archiveContext(
            selectedDraftID: selectedDraftID,
            drafts: store.materialSheetDrafts,
            now: Formatters.now()
        ) else { return }
        store.replaceMaterialSheetDrafts(context.updatedDrafts)
        store.scheduleSave()

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(
                format: String(localized: "已归档材料单「%@」"),
                draftDisplayName(context.archivedDraft)
            ),
            undoMessage: String(localized: "已恢复材料单草稿"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceMaterialSheetDrafts(UndoableDeletionCoordinator.restoringItems(
                    snapshot: context.previousDrafts,
                    current: store.materialSheetDrafts,
                    deletedIDs: Set([context.archivedDraft.id])
                ))
                self.selectedDraftID = context.previousSelectedDraftID
                loadSelectedDraftIntoEditor()
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "归档材料单草稿"),
                detail: draftDisplayName(context.archivedDraft),
                source: "MaterialSheetView"
            )
        )
    }

    private func ensureDraftSelection() {
        if activeMaterialSheetDrafts.isEmpty {
            selectedDraftID = nil
            isApplyingDraftState = true
            sheetItems = []
            exportProjectName = ""
            exportPreparer = ""
            itemExpanded.removeAll()
            rowPhotoSelections.removeAll()
            pendingDeleteSheetItemIDs.removeAll()
            isApplyingDraftState = false
            return
        }
        selectedDraftID = MaterialSheetLogicHelpers.resolvedSelectedDraftID(
            currentSelectedDraftID: selectedDraftID,
            activeDraftIDs: activeMaterialSheetDraftIDs
        )
    }

    private func loadSelectedDraftIntoEditor() {
        guard let selectedDraft else { return }
        let editorState = MaterialSheetLogicHelpers.draftEditorState(
            draft: selectedDraft,
            projects: store.projects
        )
        isApplyingDraftState = true
        sheetItems = editorState.sheetItems
        exportProjectName = editorState.exportProjectName
        exportPreparer = editorState.exportPreparer
        itemExpanded.removeAll()
        rowPhotoSelections.removeAll()
        pendingDeleteSheetItemIDs.removeAll()
        isApplyingDraftState = false
    }

    private func persistCurrentDraft() {
        guard !isApplyingDraftState,
              let drafts = MaterialSheetLogicHelpers.persistingDrafts(
                selectedDraftID: selectedDraftID,
                drafts: store.materialSheetDrafts,
                sheetItems: sheetItems,
                exportProjectName: exportProjectName,
                exportPreparer: exportPreparer,
                exportDate: Formatters.date.string(from: Date()),
                now: Formatters.now()
              ) else { return }
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
    }

    private func saveSheetToMaterialListAndClear() {
        guard !sheetItems.isEmpty else { return }
        saveToMaterialList()
        clearCurrentSheetItemsWithUndo(
            message: String(localized: "已保存到材料清单并清空材料单"),
            auditSummary: String(localized: "保存并清空材料单")
        )
    }

    private func photoSelectionBinding(for itemId: UUID) -> Binding<[PhotosPickerItem]> {
        Binding(
            get: { rowPhotoSelections[itemId] ?? [] },
            set: { newItems in
                rowPhotoSelections[itemId] = newItems
                guard !newItems.isEmpty else { return }
                Task {
                    await attachSelectedPhoto(itemId: itemId, items: newItems)
                }
            }
        )
    }

    @MainActor
    private func attachSelectedPhoto(itemId: UUID, items: [PhotosPickerItem]) async {
        defer {
            rowPhotoSelections[itemId] = []
        }
        guard let first = items.first else { return }
        guard let data = try? await first.loadTransferable(type: Data.self) else { return }
        guard let idx = sheetItems.firstIndex(where: { $0.id == itemId }) else { return }
        sheetItems[idx].attachmentData = data
        sheetItems[idx].attachmentFileName = "照片.jpg"
    }

    // MARK: - Item Row

    private func materialItemRow(_ item: Binding<MaterialSheetItem>) -> some View {
        let itemID = item.wrappedValue.id
        let isExpanded = itemExpanded.contains(itemID)
        return MaterialSheetEditableItemRow(
            item: item,
            isExpanded: isExpanded,
            accessibilityLabel: MaterialSheetLogicHelpers.materialItemAccessibilityLabel(
                item.wrappedValue,
                isExpanded: isExpanded
            ),
            photoSelection: photoSelectionBinding(for: itemID),
            suggestedPrice: MaterialSheetLogicHelpers.suggestedUnitPrice(
                for: item.wrappedValue,
                entries: store.materialPriceEntries
            ),
            onToggleExpand: {
                toggleExpand(itemID)
            },
            onDelete: {
                requestDeleteSheetItems(ids: [itemID])
            }
        )
    }

    private func toggleExpand(_ id: UUID) {
        if itemExpanded.contains(id) { itemExpanded.remove(id) }
        else { itemExpanded.insert(id) }
    }

    private func requestDeleteSheetItems(ids: [UUID]) {
        let normalizedIDs = MaterialSheetLogicHelpers.normalizedDeleteIDs(ids)
        guard !normalizedIDs.isEmpty else { return }
        pendingDeleteSheetItemIDs = normalizedIDs
        showDeleteItemConfirm = true
    }

    private func confirmDeleteSheetItems() {
        let ids = pendingDeleteSheetItemIDs
        guard !ids.isEmpty else { return }
        let count = MaterialSheetLogicHelpers.deletedItemCount(ids: ids, sheetItems: sheetItems)
        queueSheetItemDeletion(
            ids: ids,
            message: String(format: String(localized: "已删除 %lld 项材料单项目"), Int64(count)),
            auditSummary: String(format: String(localized: "删除材料单项目 %lld 项"), Int64(count))
        )
        pendingDeleteSheetItemIDs.removeAll()
    }

    private func clearCurrentSheetItemsWithUndo(
        message: String = String(localized: "已清空材料单"),
        auditSummary: String? = nil
    ) {
        let ids = Set(sheetItems.map(\.id))
        guard !ids.isEmpty else { return }
        queueSheetItemDeletion(
            ids: ids,
            message: message,
            auditSummary: auditSummary ?? String(format: String(localized: "清空材料单 %lld 项"), Int64(ids.count))
        )
    }

    private func queueSheetItemDeletion(ids: Set<UUID>, message: String, auditSummary: String) {
        let snapshot = sheetItems
        let deletedItems = snapshot.filter { ids.contains($0.id) }
        guard !deletedItems.isEmpty else { return }

        let previousExpanded = itemExpanded
        let previousPhotoSelections = rowPhotoSelections
        sheetItems.removeAll { ids.contains($0.id) }
        itemExpanded.subtract(ids)
        rowPhotoSelections = rowPhotoSelections.filter { !ids.contains($0.key) }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            undoMessage: String(localized: "已恢复材料单内容"),
            commit: {
                persistCurrentDraft()
            },
            undo: {
                sheetItems = UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: sheetItems,
                    deletedIDs: ids
                )
                itemExpanded = previousExpanded
                rowPhotoSelections = previousPhotoSelections
                persistCurrentDraft()
            },
            audit: UndoableDeletionAuditContext(
                summary: auditSummary,
                detail: materialSheetItemAuditDetail(deletedItems),
                source: "MaterialSheetView"
            )
        )
    }

    private func materialSheetItemAuditDetail(_ items: [MaterialSheetItem]) -> String {
        MaterialSheetLogicHelpers.materialSheetItemAuditDetail(items)
    }

    // MARK: - Search Rows

    private func librarySearchRow(entry: MaterialPriceEntry) -> some View {
        Button {
            addToSheet(name: entry.name, spec: entry.specification, unit: entry.unit, price: entry.referencePrice)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if !entry.specification.isEmpty { Text(entry.specification).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                HStack(spacing: 4) {
                    if !entry.referencePrice.isEmpty { Text("¥\(entry.referencePrice)").font(.caption).foregroundStyle(Color.appPrimaryAction) }
                    Text(entry.unit).font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "材料库")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.appPrimaryAction).font(.title3)
            }
        }
    }

    private func presetSearchRow(material: CommonMaterial) -> some View {
        Button {
            addToSheet(name: material.name, spec: material.specification, unit: material.unit)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(material.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(material.specification).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(material.unit).font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "预置材料")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.appPrimaryAction).font(.title3)
            }
        }
    }

    // MARK: - Helpers

    private func focusMaterialSearch() {
        searchText = ""
        isMaterialSearchFocused = true
    }

    private func addToSheet(name: String, spec: String, unit: String, price: String = "") {
        let newItem = MaterialSheetItem(
            name: name, specification: spec, unit: unit,
            quantity: "1", unitPrice: price
        )
        if selectedDraft == nil {
            let now = Formatters.now()
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
                name: item.name, quantity: finalQty,
                unit: item.unit.isEmpty ? "个" : item.unit,
                unitPrice: price,
                specification: item.specification,
                supplier: item.supplier,
                projectId: projectId
            ))
        }
        store.scheduleSave()
    }

    // MARK: - Export

    private func exportAsPDF() {
        isExporting = true
        defer { isExporting = false }
        let data = MaterialSheetExportRenderer.generatePDF(
            sheetItems: sheetItems,
            options: exportOptions,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).pdf")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func exportAsCSV() {
        isExporting = true
        defer { isExporting = false }
        let data = Data(
            MaterialSheetExportRenderer.generateCSV(
                sheetItems: sheetItems,
                options: exportOptions
            ).utf8
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).csv")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func exportAsImage() {
        isExporting = true
        defer { isExporting = false }
        guard let data = MaterialSheetExportRenderer.generateImage(
            sheetItems: sheetItems,
            options: exportOptions,
            exportProjectName: exportProjectName,
            exportPreparer: exportPreparer
        ) else {
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("material_sheet_\(MaterialSheetExportRenderer.timestampToken()).png")
        do {
            try data.write(to: url)
            exportFileURL = url
            showExportChoice = true
        } catch {
            cleanupExportFileIfNeeded()
        }
    }

    private func cleanupExportFileIfNeeded() {
        guard let exportFileURL else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: exportFileURL,
                context: .init(
                    event: "material_sheet.cleanup_export_file",
                    category: .fileStorage,
                    source: "MaterialSheetView.cleanupExportFileIfNeeded"
                )
            )
        } catch {
            StorageIssueLog.recordEvent(
                "material_sheet.cleanup_export_file_failed",
                category: .fileStorage,
                details: ["file": exportFileURL.lastPathComponent],
                error: error
            )
        }
        self.exportFileURL = nil
        showExportChoice = false
    }

}
