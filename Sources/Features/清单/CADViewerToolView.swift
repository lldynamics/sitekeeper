import SwiftUI
import UniformTypeIdentifiers

struct CADViewerToolView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedProjectID: UUID?
    @State private var previewRequest: ProjectCADPreviewRequest?
    @State private var operationMessage: String?
    @State private var showDrawingImporter = false
    @State private var pendingImportURLs: [URL] = []
    @State private var showImportProjectPicker = false
    @State private var pendingImportProjectID: UUID?
    @State private var pendingImportConflictNames: [String] = []
    @State private var showImportStrategyDialog = false
    @State private var searchText = ""
    @AppStorage(UserPreferenceKeys.cadViewerRecentDrawingIDs) private var recentDrawingIDsRaw = ""

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

    private var sortedDrawings: [ProjectDrawing] {
        store.projectDrawings
            .filter(isSupportedDrawing)
            .sorted { lhs, rhs in
                let left = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
                let right = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
                if left != right {
                    return left > right
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredDrawings: [ProjectDrawing] {
        let scoped = selectedProjectID.map { projectId in
            sortedDrawings.filter { $0.projectId == projectId }
        } ?? sortedDrawings
        guard !normalizedSearchText.isEmpty else { return scoped }
        return scoped.filter(matchesSearch(_:))
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentDrawingIDs: [UUID] {
        recentDrawingIDsRaw
            .split(separator: "\n")
            .compactMap { UUID(uuidString: String($0)) }
    }

    private var recentDrawings: [ProjectDrawing] {
        recentDrawingIDs.compactMap { id in
            sortedDrawings.first(where: { $0.id == id })
        }
    }

    private var isCADKernelReady: Bool {
        CADDrawingCapability.isCADEngineInstalled() && CADRendererProvider.isRendererBound
    }

    private var importStrategyMessage: String {
        guard !pendingImportConflictNames.isEmpty else {
            return "检测到同名图纸，请选择导入策略。"
        }
        let preview = pendingImportConflictNames.prefix(3).joined(separator: "、")
        if pendingImportConflictNames.count > 3 {
            return "检测到同名图纸：\(preview) 等 \(pendingImportConflictNames.count) 项，请选择导入策略。"
        }
        return "检测到同名图纸：\(preview)，请选择导入策略。"
    }

    var body: some View {
        List {
            Section("项目筛选") {
                Picker("查看范围", selection: $selectedProjectID) {
                    Text("全部项目").tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }

            Section("快速查找") {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索图纸名称、项目", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                if !normalizedSearchText.isEmpty {
                    Text("匹配 \(filteredDrawings.count) 张图纸")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !recentDrawings.isEmpty {
                Section("最近打开") {
                    ForEach(recentDrawings.prefix(3)) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                }
            }

            Section(selectedProjectID == nil ? "全部图纸" : "项目图纸") {
                if filteredDrawings.isEmpty {
                    ContentUnavailableView(
                        "暂无 CAD 图纸",
                        systemImage: "doc.viewfinder",
                        description: Text("先在项目详情里导入 DWG / DXF 图纸；PDF 图纸会作为附件打开。")
                    )
                } else {
                    ForEach(filteredDrawings) { drawing in
                        drawingRow(drawing, showsProject: selectedProjectID == nil)
                    }
                }
            }
        }
        .navigationTitle("CAD 看图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    beginImportDrawings()
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .accessibilityLabel("导入图纸")
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
                StorageIssueLog.record("CAD 看图导入失败：\(error.localizedDescription)")
                operationMessage = "图纸导入失败：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("选择导入项目", isPresented: $showImportProjectPicker, titleVisibility: .visible) {
            ForEach(store.projects) { project in
                Button(project.name) {
                    prepareImportDrawings(pendingImportURLs, projectId: project.id)
                }
            }
            Button("取消", role: .cancel) {
                pendingImportURLs.removeAll()
            }
        } message: {
            Text("请选择图纸归属的项目。")
        }
        .confirmationDialog("同名图纸导入策略", isPresented: $showImportStrategyDialog, titleVisibility: .visible) {
            ForEach(ProjectDrawingImportStrategy.allCases) { strategy in
                Button(strategy.displayName) {
                    applyImportStrategy(strategy)
                }
            }
            Button("取消", role: .cancel) {
                clearImportStrategyState()
            }
        } message: {
            Text(importStrategyMessage)
        }
        .fullScreenCover(item: $previewRequest) { request in
            CADPreviewContainer(request: request)
        }
        .operationToast(message: $operationMessage)
    }

    private func drawingRow(_ drawing: ProjectDrawing, showsProject: Bool) -> some View {
        Button {
            openDrawing(drawing)
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.normal) {
                Image(systemName: icon(for: drawing))
                    .font(.title3)
                    .foregroundStyle(Color.appDoc)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drawing.name.isEmpty ? drawing.fileName : drawing.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if drawing.isCurrentVersion {
                            Text("当前版")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appSuccess.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(detailText(for: drawing, showsProject: showsProject))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if ProjectDetailDrawingHelper.isCADSource(drawing.fileType) {
                        let status = previewStatus(for: drawing)
                        if let statusText = status.text {
                            Text(statusText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(status.isReady ? Color.appSuccess : Color.appWarning)
                        }
                    }
                }
                Spacer(minLength: AppSpacing.tight)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("预览图纸 \(drawing.name.isEmpty ? drawing.fileName : drawing.name)")
    }

    private func openDrawing(_ drawing: ProjectDrawing) {
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing) {
        case .success(let url):
            recordRecentDrawing(drawing.id)
            previewRequest = ProjectCADPreviewRequest(
                projectId: drawing.projectId,
                drawingID: drawing.id,
                fileURL: url,
                displayName: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                fileType: drawing.fileType,
                importedAt: drawing.importedAt,
                fileSizeBytes: DrawingStorage.fileSize(for: drawing.fileName),
                textEncoding: drawing.textEncoding,
                textBigFont: drawing.textBigFont,
                textSchemeSnapshot: drawing.textSchemeSnapshot,
                cadViewState: drawing.cadViewState,
                projectFontMappings: store.projects.first(where: { $0.id == drawing.projectId })?.cadFontMappings ?? [],
                overlaySnapshotData: drawing.cadOverlaySnapshotData,
                onOverlaySnapshotChange: { drawingID, snapshotData in
                    updateOverlaySnapshot(drawingID: drawingID, snapshotData: snapshotData)
                },
                onViewStateChange: { drawingID, viewState in
                    updateCADViewState(drawingID: drawingID, viewState: viewState)
                },
                onTextEncodingChange: { drawingID, encoding in
                    updateTextEncoding(drawingID: drawingID, encoding: encoding)
                },
                onTextBigFontChange: { drawingID, profile in
                    updateTextBigFont(drawingID: drawingID, profile: profile)
                },
                onTextSchemeSnapshotChange: { drawingID, snapshot in
                    updateTextSchemeSnapshot(drawingID: drawingID, snapshot: snapshot)
                },
                onProjectFontMappingsChange: { projectID, mappings in
                    updateProjectFontMappings(projectID: projectID, mappings: mappings)
                }
            )
        case .failure(let message):
            StorageIssueLog.record("CAD 图纸打开失败：\(drawing.name.isEmpty ? drawing.fileName : drawing.name)，\(message)")
            operationMessage = message
        }
    }

    private func beginImportDrawings() {
        guard !store.projects.isEmpty else {
            operationMessage = "请先创建项目，再导入图纸。"
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
        let projectDrawings = store.projectDrawings.filter { $0.projectId == projectId }
        let conflicts = ProjectDetailDrawingHelper.conflictedDrawingNames(for: urls, in: projectDrawings)
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
        var importedCount = 0
        var replacedCount = 0
        var failedNames: [String] = []
        var importedDrawings: [ProjectDrawing] = []
        var currentDrawings = store.projectDrawings.filter { $0.projectId == projectId }

        func importDrawing(_ drawing: ProjectDrawing) {
            var versioned = drawing
            let resolved = ProjectDetailDrawingHelper.resolvedImportMetadata(
                for: drawing,
                in: currentDrawings,
                strategy: strategy
            )
            versioned.version = resolved.version
            versioned.isCurrentVersion = resolved.isCurrentVersion

            if let replacement = resolved.replacement {
                store.removeProjectDrawings(
                    ids: Set([replacement.id]),
                    deferredFileCleanup: DataStoreDeferredFileCleanup.drawingFiles(
                        [replacement.fileName],
                        summary: "cadViewer.importReplacement"
                    ),
                    recordsAuditImmediately: true
                )
                currentDrawings.removeAll { $0.id == replacement.id }
                replacedCount += 1
            }

            if strategy == .createNewVersion && versioned.isCurrentVersion {
                ProjectDetailAssetActions.updateCurrentVersionFlags(for: versioned, store: store)
                for index in currentDrawings.indices where currentDrawings[index].projectId == versioned.projectId {
                    if ProjectDetailDrawingHelper.normalizedDrawingNameKey(currentDrawings[index].name) ==
                        ProjectDetailDrawingHelper.normalizedDrawingNameKey(versioned.name),
                       currentDrawings[index].id != versioned.id {
                        currentDrawings[index].isCurrentVersion = false
                    }
                }
            }
            store.appendProjectDrawing(versioned)
            currentDrawings.append(versioned)
            importedDrawings.append(versioned)
            importedCount += 1
        }

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    var hasDrawingEntries = false
                    try SimpleZipArchiveReader.scan(fileURL: url) { entry, readData, _ in
                        let ext = (entry.path as NSString).pathExtension.lowercased()
                        guard ProjectDrawing.allowedFileExtensions.contains(ext) else { return }
                        hasDrawingEntries = true
                        do {
                            let entryData = try readData()
                            var drawing = try DrawingStorage.saveImportedDataOrThrow(
                                data: entryData,
                                sourceFileName: entry.path,
                                projectId: projectId
                            )
                            drawing.note = ProjectDetailDrawingHelper.packageNote(for: entry.path)
                            importDrawing(drawing)
                        } catch {
                            StorageIssueLog.record("CAD ZIP 图纸导入失败：\(entry.path)，\(error.localizedDescription)")
                            failedNames.append("\(entry.path)（\(error.localizedDescription)）")
                        }
                    }
                    if !hasDrawingEntries {
                        failedNames.append("\(url.lastPathComponent)（ZIP 内没有可导入的图纸）")
                    }
                } catch {
                    StorageIssueLog.record("CAD ZIP 读取失败：\(url.lastPathComponent)，\(error.localizedDescription)")
                    failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
                }
                continue
            }

            do {
                let drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
                importDrawing(drawing)
            } catch {
                StorageIssueLog.record("CAD 图纸导入失败：\(url.lastPathComponent)，\(error.localizedDescription)")
                failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
            }
        }

        if importedCount > 0 {
            selectedProjectID = projectId
            store.scheduleSave()
        }
        let previewHint = ""

        if importedCount > 0, failedNames.isEmpty {
            let replaceHint = replacedCount > 0 ? "，替换 \(replacedCount) 份同格式旧文件" : ""
            operationMessage = "已导入 \(importedCount) 份图纸\(previewHint)"
            if !replaceHint.isEmpty {
                operationMessage = "已导入 \(importedCount) 份图纸\(replaceHint)\(previewHint)"
            }
            openFirstImportedDrawing(importedDrawings)
            return
        }
        if importedCount > 0, !failedNames.isEmpty {
            let replaceHint = replacedCount > 0 ? "，已替换 \(replacedCount) 份同格式旧文件" : ""
            operationMessage = "已导入 \(importedCount) 份，\(failedNames.count) 份失败\(replaceHint)\(previewHint)"
            openFirstImportedDrawing(importedDrawings)
            return
        }
        operationMessage = "没有可导入的图纸文件，请选择 DWG / DXF / PDF / ZIP。"
    }

    private func openFirstImportedDrawing(_ importedDrawings: [ProjectDrawing]) {
        guard let firstDrawing = importedDrawings.first else { return }
        openDrawing(firstDrawing)
    }

    private func updateOverlaySnapshot(drawingID: UUID, snapshotData: String) {
        guard store.mutateProjectDrawing(id: drawingID, { $0.cadOverlaySnapshotData = snapshotData }) else { return }
        store.scheduleSave()
    }

    private func updateCADViewState(drawingID: UUID, viewState: CADDrawingViewState) {
        guard store.mutateProjectDrawing(id: drawingID, { $0.cadViewState = viewState }) else { return }
        store.scheduleSave()
    }

    private func updateTextEncoding(drawingID: UUID, encoding: CADDrawingTextEncoding) {
        guard store.mutateProjectDrawing(id: drawingID, { $0.textEncoding = encoding }) else { return }
        store.scheduleSave()
    }

    private func updateTextBigFont(drawingID: UUID, profile: CADDrawingTextBigFont) {
        guard store.mutateProjectDrawing(id: drawingID, { $0.textBigFont = profile }) else { return }
        store.scheduleSave()
    }

    private func updateTextSchemeSnapshot(drawingID: UUID, snapshot: CADDrawingTextSchemeSnapshot) {
        guard store.mutateProjectDrawing(id: drawingID, { $0.textSchemeSnapshot = snapshot }) else { return }
        store.scheduleSave()
    }

    private func updateProjectFontMappings(projectID: UUID, mappings: [CADProjectFontMapping]) {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        var project = store.projects[index]
        project.cadFontMappings = mappings
        guard store.updateProject(project) else { return }
        store.scheduleSave()
    }

    private func recordRecentDrawing(_ drawingID: UUID) {
        var ids = recentDrawingIDs
        ids.removeAll { $0 == drawingID }
        ids.insert(drawingID, at: 0)
        recentDrawingIDsRaw = ids.prefix(12).map(\.uuidString).joined(separator: "\n")
    }

    private func detailText(for drawing: ProjectDrawing, showsProject: Bool) -> String {
        var parts = [String]()
        if showsProject {
            parts.append(projectName(for: drawing.projectId))
        }
        parts.append(drawing.version)
        parts.append(drawing.fileType.uppercased())
        if !drawing.importedAt.isEmpty {
            parts.append("导入 \(drawing.importedAt)")
        }
        return parts.joined(separator: " · ")
    }

    private func projectName(for projectID: UUID) -> String {
        store.projects.first(where: { $0.id == projectID })?.name ?? "未知项目"
    }

    private func matchesSearch(_ drawing: ProjectDrawing) -> Bool {
        let query = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let fields = [
            drawing.name,
            drawing.fileName,
            drawing.version,
            drawing.fileType,
            drawing.note,
            projectName(for: drawing.projectId),
            ProjectDetailDrawingHelper.zipEntryPath(for: drawing) ?? "",
            ProjectDetailDrawingHelper.zipFolderPath(for: drawing) ?? ""
        ]
        return fields.contains { value in
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
        }
    }

    private func isSupportedDrawing(_ drawing: ProjectDrawing) -> Bool {
        ProjectDrawing.allowedFileExtensions.contains(drawing.fileType.lowercased())
    }

    private func icon(for drawing: ProjectDrawing) -> String {
        switch drawing.fileType.lowercased() {
        case "pdf":
            return "doc.richtext.fill"
        case "dwg", "dxf":
            return "compass.drawing"
        default:
            return "doc.viewfinder"
        }
    }

    private func previewStatus(for drawing: ProjectDrawing) -> (text: String?, isReady: Bool) {
        let fileType = drawing.fileType.lowercased()
        if fileType == "dxf" {
            return isCADKernelReady ? ("CAD 本机查看可用", true) : (nil, false)
        }
        if fileType == "pdf" {
            return ("PDF 附件", true)
        }
        if fileType == "dwg" {
            return isCADKernelReady ? ("DWG 本机查看", true) : (nil, false)
        }
        return ("文件独立打开", true)
    }
}
