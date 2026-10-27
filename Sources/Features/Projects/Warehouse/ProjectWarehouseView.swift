import SwiftUI

struct ProjectWarehouseOverviewView: View {
    @Environment(DataStore.self) private var store
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var importErrorMessage = ""
    @State private var showImportError = false

    private var filteredProjects: [Project] {
        SearchMatcher.filter(
            store.projects,
            keyword: searchText,
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    var body: some View {
        let stockByProject = Dictionary(uniqueKeysWithValues: store.projects.map { project in
            (project.id, WarehouseStockCalculator.stockLines(for: project.id, movements: store.projectStore.projectWarehouseMovements(for: project.id)))
        })
        List {
            Section(AppLocalization.string("汇总")) {
                LabeledContent(AppLocalization.string("有库存项目"), value: "\(stockByProject.values.filter { !$0.isEmpty }.count)")
                LabeledContent(AppLocalization.string("库存材料种类"), value: "\(stockByProject.values.reduce(0) { $0 + $1.count })")
                LabeledContent(AppLocalization.string("负库存项"), value: "\(stockByProject.values.reduce(0) { $0 + $1.filter { $0.quantity.isNegative }.count })")
            }

            Section(AppLocalization.string("项目仓库")) {
                if filteredProjects.isEmpty {
                    ContentUnavailableView(AppLocalization.string("暂无项目"), systemImage: "shippingbox")
                } else {
                    ForEach(filteredProjects) { project in
                        projectRow(project, stockCount: stockByProject[project.id]?.count ?? 0)
                    }
                }
            }
        }
        .navigationTitle(AppLocalization.string("项目仓库"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索项目"))
        .toolbar {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus").visibleIconStyle()
            }
            .buttonStyle(.appIcon())
            .accessibilityLabel(AppLocalization.string("新增出入库记录"))
            .accessibilityHint(AppLocalization.string("打开出入库表单"))
        }
        .sheet(isPresented: $showAdd) {
            ProjectWarehouseMovementSheet(projects: store.projects) { movement, attachments in
                saveMovement(movement, attachments: attachments)
            }
        }
        .alert(AppLocalization.string("附件导入失败"), isPresented: $showImportError) {
            Button(AppLocalization.string("知道了"), role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func projectRow(_ project: Project, stockCount: Int) -> some View {
        let movementCount = store.projectStore.projectWarehouseMovements(for: project.id).count
        return NavigationLink {
            ProjectWarehouseView(project: project)
        } label: {
            ProjectWarehouseProjectRow(project: project, stockCount: stockCount, movementCount: movementCount)
        }
    }

    private func saveMovement(_ movement: ProjectWarehouseMovement, attachments: [ProjectWarehouseAttachmentDraft]) {
        var value = movement
        let result = ProjectWarehouseAttachmentImporter.importAttachments(attachments, movement: value, store: store)
        value.linkedDocumentIds = result.documents.map(\.id)
        store.appendProjectDocuments(result.documents)
        store.insertProjectWarehouseMovementAtTop(value)
        store.scheduleSave()
        showAttachmentFailures(result.failures)
    }

    private func showAttachmentFailures(_ failures: [String]) {
        guard !failures.isEmpty else { return }
        importErrorMessage = String(format: AppLocalization.string("以下附件未能导入：%@"), failures.joined(separator: AppLocalization.string("、")))
        showImportError = true
    }
}

struct ProjectWarehouseView: View {
    @State private var movementPageIndex = 0
    @State private var stockPageIndex = 0
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let project: Project
    @State private var showAdd = false
    @State private var importErrorMessage = ""
    @State private var showImportError = false
    @State private var showDeleteMovementConfirm = false
    @State private var pendingDeleteMovementIds: Set<UUID> = []
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    private var movements: [ProjectWarehouseMovement] {
        store.projectStore.projectWarehouseMovements(for: project.id)
            .sorted { $0.date > $1.date }
    }

    private var stockLines: [WarehouseStockLine] {
        WarehouseStockCalculator.stockLines(for: project.id, movements: store.projectWarehouseMovements)
    }

    private var usesWarehouseSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesWarehouseSplitLayout {
                HStack(alignment: .top, spacing: 12) {
                    List {
                        warehouseActionSection
                        stockSummarySection
                    }
                    .frame(minWidth: 300, maxWidth: 360)

                    List {
                        movementFlowSection
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                List {
                    warehouseActionSection
                    stockSummarySection
                    movementFlowSection
                }
            }
        }
        .navigationTitle(AppLocalization.string("仓库"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            ProjectWarehouseMovementSheet(projects: [project], fixedProjectId: project.id) { movement, attachments in
                saveMovement(movement, attachments: attachments)
            }
        }
        .alert(AppLocalization.string("附件导入失败"), isPresented: $showImportError) {
            Button(AppLocalization.string("知道了"), role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .confirmationDialog(AppLocalization.string("删除出入库流水"), isPresented: $showDeleteMovementConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string("仅删除流水"), role: .destructive) {
                deleteMovements(ids: pendingDeleteMovementIds, deleteAttachments: false)
            }
            Button(AppLocalization.string("同时删除附件"), role: .destructive) {
                deleteMovements(ids: pendingDeleteMovementIds, deleteAttachments: true)
            }
            Button(AppLocalization.string("取消"), role: .cancel) {
                pendingDeleteMovementIds.removeAll()
            }
        } message: {
            Text(
                String(
                    format: AppLocalization.string("将删除 %lld 条出入库流水。可选择保留资料原件，避免误删送货单/照片。"),
                    Int64(pendingDeleteMovementIds.count)
                )
            )
        }
        .onDisappear {
            flushPendingWarehouseDeletionIfNeeded()
        }
        .operationToast(notice: $operationNotice)
    }

    private var warehouseActionSection: some View {
        Section(AppLocalization.string("仓库操作")) {
            Button {
                showAdd = true
            } label: {
                Label(AppLocalization.string("材料出入库"), systemImage: "shippingbox.and.arrow.backward.fill")
            }
        }
    }

    private var stockSummarySection: some View {
        let page = RecordPage(stockLines, index: stockPageIndex)
        return Section(AppLocalization.string("库存汇总")) {
            if stockLines.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("暂无库存"),
                    systemImage: "shippingbox",
                    description: Text(AppLocalization.string("记录材料入库、出库或退料后，这里会自动汇总库存。"))
                )
                Button {
                    showAdd = true
                } label: {
                    Label(AppLocalization.string("材料出入库"), systemImage: "shippingbox.and.arrow.backward.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                ForEach(page.items) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.materialName)
                                .font(.body.weight(.medium))
                            Text([line.specification, line.unit].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(WarehouseStockCalculator.quantityText(line.quantity))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(line.quantity.isNegative ? .appRisk : Color.appPrimaryAction)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(format: AppLocalization.string("%@，库存 %@"), line.materialName, WarehouseStockCalculator.quantityText(line.quantity)))
                }
                RecordPageControls(index: page.index, count: page.count, selection: $stockPageIndex)
            }
        }
    }

    private var movementFlowSection: some View {
        let page = RecordPage(movements, index: movementPageIndex)
        return Section(AppLocalization.string("出入库流水")) {
            if movements.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("暂无出入库记录"),
                    systemImage: "arrow.left.arrow.right.square",
                    description: Text(AppLocalization.string("添加入库或出库后可追踪库存流向。"))
                )
            } else {
                ForEach(page.items) { movement in
                    NavigationLink {
                        ProjectWarehouseMovementDetailView(
                            movement: movement,
                            documents: linkedDocuments(for: movement)
                        )
                    } label: {
                        WarehouseMovementRow(movement: movement)
                    }
                }
                .onDelete(perform: requestDeleteMovements)
                RecordPageControls(index: page.index, count: page.count, selection: $movementPageIndex)
            }
        }
    }

    private func requestDeleteMovements(_ offsets: IndexSet) {
        let items = RecordPage(movements, index: movementPageIndex).items
        pendingDeleteMovementIds = Set(offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil })
        showDeleteMovementConfirm = !pendingDeleteMovementIds.isEmpty
    }

    private func deleteMovements(ids: Set<UUID>, deleteAttachments: Bool) {
        guard !ids.isEmpty else { return }
        flushPendingWarehouseDeletionIfNeeded()

        guard let deletion = ProjectWarehouseDeletionActions.execute(
            ids: ids,
            deleteAttachments: deleteAttachments,
            store: store
        ) else { return }

        pendingDeleteMovementIds.removeAll()

        let message = deleteAttachments
        ? String(format: AppLocalization.string("已删除 %lld 条出入库流水（含附件）"), Int64(deletion.movements.deletedCount))
        : String(format: AppLocalization.string("已删除 %lld 条出入库流水"), Int64(deletion.movements.deletedCount))
        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            commit: {
                deletion.commit(in: store)
            },
            undo: {
                deletion.restore(in: store)
            },
            audit: deletion.movements.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func linkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let ids = Set(movement.linkedDocumentIds)
        return store.projectDocuments.filter { ids.contains($0.id) }
    }

    private func saveMovement(_ movement: ProjectWarehouseMovement, attachments: [ProjectWarehouseAttachmentDraft]) {
        var value = movement
        let result = ProjectWarehouseAttachmentImporter.importAttachments(attachments, movement: value, store: store)
        value.linkedDocumentIds = result.documents.map(\.id)
        store.appendProjectDocuments(result.documents)
        store.insertProjectWarehouseMovementAtTop(value)
        autoAddToMaterialLibrary(movement: value)
        store.scheduleSave()
        showAttachmentFailures(result.failures)
    }

    private func autoAddToMaterialLibrary(movement: ProjectWarehouseMovement) {
        let name = movement.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = movement.specification.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = movement.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let key = [name.lowercased(), spec.lowercased(), unit.lowercased()].joined(separator: "|")
        let exists = store.materialPriceEntries.contains { entry in
            let ek = [entry.name.lowercased(), entry.specification.lowercased(), entry.unit.lowercased()].joined(separator: "|")
            return ek == key
        }
        guard !exists else { return }

        let entry = MaterialPriceEntry(
            name: name,
            specification: spec,
            unit: unit
        )
        store.appendMaterialPriceEntry(entry)
    }

    private func showAttachmentFailures(_ failures: [String]) {
        guard !failures.isEmpty else { return }
        importErrorMessage = String(format: AppLocalization.string("以下附件未能导入：%@"), failures.joined(separator: AppLocalization.string("、")))
        showImportError = true
    }

    private func flushPendingWarehouseDeletionIfNeeded() {
        undoableDeletion.flushPendingCommit()
    }
}
