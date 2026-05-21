import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DrawingLibraryToolView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedProjectID: UUID?
    @State private var quickLookURL: URL?
    @State private var shareURL: URL?
    @State private var shareDrawingID: UUID?
    @State private var operationMessage: String?
    @State private var showDrawingImporter = false
    @State private var pendingImportURLs: [URL] = []
    @State private var showImportProjectPicker = false
    @State private var pendingImportProjectID: UUID?
    @State private var pendingImportConflictNames: [String] = []
    @State private var showImportStrategyDialog = false
    @State private var searchText = ""
    @State private var availabilityFilter: DrawingAvailabilityFilter = .all
    @State private var showHistoricalDrawings = false
    @AppStorage(UserPreferenceKeys.drawingLibraryRecentDrawingIDs) private var recentDrawingIDsRaw = ""

    private static let drawingImportTypes: [UTType] = {
        var types: [UTType] = [.pdf, .zip]
        if let dwg = UTType(filenameExtension: "dwg") {
            types.append(dwg)
        }
        if let dxf = UTType(filenameExtension: "dxf") {
            types.append(dxf)
        }
        if !types.contains(.item) {
            types.append(.item)
        }
        return types
    }()

    private var listModel: DrawingListViewModel {
        DrawingListViewModel(
            projects: store.projects,
            drawings: store.projectDrawings,
            selectedProjectID: selectedProjectID,
            searchText: searchText,
            recentDrawingIDs: DrawingListViewModel.recentDrawingIDs(from: recentDrawingIDsRaw),
            availabilityFilter: availabilityFilter
        )
    }

    private var importStrategyMessage: String {
        DrawingImportCoordinator.importStrategyMessage(for: pendingImportConflictNames)
    }

    private var drawingSearchSuggestions: [RealtimeSearchSuggestion] {
        listModel.filteredDrawings.prefix(8).map { drawing in
            RealtimeSearchSuggestion(
                id: "drawing-\(drawing.id.uuidString)",
                category: .drawing,
                entityId: drawing.id,
                title: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                subtitleParts: [
                    listModel.projectName(for: drawing.projectId),
                    drawing.drawingNumber,
                    drawing.discipline,
                    drawing.floorArea
                ],
                score: drawing.isCurrentVersion ? 120 : 100
            )
        }
    }

    private var shareSheetPresented: Binding<Bool> {
        Binding(
            get: { shareURL != nil },
            set: { isPresented in
                if !isPresented {
                    shareURL = nil
                    shareDrawingID = nil
                }
            }
        )
    }

    var body: some View {
        List {
            Section(String(localized: "项目筛选")) {
                Picker(String(localized: "查看范围"), selection: $selectedProjectID) {
                    Text(String(localized: "全部项目")).tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }

            Section(String(localized: "图纸能力边界")) {
                InlineNotice(
                    title: String(localized: "图纸台账 + 外部打开"),
                    message: String(localized: "App 管理 DWG / DXF / PDF 原件、版本、当前版和交付导出；DWG/DXF 原件通过外部专业看图软件打开，PDF 使用系统预览。"),
                    tone: .info
                )
            }

            Section(String(localized: "快速查找")) {
                InlineSearchPanel(
                    text: $searchText,
                    prompt: String(localized: "搜索名称、图号、专业、楼层、项目"),
                    suggestions: drawingSearchSuggestions,
                    emptyStateText: String(localized: "未找到匹配图纸")
                ) { suggestion in
                    guard let drawing = listModel.filteredDrawings.first(where: { $0.id == suggestion.entityId }) else { return }
                    openDrawing(drawing)
                }
                if !listModel.normalizedSearchText.isEmpty {
                    Text(String(format: String(localized: "匹配 %lld 张图纸"), Int64(listModel.filteredDrawings.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "状态筛选")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DrawingAvailabilityFilter.allCases) { filter in
                            DrawingAvailabilityFilterChip(
                                filter: filter,
                                count: listModel.count(for: filter),
                                isSelected: availabilityFilter == filter
                            ) {
                                availabilityFilter = filter
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                if let summary = listModel.filteredResultSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    scanDrawingFileAvailability()
                } label: {
                    Label(String(localized: "扫描原件状态"), systemImage: "checkmark.folder.fill")
                }
            }

            if !listModel.recentDrawings.isEmpty {
                Section(String(localized: "最近打开")) {
                    ForEach(listModel.recentDrawings.prefix(3)) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                }
            }

            Section(selectedProjectID == nil ? String(localized: "图纸台账") : String(localized: "项目图纸")) {
                if listModel.filteredDrawings.isEmpty {
                    ContentUnavailableView(
                        String(localized: "暂无图纸"),
                        systemImage: "doc.viewfinder",
                        description: Text(String(localized: "先导入 DWG / DXF / PDF 图纸原件，App 负责台账、版本、当前版和交付导出；DWG/DXF 通过外部专业看图软件打开。"))
                    )
                } else {
                    ForEach(listModel.currentFilteredDrawings) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                    if !listModel.historicalFilteredDrawings.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHistoricalDrawings.toggle()
                            }
                        } label: {
                            HStack {
                                Label(
                                    String(
                                        format: String(localized: "历史版本 (%lld)"),
                                        Int64(listModel.historicalFilteredDrawings.count)
                                    ),
                                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                                )
                                Spacer()
                                Image(systemName: showHistoricalDrawings ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showHistoricalDrawings {
                            ForEach(listModel.historicalFilteredDrawings) { drawing in
                                drawingRow(drawing, showsProject: selectedProjectID == nil)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "图纸台账"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    beginImportDrawings()
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "导入图纸"))
            }
        }
        .fileImporter(
            isPresented: $showDrawingImporter,
            allowedContentTypes: Self.drawingImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                handleImportedDrawings(urls)
            case .failure(let error):
                StorageIssueLog.record(
                    String(format: String(localized: "图纸台账导入失败：%@"), error.localizedDescription)
                )
                operationMessage = String(format: String(localized: "图纸导入失败：%@"), error.localizedDescription)
            }
        }
        .confirmationDialog(String(localized: "选择导入项目"), isPresented: $showImportProjectPicker, titleVisibility: .visible) {
            ForEach(store.projects) { project in
                Button(project.name) {
                    prepareImportDrawings(pendingImportURLs, projectId: project.id)
                }
            }
            Button(String(localized: "取消"), role: .cancel) {
                pendingImportURLs.removeAll()
            }
        } message: {
            Text(String(localized: "请选择图纸归属的项目。"))
        }
        .confirmationDialog(String(localized: "同名图纸导入策略"), isPresented: $showImportStrategyDialog, titleVisibility: .visible) {
            ForEach(ProjectDrawingImportStrategy.allCases) { strategy in
                Button(strategy.displayName) {
                    applyImportStrategy(strategy)
                }
            }
            Button(String(localized: "取消"), role: .cancel) {
                clearImportStrategyState()
            }
        } message: {
            Text(importStrategyMessage)
        }
        .quickLookPreview($quickLookURL)
        .sheet(isPresented: shareSheetPresented) {
            if let shareURL {
                ActivityShareSheet(activityItems: [shareURL], onComplete: { completed in
                    ProjectDetailAssetActions.recordDrawingExternalOpenResult(
                        completed: completed,
                        drawingID: shareDrawingID,
                        store: store
                    )
                    self.shareURL = nil
                    self.shareDrawingID = nil
                })
            }
        }
        .operationToast(message: $operationMessage)
    }

    private func drawingRow(_ drawing: ProjectDrawing, showsProject: Bool) -> some View {
        DrawingRow(
            drawing: drawing,
            projectName: showsProject ? listModel.projectName(for: drawing.projectId) : nil
        ) {
            openDrawing(drawing)
        }
    }

    private func openDrawing(_ drawing: ProjectDrawing) {
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing, store: store) {
        case .success(let url):
            recordRecentDrawing(drawing.id)
            if drawing.fileType.lowercased() == "pdf" {
                quickLookURL = url
            } else {
                shareDrawingID = drawing.id
                shareURL = url
            }
        case .failure(let message):
            StorageIssueLog.record(
                String(
                    format: String(localized: "图纸原件打开失败：%@，%@"),
                    drawing.name.isEmpty ? drawing.fileName : drawing.name,
                    message
                )
            )
            operationMessage = message
        }
    }

    private func beginImportDrawings() {
        guard !store.projects.isEmpty else {
            operationMessage = String(localized: "请先创建项目，再导入图纸。")
            return
        }
        showDrawingImporter = true
    }

    private func handleImportedDrawings(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let projectID = selectedProjectID {
            prepareImportDrawings(urls, projectId: projectID)
            return
        }
        if store.projects.count == 1, let projectID = store.projects.first?.id {
            prepareImportDrawings(urls, projectId: projectID)
            return
        }
        pendingImportURLs = urls
        showImportProjectPicker = true
    }

    private func prepareImportDrawings(_ urls: [URL], projectId: UUID) {
        guard !urls.isEmpty else { return }
        pendingImportProjectID = nil
        pendingImportConflictNames.removeAll()
        showImportStrategyDialog = false
        let conflicts = DrawingImportCoordinator.conflictedDrawingNames(for: urls, projectId: projectId, store: store)
        guard !conflicts.isEmpty else {
            pendingImportURLs.removeAll()
            performImportDrawings(urls, projectId: projectId, strategy: .createNewVersion)
            return
        }
        pendingImportURLs = urls
        pendingImportProjectID = projectId
        pendingImportConflictNames = conflicts
        showImportStrategyDialog = true
    }

    private func applyImportStrategy(_ strategy: ProjectDrawingImportStrategy) {
        guard let projectId = pendingImportProjectID else { return }
        let urls = pendingImportURLs
        clearImportStrategyState()
        guard !urls.isEmpty else { return }
        performImportDrawings(urls, projectId: projectId, strategy: strategy)
    }

    private func clearImportStrategyState() {
        pendingImportURLs.removeAll()
        pendingImportProjectID = nil
        pendingImportConflictNames.removeAll()
        showImportStrategyDialog = false
    }

    private func performImportDrawings(_ urls: [URL], projectId: UUID, strategy: ProjectDrawingImportStrategy) {
        let result = DrawingImportCoordinator.importDrawings(
            urls,
            projectId: projectId,
            strategy: strategy,
            store: store,
            replacementCleanupSummary: "drawingLibrary.importReplacement"
        )
        if result.didImport {
            selectedProjectID = projectId
            store.scheduleSave()
        }
        operationMessage = result.operationMessage
    }

    private func scanDrawingFileAvailability() {
        let drawings = listModel.scannableDrawings
        guard !drawings.isEmpty else {
            operationMessage = String(localized: "没有可扫描的图纸原件。")
            return
        }

        let now = Formatters.now()
        var availableCount = 0
        var missingCount = 0
        var didChange = false

        for drawing in drawings {
            let exists = DrawingStorage.exists(fileName: drawing.fileName)
            let status: ProjectDrawingFileAvailabilityStatus = exists ? .available : .missing
            if exists {
                availableCount += 1
            } else {
                missingCount += 1
            }

            store.mutateProjectDrawing(id: drawing.id) { item in
                if item.fileAvailabilityStatus != status {
                    item.fileAvailabilityStatus = status
                    didChange = true
                }
                if item.fileAvailabilityCheckedAt != now {
                    item.fileAvailabilityCheckedAt = now
                    didChange = true
                }
            }
        }

        if didChange {
            store.scheduleSave()
        }
        if missingCount > 0 {
            availabilityFilter = .missing
        }
        operationMessage = String(
            format: String(localized: "已扫描 %lld 张图纸：可用 %lld，缺失 %lld"),
            Int64(drawings.count),
            Int64(availableCount),
            Int64(missingCount)
        )
    }

    private func recordRecentDrawing(_ drawingID: UUID) {
        recentDrawingIDsRaw = DrawingListViewModel.rawRecentDrawingIDs(recording: drawingID, in: recentDrawingIDsRaw)
    }
}

private struct DrawingAvailabilityFilterChip: View {
    let filter: DrawingAvailabilityFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                Text(filter.title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.appDoc : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(localized: "%@，%lld 张图纸"),
                filter.title,
                Int64(count)
            )
        )
    }
}
