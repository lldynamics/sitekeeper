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
    @AppStorage(UserPreferenceKeys.cadViewerRecentDrawingIDs) private var recentDrawingIDsRaw = ""

    private struct DrawingProjectGroup: Identifiable {
        let id: UUID
        let title: String
        let drawings: [ProjectDrawing]
    }

    private struct DrawingFolderGroup: Identifiable {
        let id: String
        let drawings: [ProjectDrawing]
    }

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
        guard let selectedProjectID else { return sortedDrawings }
        return sortedDrawings.filter { $0.projectId == selectedProjectID }
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

    private var recentProjectGroups: [DrawingProjectGroup] {
        var groups: [DrawingProjectGroup] = []
        for drawing in recentDrawings {
            if let index = groups.firstIndex(where: { $0.id == drawing.projectId }) {
                var updated = groups[index]
                updated = DrawingProjectGroup(
                    id: updated.id,
                    title: updated.title,
                    drawings: updated.drawings + [drawing]
                )
                groups[index] = updated
            } else {
                groups.append(
                    DrawingProjectGroup(
                        id: drawing.projectId,
                        title: projectName(for: drawing.projectId),
                        drawings: [drawing]
                    )
                )
            }
        }
        return groups
    }

    private var zipFolderGroups: [DrawingFolderGroup] {
        let grouped = Dictionary(grouping: filteredDrawings) { drawing in
            ProjectDetailDrawingHelper.zipFolderPath(for: drawing) ?? ""
        }
        return grouped
            .filter { !$0.key.isEmpty }
            .map { DrawingFolderGroup(id: $0.key, drawings: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private var selectedEngine: CADPreviewEngine {
        CADPreviewEngineStore.selected
    }

    private var resolvedEngine: CADPreviewEngine {
        CADPreviewCapability.resolvedEngine(selectedEngine)
    }

    private var isLibreDWGUnavailable: Bool {
        selectedEngine == .libreDWG && !CADPreviewCapability.isLibreDWGRendererAvailable()
    }

    private var isLibreDWGUnbound: Bool {
        selectedEngine == .libreDWG &&
        CADPreviewCapability.isLibreDWGRendererAvailable() &&
        !CADRendererProvider.isLibreDWGRendererBound
    }

    private var engineStatusText: String {
        if isLibreDWGUnavailable {
            return "LibreDWG 未接入"
        }
        if isLibreDWGUnbound {
            return "LibreDWG 未绑定"
        }
        return resolvedEngine.title
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
            Section("预览引擎") {
                HStack {
                    Label(engineStatusText, systemImage: (isLibreDWGUnavailable || isLibreDWGUnbound) ? "exclamationmark.triangle.fill" : "viewfinder")
                        .foregroundStyle((isLibreDWGUnavailable || isLibreDWGUnbound) ? Color.appWarning : Color.appDoc)
                    Spacer()
                    if selectedEngine != resolvedEngine {
                        Text("已回退")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if isLibreDWGUnavailable {
                    Text("当前构建未包含 LibreDWGBridge。可在“我的 → 更多设置 → CAD 预览”切换为系统预览。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLibreDWGUnbound {
                    Text("已检测到 LibreDWG 环境，但尚未注册渲染入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("项目筛选") {
                Picker("查看范围", selection: $selectedProjectID) {
                    Text("全部项目").tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }

            Section("最近浏览") {
                if recentDrawings.isEmpty {
                    ContentUnavailableView(
                        "暂无最近浏览",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("打开 CAD 图纸后会自动记录在这里。")
                    )
                } else {
                    ForEach(recentProjectGroups) { group in
                        DisclosureGroup {
                            ForEach(group.drawings) { drawing in
                                drawingRow(drawing, showsProject: false)
                            }
                        } label: {
                            Label("\(group.title) · \(group.drawings.count) 张", systemImage: "folder")
                        }
                    }
                }
            }

            if !zipFolderGroups.isEmpty {
                Section("图纸包目录") {
                    ForEach(zipFolderGroups) { group in
                        DisclosureGroup {
                            ForEach(group.drawings) { drawing in
                                drawingRow(drawing, showsProject: selectedProjectID == nil)
                            }
                        } label: {
                            Label("\(group.id) · \(group.drawings.count) 张", systemImage: "folder.badge.gearshape")
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section(selectedProjectID == nil ? "全部 CAD 图纸" : "项目 CAD 图纸") {
                if filteredDrawings.isEmpty {
                    ContentUnavailableView(
                        "暂无 CAD 图纸",
                        systemImage: "doc.viewfinder",
                        description: Text("先在项目详情里导入 PDF / DWG / DXF 图纸。")
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
            ProjectCADPreviewView(request: request)
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
                        Text(status.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(status.isReady ? Color.appSuccess : Color.appWarning)
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
        let previewTarget = ProjectDetailDrawingHelper.matchingRenderablePreview(
            for: drawing,
            in: store.projectDrawings
        ) ?? drawing
        switch ProjectDetailAssetActions.previewDrawingURL(for: previewTarget) {
        case .success(let url):
            recordRecentDrawing(drawing.id)
            previewRequest = ProjectCADPreviewRequest(
                projectId: previewTarget.projectId,
                drawingID: previewTarget.id,
                fileURL: url,
                displayName: previewTarget.name.isEmpty ? previewTarget.fileName : previewTarget.name,
                fileType: previewTarget.fileType,
                textEncoding: previewTarget.textEncoding,
                textBigFont: previewTarget.textBigFont,
                overlaySnapshotData: previewTarget.cadOverlaySnapshotData,
                onOverlaySnapshotChange: { drawingID, snapshotData in
                    updateOverlaySnapshot(drawingID: drawingID, snapshotData: snapshotData)
                },
                onTextEncodingChange: { drawingID, encoding in
                    updateTextEncoding(drawingID: drawingID, encoding: encoding)
                },
                onTextBigFontChange: { drawingID, profile in
                    updateTextBigFont(drawingID: drawingID, profile: profile)
                }
            )
            if previewTarget.id != drawing.id {
                operationMessage = "已使用同名 \(previewTarget.fileType.uppercased()) 预览图纸。"
            }
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
                DrawingStorage.delete(fileName: replacement.fileName)
                store.projectDrawings.removeAll { $0.id == replacement.id }
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
            store.projectDrawings.append(versioned)
            currentDrawings.append(versioned)
            relinkDrawingFamily(forName: versioned.name, projectId: projectId, drawings: &currentDrawings)
            importedDrawings.append(versioned)
            importedCount += 1
        }

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    let archiveData = try Data(contentsOf: url, options: [.mappedIfSafe])
                    let entries = try SimpleZipArchiveReader.read(archiveData)
                    let drawingEntries = entries.filter { entry in
                        let ext = (entry.path as NSString).pathExtension.lowercased()
                        return ProjectDrawing.allowedFileExtensions.contains(ext)
                    }
                    if drawingEntries.isEmpty {
                        failedNames.append("\(url.lastPathComponent)（ZIP 内没有可导入的图纸）")
                        continue
                    }
                    for entry in drawingEntries {
                        do {
                            var drawing = try DrawingStorage.saveImportedDataOrThrow(
                                data: entry.data,
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
            store.scheduleSave()
        }
        let allProjectDrawings = store.projectDrawings.filter { $0.projectId == projectId }
        let missingPreviewNames = importedDrawings
            .filter { $0.fileType.lowercased() == "dwg" }
            .filter { ProjectDetailDrawingHelper.matchingRenderablePreview(for: $0, in: allProjectDrawings) == nil }
            .map(\.name)
        let previewHint = missingPreviewNames.isEmpty
            ? ""
            : "；\(missingPreviewNames.prefix(3).joined(separator: "、")) 需绑定 PDF / DXF 预览"

        if importedCount > 0, failedNames.isEmpty {
            let replaceHint = replacedCount > 0 ? "，替换 \(replacedCount) 份同格式旧文件" : ""
            operationMessage = "已导入 \(importedCount) 份图纸\(previewHint)"
            if !replaceHint.isEmpty {
                operationMessage = "已导入 \(importedCount) 份图纸\(replaceHint)\(previewHint)"
            }
            return
        }
        if importedCount > 0, !failedNames.isEmpty {
            let replaceHint = replacedCount > 0 ? "，已替换 \(replacedCount) 份同格式旧文件" : ""
            operationMessage = "已导入 \(importedCount) 份，\(failedNames.count) 份失败\(replaceHint)\(previewHint)"
            return
        }
        operationMessage = "没有可导入的图纸文件，请选择 PDF / DWG / DXF / ZIP。"
    }

    private func relinkDrawingFamily(forName drawingName: String, projectId: UUID, drawings: inout [ProjectDrawing]) {
        let nameKey = ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawingName)
        guard !nameKey.isEmpty else { return }
        for index in drawings.indices {
            guard drawings[index].projectId == projectId else { continue }
            guard ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawings[index].name) == nameKey else { continue }
            guard ProjectDetailDrawingHelper.isCADSource(drawings[index].fileType) else { continue }
            let linkedID = ProjectDetailDrawingHelper.matchingRenderablePreview(for: drawings[index], in: drawings)?.id
            if drawings[index].linkedPreviewDrawingID != linkedID {
                drawings[index].linkedPreviewDrawingID = linkedID
                if let storeIndex = store.projectDrawings.firstIndex(where: { $0.id == drawings[index].id }) {
                    store.projectDrawings[storeIndex].linkedPreviewDrawingID = linkedID
                }
            }
        }
    }

    private func updateOverlaySnapshot(drawingID: UUID, snapshotData: String) {
        guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
        store.projectDrawings[index].cadOverlaySnapshotData = snapshotData
        store.scheduleSave()
    }

    private func updateTextEncoding(drawingID: UUID, encoding: CADDrawingTextEncoding) {
        guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
        store.projectDrawings[index].textEncoding = encoding
        store.scheduleSave()
    }

    private func updateTextBigFont(drawingID: UUID, profile: CADDrawingTextBigFont) {
        guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
        store.projectDrawings[index].textBigFont = profile
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
        if let folder = ProjectDetailDrawingHelper.zipFolderPath(for: drawing) {
            parts.append("ZIP \(folder)")
        }
        return parts.joined(separator: " · ")
    }

    private func projectName(for projectID: UUID) -> String {
        store.projects.first(where: { $0.id == projectID })?.name ?? "未知项目"
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

    private func previewStatus(for drawing: ProjectDrawing) -> (text: String, isReady: Bool) {
        let fileType = drawing.fileType.lowercased()
        if let proxy = ProjectDetailDrawingHelper.matchingRenderablePreview(for: drawing, in: store.projectDrawings) {
            return ("预览: 已绑定 \(proxy.fileType.uppercased())", true)
        }
        if fileType == "dxf" {
            return ("预览: 应用内可直览", true)
        }
        return ("预览: 需绑定 PDF / DXF", false)
    }
}
