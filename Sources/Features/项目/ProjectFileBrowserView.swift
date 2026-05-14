import SwiftUI
import QuickLook

struct ProjectFileBrowserView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchResultIDs: [String] = []
    @State private var searchResultByID: [String: ProjectFileSearchResult] = [:]
    @State private var indexedDataSignature = 0
    @State private var fileSearchService = ProjectFileSearchIndexService()
    @State private var isBuildingFileIndex = false
    @State private var isSearchingFiles = false
    @State private var previewURL: URL?
    @State private var selectedProjectId: UUID?
    @State private var selectedCategory: ProjectFileCategory = .images
    @State private var selectedSplitItemId: String?

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDebouncedQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fileSearchExecutionKey: FileSearchExecutionKey {
        FileSearchExecutionKey(keyword: normalizedQuery, signature: fileSearchDataSignature)
    }

    private var filteredProjects: [Project] {
        SearchMatcher.filter(
            store.projects,
            keyword: normalizedQuery,
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    private var fileSearchResults: [ProjectFileSearchResult] {
        guard !normalizedDebouncedQuery.isEmpty else { return [] }
        return searchResultIDs.compactMap { searchResultByID[$0] }
    }

    private var displayedFileSearchResults: [ProjectFileSearchResult] {
        guard normalizedQuery == normalizedDebouncedQuery else { return [] }
        return fileSearchResults
    }

    private var fileSearchDataSignature: Int {
        var hasher = Hasher()

        for project in store.projects {
            hasher.combine(project.id)
            hasher.combine(project.name)
            hasher.combine(project.location)
        }

        for log in store.dailyLogs {
            hasher.combine(log.id)
            hasher.combine(log.projectId)
            hasher.combine(log.date)
            for photo in log.photoAttachments {
                hasher.combine(photo.id)
                hasher.combine(photo.fileName)
                hasher.combine(photo.note)
                hasher.combine(photo.tag)
            }
        }

        for todo in store.siteTodos {
            hasher.combine(todo.id)
            hasher.combine(todo.projectId)
            hasher.combine(todo.title)
            hasher.combine(todo.dueDate)
            hasher.combine(todo.completedAt)
            hasher.combine(todo.rectificationBeforePhotoFileName)
            hasher.combine(todo.rectificationAfterPhotoFileName)
        }

        for drawing in store.projectDrawings {
            hasher.combine(drawing.id)
            hasher.combine(drawing.projectId)
            hasher.combine(drawing.name)
            hasher.combine(drawing.fileName)
            hasher.combine(drawing.fileType)
            hasher.combine(drawing.importedAt)
            hasher.combine(drawing.note)
        }

        for document in store.projectDocuments {
            hasher.combine(document.id)
            hasher.combine(document.projectId)
            hasher.combine(document.title)
            hasher.combine(document.fileName)
            hasher.combine(document.fileType)
            hasher.combine(document.category)
            hasher.combine(document.createdAt)
            hasher.combine(document.amount)
            hasher.combine(document.note)
            hasher.combine(document.linkedFinancialRecordId)
        }

        for note in store.quickNotes {
            hasher.combine(note.id)
            hasher.combine(note.projectId)
            hasher.combine(note.title)
            hasher.combine(note.createdAt)
            hasher.combine(note.updatedAt)
            for attachment in note.attachments {
                hasher.combine(attachment.id)
                hasher.combine(attachment.kind)
                hasher.combine(attachment.fileName)
                hasher.combine(attachment.originalName)
                hasher.combine(attachment.createdAt)
            }
        }

        return hasher.finalize()
    }

    private func collectAllFileSearchResults() -> [ProjectFileSearchResult] {
        var results: [ProjectFileSearchResult] = []

        for project in store.projects {
            for category in ProjectFileCategory.allCases {
                let items = ProjectFileCollector.items(for: project.id, category: category, store: store)
                for item in items {
                    results.append(ProjectFileSearchResult(project: project, item: item))
                }
            }
        }

        return results
    }

    private func makeIndexRows(from results: [ProjectFileSearchResult]) -> [ProjectFileSearchIndexRow] {
        results.map { result in
            let searchable = [
                result.project.name,
                result.project.location,
                result.item.title,
                result.item.subtitle,
                result.item.fileType
            ].joined(separator: " ")

            return ProjectFileSearchIndexRow(
                id: result.id,
                searchableText: searchable,
                sortDate: result.item.sortDate
            )
        }
    }

    private func refreshSearchIndexIfNeeded(completion: @escaping () -> Void) {
        let signature = fileSearchDataSignature
        if signature == indexedDataSignature, !searchResultByID.isEmpty {
            completion()
            return
        }

        let allResults = collectAllFileSearchResults()
        searchResultByID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.id, $0) })
        let rows = makeIndexRows(from: allResults)

        isBuildingFileIndex = true
        fileSearchService.rebuild(signature: signature, rows: rows) {
            indexedDataSignature = signature
            isBuildingFileIndex = false
            completion()
        }
    }

    @MainActor
    private func runFileSearchTask(for text: String) async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            debouncedSearchText = ""
            searchResultIDs = []
            isSearchingFiles = false
            return
        }

        isSearchingFiles = true
        guard await DebouncedTask.wait(for: .milliseconds(300)) else { return }
        let requestedKeyword = keyword
        await refreshSearchIndexIfNeeded()
        guard !Task.isCancelled else { return }
        let ids = await searchIndexedFileIDs(keyword: requestedKeyword)
        guard !Task.isCancelled else { return }
        guard requestedKeyword == normalizedQuery else { return }
        searchResultIDs = ids
        debouncedSearchText = requestedKeyword
        isSearchingFiles = false
    }

    private func refreshSearchIndexIfNeeded() async {
        await withCheckedContinuation { continuation in
            refreshSearchIndexIfNeeded {
                continuation.resume()
            }
        }
    }

    private func searchIndexedFileIDs(keyword: String) async -> [String] {
        await withCheckedContinuation { continuation in
            fileSearchService.search(keyword: keyword) { ids in
                continuation.resume(returning: ids)
            }
        }
    }

    private var missingResultCount: Int {
        displayedFileSearchResults.reduce(0) { result, item in
            result + (item.item.exists ? 0 : 1)
        }
    }

    private var usesThreeColumnLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return store.projects.first { $0.id == selectedProjectId }
    }

    private var splitCategoryItems: [ProjectFileItem] {
        guard let selectedProjectId else { return [] }
        return ProjectFileCollector.items(for: selectedProjectId, category: selectedCategory, store: store)
    }

    private var selectedSplitItem: ProjectFileItem? {
        guard let selectedSplitItemId else { return nil }
        return splitCategoryItems.first { $0.id == selectedSplitItemId }
    }

    var body: some View {
        Group {
            if usesThreeColumnLayout {
                splitBrowserLayout
            } else {
                compactBrowserLayout
            }
        }
        .quickLookPreview($previewURL)
        .onAppear {
            syncSplitSelectionIfNeeded()
        }
        .task(id: fileSearchExecutionKey) {
            await runFileSearchTask(for: fileSearchExecutionKey.keyword)
        }
        .onChange(of: fileSearchDataSignature) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onChange(of: filteredProjects.map(\.id)) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onChange(of: selectedCategory) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onDisappear {
            isSearchingFiles = false
        }
    }

    private var compactBrowserLayout: some View {
        List {
            if !normalizedQuery.isEmpty {
                Section("文件搜索结果") {
                    if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在搜索文件…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if displayedFileSearchResults.isEmpty {
                        Text("未找到匹配文件，请尝试不同关键词。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedFileSearchResults.prefix(30)) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                ProjectFileItemRow(item: result.item) {
                                    previewURL = result.item.url
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "building.2")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(result.project.name)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if !result.project.location.isEmpty {
                                        Text("· \(result.project.location)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        if displayedFileSearchResults.count > 30 {
                            Text("仅显示前 30 条结果，请继续输入缩小范围。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !displayedFileSearchResults.isEmpty {
                    Section("建议下一步") {
                        ProjectFileMicroGuideRow(
                            icon: "sparkle.magnifyingglass",
                            color: .appDoc,
                            title: "已命中文件，可直接预览",
                            detail: "点条目可查看，点右侧菜单可分享或打开。"
                        )

                        if missingResultCount > 0 {
                            ProjectFileMicroGuideRow(
                                icon: "exclamationmark.triangle.fill",
                                color: .appRisk,
                                title: String(localized: "发现 \(missingResultCount) 个缺失文件"),
                                detail: "建议回到项目详情重新导入图纸或资料，避免交付时缺件。"
                            )
                            NavigationLink {
                                ProjectListView(initialOverviewFilter: .active)
                            } label: {
                                Label("去项目列表排查", systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if filteredProjects.isEmpty {
                if normalizedQuery.isEmpty {
                    Section("建议下一步") {
                        ContentUnavailableView(
                            "暂无全局文件",
                            systemImage: "folder",
                            description: Text("先新建项目并补充日志、图纸或票据，这里会自动聚合显示。")
                        )
                        NavigationLink {
                            ProjectListView(autoOpenComposerToken: 1)
                        } label: {
                            Label("去新建项目", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.appProminent())
                    }
                } else {
                    Section("建议下一步") {
                        ContentUnavailableView(
                            "未找到匹配项目",
                            systemImage: "magnifyingglass",
                            description: Text(displayedFileSearchResults.isEmpty ? "请尝试其他关键词。" : "未匹配到项目名，可直接使用上方文件结果。")
                        )
                        Button {
                            searchText = ""
                        } label: {
                            Label("清除关键词", systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
            } else {
                Section("项目") {
                    ForEach(filteredProjects) { project in
                        let summary = ProjectFileSummary(projectId: project.id, store: store)
                        NavigationLink {
                            ProjectFileCategoryView(project: project)
                        } label: {
                            ProjectFileProjectRow(project: project, summary: summary, isSelected: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("全局文件检索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索全部项目或文件")
    }

    private var splitBrowserLayout: some View {
        NavigationSplitView {
            List {
                if !normalizedQuery.isEmpty {
                    Section("文件搜索结果") {
                        if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在搜索文件…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if displayedFileSearchResults.isEmpty {
                            Text("未找到匹配文件，请尝试不同关键词。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(displayedFileSearchResults.prefix(30)) { result in
                                Button {
                                    selectedProjectId = result.project.id
                                    selectedCategory = result.item.category
                                    selectedSplitItemId = result.item.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(result.item.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(2)
                                        Text(result.project.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(result.item.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("全部项目") {
                    if filteredProjects.isEmpty {
                        Text(normalizedQuery.isEmpty ? "暂无项目" : "未找到匹配项目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredProjects) { project in
                            let summary = ProjectFileSummary(projectId: project.id, store: store)
                            let isSelected = selectedProjectId == project.id
                            Button {
                                selectedProjectId = project.id
                                syncSplitSelectionIfNeeded()
                            } label: {
                                ProjectFileProjectRow(project: project, summary: summary, isSelected: isSelected)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("全局文件检索")
            .searchable(text: $searchText, prompt: "搜索全部项目或文件")
        } content: {
            List {
                if let selectedProject {
                    Section {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Text(selectedProject.name)
                                .font(.headline)
                            if !selectedProject.location.isEmpty {
                                Text(selectedProject.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("文件分类") {
                        ForEach(ProjectFileCategory.allCases, id: \.self) { category in
                            let count = ProjectFileSummary(projectId: selectedProject.id, store: store).count(for: category)
                            Button {
                                selectedCategory = category
                                syncSplitSelectionIfNeeded()
                            } label: {
                                HStack(spacing: AppSpacing.normal) {
                                    Image(systemName: category.systemImage)
                                        .foregroundStyle(category.tint)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.title)
                                        Text(category.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(count > 0 ? category.tint : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(selectedCategory == category ? category.tint.opacity(0.12) : Color.clear)
                        }
                    }

                    Section(selectedCategory.title) {
                        if splitCategoryItems.isEmpty {
                            Text("当前分类暂无文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(splitCategoryItems) { item in
                                Button {
                                    selectedSplitItemId = item.id
                                } label: {
                                    ProjectFileSplitItemRow(item: item, isSelected: selectedSplitItemId == item.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "请选择项目",
                        systemImage: "building.2.crop.circle",
                        description: Text("左侧是全局项目列表；选择后查看该项目文件。")
                    )
                }
            }
            .navigationTitle(selectedProject?.name ?? "文件分类")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            Group {
                if let item = selectedSplitItem {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.normal) {
                            HStack(spacing: AppSpacing.normal) {
                                Image(systemName: item.systemImage)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(item.category.tint)
                                    .frame(width: 36, height: 36)
                                    .background(item.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent("类型", value: item.fileType.uppercased())
                                LabeledContent("大小", value: item.formattedSize)
                                LabeledContent("状态", value: item.exists ? "可用" : "文件缺失")
                            }
                            .font(.subheadline)

                            if item.exists {
                                Button {
                                    previewURL = item.url
                                } label: {
                                    Label("预览文件", systemImage: "eye")
                                }
                                .buttonStyle(.appProminent())
                                ShareLink(item: item.url) {
                                    Label("分享/打开", systemImage: "square.and.arrow.up")
                                }
                            } else {
                                Text("该文件在本地已缺失，请回到项目详情重新导入。")
                                    .font(.caption)
                                    .foregroundStyle(.appRisk)
                            }
                        }
                        .padding(AppSpacing.relaxed)
                    }
                } else {
                    ContentUnavailableView(
                        "请选择文件",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("在中栏点击文件后，右侧显示详情并支持 QuickLook 预览。")
                    )
                }
            }
            .navigationTitle("文件预览")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func syncSplitSelectionIfNeeded() {
        guard usesThreeColumnLayout else { return }

        if let selectedProjectId,
           !filteredProjects.contains(where: { $0.id == selectedProjectId }) {
            self.selectedProjectId = nil
        }
        if selectedProjectId == nil {
            selectedProjectId = filteredProjects.first?.id
        }

        let itemIds = Set(splitCategoryItems.map(\.id))
        if let selectedSplitItemId, !itemIds.contains(selectedSplitItemId) {
            self.selectedSplitItemId = nil
        }
        if selectedSplitItemId == nil {
            selectedSplitItemId = splitCategoryItems.first?.id
        }
    }
}

private struct FileSearchExecutionKey: Equatable {
    let keyword: String
    let signature: Int
}

private struct ProjectFileProjectRow: View {
    let project: Project
    let summary: ProjectFileSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color.appPrimaryAction : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(summary.totalCount) 个文件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.totalCount > 0 ? Color.appPrimaryAction : .secondary)
                }
                HStack(spacing: AppSpacing.tight) {
                    ProjectFileCountChip(title: "图片", value: summary.imageCount, color: .appDoc)
                    ProjectFileCountChip(title: "CAD", value: summary.drawingCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: "资料", value: summary.documentCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: "附件", value: summary.quickNoteAttachmentCount, color: .appPrimaryAction)
                }
                if !project.location.isEmpty {
                    Text(project.location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.appPrimarySurface : Color.clear)
        )
    }
}

private struct ProjectFileSplitItemRow: View {
    let item: ProjectFileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.normal) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.exists ? item.category.tint : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: AppSpacing.tight) {
                    Text(item.fileType.uppercased())
                    Text(item.formattedSize)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.exists ? Color.secondary : Color.appRisk)
            }
            Spacer(minLength: 6)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.appPrimarySurfaceSubtle : Color.clear))
    }
}

private struct ProjectFileSearchResult: Identifiable {
    let project: Project
    let item: ProjectFileItem

    var id: String {
        "\(project.id.uuidString)-\(item.id)"
    }
}
