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
        List {
            Section("汇总") {
                LabeledContent("有库存项目", value: "\(projectsWithStockCount)")
                LabeledContent("库存材料种类", value: "\(allStockLines.count)")
                LabeledContent("负库存项", value: "\(negativeStockCount)")
            }

            Section("项目仓库") {
                if filteredProjects.isEmpty {
                    ContentUnavailableView("暂无项目", systemImage: "shippingbox")
                } else {
                    ForEach(filteredProjects) { project in
                        projectRow(project)
                    }
                }
            }
        }
        .navigationTitle("项目仓库")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索项目")
        .toolbar {
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus").visibleIconStyle()
            }
            .buttonStyle(.appIcon())
            .accessibilityLabel("新增出入库记录")
            .accessibilityHint("打开出入库表单")
        }
        .sheet(isPresented: $showAdd) {
            ProjectWarehouseMovementSheet(projects: store.projects) { movement, attachments in
                saveMovement(movement, attachments: attachments)
            }
        }
        .alert("附件导入失败", isPresented: $showImportError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private var allStockLines: [WarehouseStockLine] {
        store.projects.flatMap {
            WarehouseStockCalculator.stockLines(for: $0.id, movements: store.projectWarehouseMovements)
        }
    }

    private var projectsWithStockCount: Int {
        store.projects.filter {
            !WarehouseStockCalculator.stockLines(for: $0.id, movements: store.projectWarehouseMovements).isEmpty
        }.count
    }

    private var negativeStockCount: Int {
        allStockLines.filter { $0.quantity < 0 }.count
    }

    private func projectRow(_ project: Project) -> some View {
        let stockCount = WarehouseStockCalculator.stockLines(for: project.id, movements: store.projectWarehouseMovements).count
        let movementCount = store.projectWarehouseMovements.filter { $0.projectId == project.id }.count
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
        importErrorMessage = "以下附件未能导入：\(failures.joined(separator: "、"))"
        showImportError = true
    }
}

struct ProjectWarehouseView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let project: Project
    @State private var showAdd = false
    @State private var importErrorMessage = ""
    @State private var showImportError = false
    @State private var showDeleteMovementConfirm = false
    @State private var pendingDeleteMovementIds: Set<UUID> = []
    @State private var operationNotice: OperationToastNotice?
    @State private var pendingDeleteCommitTask: Task<Void, Never>?
    @State private var pendingDeleteCommit: (() -> Void)?

    private var movements: [ProjectWarehouseMovement] {
        store.projectWarehouseMovements
            .filter { $0.projectId == project.id }
            .sorted { $0.date > $1.date }
    }

    private var stockLines: [WarehouseStockLine] {
        WarehouseStockCalculator.stockLines(for: project.id, movements: store.projectWarehouseMovements)
    }

    private var usesWarehouseSplitLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
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
        .navigationTitle("仓库")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            ProjectWarehouseMovementSheet(projects: [project], fixedProjectId: project.id) { movement, attachments in
                saveMovement(movement, attachments: attachments)
            }
        }
        .alert("附件导入失败", isPresented: $showImportError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .confirmationDialog("删除出入库流水", isPresented: $showDeleteMovementConfirm, titleVisibility: .visible) {
            Button("仅删除流水", role: .destructive) {
                deleteMovements(ids: pendingDeleteMovementIds, deleteAttachments: false)
            }
            Button("同时删除附件", role: .destructive) {
                deleteMovements(ids: pendingDeleteMovementIds, deleteAttachments: true)
            }
            Button("取消", role: .cancel) {
                pendingDeleteMovementIds.removeAll()
            }
        } message: {
            Text(
                String(
                    format: String(localized: "将删除 %lld 条出入库流水。可选择保留资料原件，避免误删送货单/照片。"),
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
        Section("仓库操作") {
            Button {
                showAdd = true
            } label: {
                Label("材料出入库", systemImage: "shippingbox.and.arrow.backward.fill")
            }
        }
    }

    private var stockSummarySection: some View {
        Section("库存汇总") {
            if stockLines.isEmpty {
                ContentUnavailableView(
                    "暂无库存",
                    systemImage: "shippingbox",
                    description: Text("记录材料入库、出库或退料后，这里会自动汇总库存。")
                )
                Button {
                    showAdd = true
                } label: {
                    Label("材料出入库", systemImage: "shippingbox.and.arrow.backward.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                ForEach(stockLines) { line in
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
                            .foregroundStyle(line.quantity < 0 ? .appRisk : Color.appPrimaryAction)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(line.materialName)，库存 \(WarehouseStockCalculator.quantityText(line.quantity))")
                }
            }
        }
    }

    private var movementFlowSection: some View {
        Section("出入库流水") {
            if movements.isEmpty {
                ContentUnavailableView(
                    "暂无出入库记录",
                    systemImage: "arrow.left.arrow.right.square",
                    description: Text("添加入库或出库后可追踪库存流向。")
                )
            } else {
                ForEach(movements) { movement in
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
            }
        }
    }

    private func requestDeleteMovements(_ offsets: IndexSet) {
        pendingDeleteMovementIds = Set(offsets.compactMap { movements.indices.contains($0) ? movements[$0].id : nil })
        showDeleteMovementConfirm = !pendingDeleteMovementIds.isEmpty
    }

    private func deleteMovements(ids: Set<UUID>, deleteAttachments: Bool) {
        guard !ids.isEmpty else { return }
        flushPendingWarehouseDeletionIfNeeded()

        let movementSnapshot = store.projectWarehouseMovements
        let documentSnapshot = store.projectDocuments
        let financialSnapshot = store.projectFinancialRecords

        var updatedMovements = movementSnapshot.filter { !ids.contains($0.id) }
        var updatedDocuments = documentSnapshot
        var updatedFinancialRecords = financialSnapshot
        var removableFileNames: [String] = []

        if deleteAttachments {
            let linkedDocumentIds = Set(
                movementSnapshot
                    .filter { ids.contains($0.id) }
                    .flatMap(\.linkedDocumentIds)
            )
            let remainingMovementDocumentIds = Set(updatedMovements.flatMap(\.linkedDocumentIds))
            let linkedFinancialDocumentIds = Set(financialSnapshot.flatMap(\.linkedDocumentIds))
            let removableDocumentIds = linkedDocumentIds
                .subtracting(remainingMovementDocumentIds)
                .subtracting(linkedFinancialDocumentIds)
            if !removableDocumentIds.isEmpty {
                removableFileNames = updatedDocuments
                    .filter { removableDocumentIds.contains($0.id) }
                    .map(\.fileName)
                updatedDocuments.removeAll { removableDocumentIds.contains($0.id) }
                for index in updatedFinancialRecords.indices {
                    updatedFinancialRecords[index].linkedDocumentIds.removeAll { removableDocumentIds.contains($0) }
                }
                for index in updatedMovements.indices {
                    updatedMovements[index].linkedDocumentIds.removeAll { removableDocumentIds.contains($0) }
                }
            }
        }

        store.projectWarehouseMovements = updatedMovements
        store.projectDocuments = updatedDocuments
        store.projectFinancialRecords = updatedFinancialRecords
        pendingDeleteMovementIds.removeAll()

        pendingDeleteCommit = {
            for fileName in removableFileNames {
                ProjectDocumentStorage.delete(fileName: fileName)
            }
            store.scheduleSave()
        }
        pendingDeleteCommitTask = Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(4)) else { return }
            pendingDeleteCommit?()
            pendingDeleteCommit = nil
            pendingDeleteCommitTask = nil
        }

        let message = deleteAttachments
        ? String(format: String(localized: "已删除 %lld 条出入库流水（含附件）"), Int64(ids.count))
        : String(format: String(localized: "已删除 %lld 条出入库流水"), Int64(ids.count))
        operationNotice = OperationToastNotice(
            message: message,
            actionTitle: String(localized: "撤销"),
            action: {
                pendingDeleteCommitTask?.cancel()
                pendingDeleteCommitTask = nil
                pendingDeleteCommit = nil
                store.projectWarehouseMovements = movementSnapshot
                store.projectDocuments = documentSnapshot
                store.projectFinancialRecords = financialSnapshot
                store.scheduleSave()
                operationNotice = .info(String(localized: "已撤销删除"))
            },
            autoDismissDuration: .seconds(4)
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
        importErrorMessage = "以下附件未能导入：\(failures.joined(separator: "、"))"
        showImportError = true
    }

    private func flushPendingWarehouseDeletionIfNeeded() {
        pendingDeleteCommitTask?.cancel()
        pendingDeleteCommitTask = nil
        pendingDeleteCommit?()
        pendingDeleteCommit = nil
    }
}
