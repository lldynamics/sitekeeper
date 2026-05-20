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
        store.materialSheetDrafts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDate = Formatters.parseDateOrDateTime(lhs.updatedAt) ?? .distantPast
                let rhsDate = Formatters.parseDateOrDateTime(rhs.updatedAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    private var selectedDraft: MaterialSheetDraft? {
        guard let selectedDraftID else { return nil }
        return activeMaterialSheetDrafts.first(where: { $0.id == selectedDraftID })
    }

    private var priceSuggestions: [MaterialPriceEntry] {
        guard !searchText.isEmpty else { return [] }
        return Array(SearchMatcher.filter(store.materialPriceEntries, keyword: searchText).prefix(10))
    }
    private var librarySuggestions: [CommonMaterial] {
        guard !searchText.isEmpty else { return [] }
        return Array(SearchMatcher.filter(MaterialLibrary.all, keyword: searchText).prefix(10))
    }
    private var hasSearchResults: Bool { !priceSuggestions.isEmpty || !librarySuggestions.isEmpty }

    private var totalEstimateValue: MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + lineTotalValue(for: item)
        }
    }
    private var totalLaborValue: MoneyValue {
        sheetItems.reduce(MoneyValue.zero) { total, item in
            total + MoneyValue(text: item.laborCost)
        }
    }
    private var grandTotalValue: MoneyValue {
        totalEstimateValue + totalLaborValue
    }
    private var totalEstimateText: String {
        String(format: "¥%.2f", totalEstimateValue.doubleValue)
    }
    private var totalLaborText: String {
        String(format: "¥%.2f", totalLaborValue.doubleValue)
    }
    private var grandTotalText: String {
        String(format: "¥%.2f", grandTotalValue.doubleValue)
    }

    var body: some View {
        List {
            draftSelectorSection
            materialSearchSection

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

            // Export actions
            if !sheetItems.isEmpty {
                Section(String(localized: "导出与操作")) {
                    Button { exportAsPDF() } label: { Label(String(localized: "导出 PDF"), systemImage: "doc.richtext.fill") }.disabled(isExporting)
                    Button { exportAsCSV() } label: { Label(String(localized: "导出 CSV"), systemImage: "tablecells.fill") }.disabled(isExporting)
                    Button { exportAsImage() } label: { Label(String(localized: "导出图片"), systemImage: "photo") }.disabled(isExporting)
                    Button(role: .destructive) { showClearConfirm = true } label: { Label(String(localized: "清空材料单"), systemImage: "trash") }
                }
            }
        }
        .navigationTitle("材料单").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !sheetItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: exportAsPDF) {
                            Label(String(localized: "导出 PDF"), systemImage: "doc.richtext.fill")
                        }
                        Button(action: exportAsCSV) {
                            Label(String(localized: "导出 CSV"), systemImage: "tablecells.fill")
                        }
                        Button(action: exportAsImage) {
                            Label(String(localized: "导出图片"), systemImage: "photo")
                        }
                        Divider()
                        Button(action: saveSheetToMaterialListAndClear) {
                            Label(String(localized: "保存到材料清单"), systemImage: "shippingbox.fill")
                        }
                    } label: {
                        if isExporting { ProgressView().controlSize(.small) }
                        else { Image(systemName: "square.and.arrow.up") }
                    }.disabled(isExporting)
                }
            }
            KeyboardDismissToolbar {
                AppKeyboard.dismiss()
            }
        }
        .confirmationDialog("导出方式", isPresented: $showExportChoice) {
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
                ProgressView("正在准备导出文件...")
                    .padding()
            }
        }
        .sheet(isPresented: $showCreateDraftSheet) { createDraftSheet }
        .sheet(isPresented: $showRenameDraftSheet) { renameDraftSheet }
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

    private var draftSelectorSection: some View {
        Section(String(localized: "材料单草稿")) {
            if activeMaterialSheetDrafts.isEmpty {
                ContentUnavailableView(
                    "暂无材料单",
                    systemImage: "doc.badge.plus",
                    description: Text(String(localized: "可从材料库点击 + 直接创建，或先在这里新建一个。"))
                )
                Button {
                    prepareCreateDraftSheet()
                } label: {
                    Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                }
                Button {
                    focusMaterialSearch()
                } label: {
                    Label(String(localized: "添加材料"), systemImage: "magnifyingglass")
                }
            } else {
                Picker(String(localized: "当前材料单"), selection: $selectedDraftID) {
                    ForEach(activeMaterialSheetDrafts) { draft in
                        Text(draftDisplayName(draft)).tag(draft.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                if let selectedDraft {
                    let updatedAt = selectedDraft.updatedAt
                    let count = selectedDraft.items.count
                    let projectName = selectedDraft.projectId.flatMap(projectName(for:)) ?? "无归属项目"
                    Text(String(format: String(localized: "%@ · %d 项 · 更新于 %@"), projectName, count, updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        Button {
                            prepareRenameDraftSheet()
                        } label: {
                            Label(String(localized: "重命名当前材料单"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            archiveSelectedDraft()
                        } label: {
                            Label(String(localized: "归档当前材料单"), systemImage: "archivebox")
                        }
                    } label: {
                        Label(String(localized: "管理当前材料单"), systemImage: "ellipsis.circle")
                    }
                }

                Button {
                    prepareCreateDraftSheet()
                } label: {
                    Label(String(localized: "新建材料单"), systemImage: "plus")
                }
                Button {
                    focusMaterialSearch()
                } label: {
                    Label(String(localized: "添加材料"), systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var materialSearchSection: some View {
        Section(String(localized: "添加材料")) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "搜索材料库"), text: $searchText)
                    .submitLabel(.search)
                    .focused($isMaterialSearchFocused)
            }
            if !searchText.isEmpty {
                if !hasSearchResults {
                    ContentUnavailableView(
                        "材料库没有匹配项",
                        systemImage: "shippingbox",
                        description: Text(String(localized: "请先到材料库新增自定义材料，再加入材料单。"))
                    )
                }
                ForEach(priceSuggestions) { librarySearchRow(entry: $0) }
                ForEach(librarySuggestions) { presetSearchRow(material: $0) }
            }
        }
    }

    private var createDraftSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基本信息")) {
                    TextField(String(localized: "材料单名称"), text: $draftTitleInput)
                    Picker(String(localized: "归属项目"), selection: $draftProjectIdInput) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
            }
            .navigationTitle("新建材料单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showCreateDraftSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "创建")) {
                        createDraftAndSelect(title: draftTitleInput, projectId: draftProjectIdInput)
                        showCreateDraftSheet = false
                    }
                }
            }
        }
    }

    private var renameDraftSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "材料单名称")) {
                    TextField(String(localized: "材料单名称"), text: $renameDraftTitleInput)
                }
            }
            .navigationTitle("重命名材料单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showRenameDraftSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        renameSelectedDraft(to: renameDraftTitleInput)
                        showRenameDraftSheet = false
                    }
                }
            }
        }
    }

    private func draftDisplayName(_ draft: MaterialSheetDraft) -> String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "未命名材料单" : title
    }

    private func projectName(for projectId: UUID) -> String? {
        store.projects.first(where: { $0.id == projectId })?.name
    }

    private func defaultDraftTitle(projectId: UUID?) -> String {
        if let projectId,
           let projectName = projectName(for: projectId),
           !projectName.isEmpty {
            return "\(projectName)-材料单"
        }
        return "材料单-\(Formatters.date.string(from: Date()))"
    }

    private func prepareCreateDraftSheet() {
        draftProjectIdInput = selectedDraft?.projectId
        draftTitleInput = defaultDraftTitle(projectId: draftProjectIdInput)
        showCreateDraftSheet = true
    }

    private func prepareRenameDraftSheet() {
        guard let selectedDraft else { return }
        renameDraftTitleInput = draftDisplayName(selectedDraft)
        showRenameDraftSheet = true
    }

    private func createDraftAndSelect(title: String, projectId: UUID?) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = normalizedTitle.isEmpty ? defaultDraftTitle(projectId: projectId) : normalizedTitle
        let now = Formatters.now()
        let newDraft = MaterialSheetDraft(
            title: resolvedTitle,
            projectId: projectId,
            exportProjectName: projectId.flatMap(projectName(for:)) ?? "",
            items: [],
            createdAt: now,
            updatedAt: now
        )
        var drafts = store.materialSheetDrafts
        drafts.insert(newDraft, at: 0)
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
        selectedDraftID = newDraft.id
    }

    private func renameSelectedDraft(to title: String) {
        guard let selectedDraftID,
              let index = store.materialSheetDrafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return
        }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        var drafts = store.materialSheetDrafts
        drafts[index].title = normalizedTitle
        drafts[index].updatedAt = Formatters.now()
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
    }

    private func archiveSelectedDraft() {
        guard let selectedDraftID,
              let index = store.materialSheetDrafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return
        }
        let draft = store.materialSheetDrafts[index]
        let previousDrafts = store.materialSheetDrafts
        let previousSelectedDraftID = selectedDraftID
        var drafts = store.materialSheetDrafts
        drafts[index].isArchived = true
        drafts[index].updatedAt = Formatters.now()
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已归档材料单「%@」"), draftDisplayName(draft)),
            undoMessage: String(localized: "已恢复材料单草稿"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceMaterialSheetDrafts(UndoableDeletionCoordinator.restoringItems(
                    snapshot: previousDrafts,
                    current: store.materialSheetDrafts,
                    deletedIDs: Set([draft.id])
                ))
                self.selectedDraftID = previousSelectedDraftID
                loadSelectedDraftIntoEditor()
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "归档材料单草稿"),
                detail: draftDisplayName(draft),
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
        if let selectedDraftID,
           activeMaterialSheetDraftIDs.contains(selectedDraftID) {
            return
        }
        self.selectedDraftID = activeMaterialSheetDrafts.first?.id
    }

    private func loadSelectedDraftIntoEditor() {
        guard let selectedDraft else { return }
        isApplyingDraftState = true
        sheetItems = selectedDraft.items.map(MaterialSheetItem.init(draftItem:))
        if selectedDraft.exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let projectId = selectedDraft.projectId,
           let projectName = projectName(for: projectId) {
            exportProjectName = projectName
        } else {
            exportProjectName = selectedDraft.exportProjectName
        }
        exportPreparer = selectedDraft.exportPreparer
        itemExpanded.removeAll()
        rowPhotoSelections.removeAll()
        pendingDeleteSheetItemIDs.removeAll()
        isApplyingDraftState = false
    }

    private func persistCurrentDraft() {
        guard !isApplyingDraftState,
              let selectedDraftID,
              let index = store.materialSheetDrafts.firstIndex(where: { $0.id == selectedDraftID }) else {
            return
        }
        var drafts = store.materialSheetDrafts
        drafts[index].items = sheetItems.map(\.draftItem)
        drafts[index].exportProjectName = exportProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[index].exportPreparer = exportPreparer.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts[index].exportDate = Formatters.date.string(from: Date())
        drafts[index].updatedAt = Formatters.now()
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
        let isExpanded = itemExpanded.contains(item.wrappedValue.id)
        return VStack(spacing: 0) {
            // Compact header row
            Button { toggleExpand(item.wrappedValue.id) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.wrappedValue.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if !item.wrappedValue.specification.isEmpty {
                            Text(item.wrappedValue.specification).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text(item.wrappedValue.quantity).font(.callout.weight(.semibold)).foregroundStyle(Color.appPrimaryAction)
                        Text(item.wrappedValue.unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(materialItemAccessibilityLabel(item.wrappedValue, isExpanded: isExpanded))
            .accessibilityHint(isExpanded ? "双击收起编辑项" : "双击展开编辑项")

            // Expanded detail
            if isExpanded {
                Divider().padding(.vertical, 6)
                VStack(spacing: 8) {
                    // Price + Labor row
                    HStack(spacing: 10) {
                        TextField(String(localized: "估价 ¥"), text: item.unitPrice).keyboardType(.decimalPad)
                            .frame(width: 100).textFieldStyle(.roundedBorder).font(.callout)
                        autoFillButton(for: item)
                        TextField(String(localized: "人工费 ¥"), text: item.laborCost).keyboardType(.decimalPad)
                            .frame(width: 100).textFieldStyle(.roundedBorder).font(.callout)
                        Spacer()
                    }

                    // Supplier + Location
                    HStack(spacing: 10) {
                        TextField(String(localized: "供应商"), text: item.supplier)
                            .textFieldStyle(.roundedBorder).font(.callout)
                        TextField(String(localized: "使用部位"), text: item.usageLocation)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }

                    // Note
                    HStack(spacing: 10) {
                        TextField(String(localized: "备注"), text: item.note)
                            .textFieldStyle(.roundedBorder).font(.callout)
                    }

                    // Attachment
                    HStack(spacing: 8) {
                        PhotosPicker(selection: photoSelectionBinding(for: item.wrappedValue.id), maxSelectionCount: 1, matching: .images) {
                            Label(item.wrappedValue.hasAttachment ? "已添加照片" : "添加照片",
                                  systemImage: item.wrappedValue.hasAttachment ? "photo.fill" : "photo.badge.plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .accessibilityLabel(String(format: String(localized: "%@添加或更换照片"), item.wrappedValue.name))

                        if item.wrappedValue.hasAttachment {
                            Text(item.wrappedValue.attachmentFileName ?? "附件")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Button {
                                item.wrappedValue.attachmentData = nil
                                item.wrappedValue.attachmentFileName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(format: String(localized: "移除%@照片"), item.wrappedValue.name))
                        }
                        Spacer()
                    }

                    // Delete
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            requestDeleteSheetItems(ids: [item.wrappedValue.id])
                        } label: {
                            Label(String(localized: "删除此项"), systemImage: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(format: String(localized: "删除%@"), item.wrappedValue.name))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func materialItemAccessibilityLabel(_ item: MaterialSheetItem, isExpanded: Bool) -> String {
        var parts = [item.name]
        if !item.specification.isEmpty { parts.append("规格 \(item.specification)") }
        parts.append("数量 \(item.quantity)\(item.unit)")
        if !item.unitPrice.isEmpty { parts.append("估价 \(item.unitPrice) 元") }
        parts.append(isExpanded ? "已展开" : "已收起")
        return parts.joined(separator: "，")
    }

    private func toggleExpand(_ id: UUID) {
        if itemExpanded.contains(id) { itemExpanded.remove(id) }
        else { itemExpanded.insert(id) }
    }

    private func requestDeleteSheetItems(ids: [UUID]) {
        let normalizedIDs = Set(ids)
        guard !normalizedIDs.isEmpty else { return }
        pendingDeleteSheetItemIDs = normalizedIDs
        showDeleteItemConfirm = true
    }

    private func confirmDeleteSheetItems() {
        let ids = pendingDeleteSheetItemIDs
        guard !ids.isEmpty else { return }
        let count = sheetItems.filter { ids.contains($0.id) }.count
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
        ListFormatter.localizedString(
            byJoining: items.map { item in
                let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let specification = item.specification.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { return String(localized: "未命名材料") }
                return specification.isEmpty ? name : "\(name) \(specification)"
            }
        )
    }

    @ViewBuilder
    private func autoFillButton(for item: Binding<MaterialSheetItem>) -> some View {
        let name = item.wrappedValue.name
        let spec = item.wrappedValue.specification
        let match = store.materialPriceEntries.first { e in
            e.name.localizedCaseInsensitiveContains(name) && (spec.isEmpty || e.specification.localizedCaseInsensitiveContains(spec))
        }
        let price = match?.referencePrice ?? ""
        if !price.isEmpty, price != item.wrappedValue.unitPrice {
            Button { item.wrappedValue.unitPrice = price } label: {
                Text("¥\(price)").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.appPrimarySurfaceSubtle, in: Capsule()).foregroundStyle(Color.appPrimaryAction)
            }
            .buttonStyle(.borderless)
        }
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

    private func lineTotalValue(for item: MaterialSheetItem) -> MoneyValue {
        QuantityValue(text: item.quantity) * MoneyValue(text: item.unitPrice)
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
            let q = item.quantity.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalQty: String
            if QuantityValue(text: q).isPositive {
                finalQty = q
            } else {
                finalQty = "1"
            }
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(MaterialSheetExportRenderer.timestampToken()).pdf")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(MaterialSheetExportRenderer.timestampToken()).csv")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("材料单_\(MaterialSheetExportRenderer.timestampToken()).png")
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
