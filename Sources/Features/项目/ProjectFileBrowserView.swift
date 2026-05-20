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
    @State private var healthFilter: ProjectFileHealthFilter = .all
    @State private var selectedSplitItemId: String?
    @State private var deliveryInspectionExportPayload: ExportPayload?
    @State private var showDeliveryInspectionExporter = false
    @State private var operationNotice: OperationToastNotice?

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDebouncedQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fileSearchExecutionKey: FileSearchExecutionKey {
        FileSearchExecutionKey(keyword: normalizedQuery, signature: fileSearchDataSignature)
    }

    private var searchMatchedProjects: [Project] {
        SearchMatcher.filter(
            store.projects,
            keyword: normalizedQuery,
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    private var filteredProjects: [Project] {
        let result = searchMatchedProjects
        guard healthFilter != .all else { return result }
        return result.filter { projectMatchesHealthFilter($0) }
    }

    private var visibleDeliveryInspections: [ProjectDocumentDeliveryInspection] {
        searchMatchedProjects
            .map { ProjectDocumentDeliveryInspection(project: $0, store: store) }
            .sorted { left, right in
                if left.isReadyForDelivery != right.isReadyForDelivery {
                    return !left.isReadyForDelivery
                }
                if left.issueDetailCount != right.issueDetailCount {
                    return left.issueDetailCount > right.issueDetailCount
                }
                return left.project.name.localizedStandardCompare(right.project.name) == .orderedAscending
            }
    }

    private var fileSearchResults: [ProjectFileSearchResult] {
        guard !normalizedDebouncedQuery.isEmpty else { return [] }
        return searchResultIDs.compactMap { searchResultByID[$0] }
    }

    private var displayedFileSearchResults: [ProjectFileSearchResult] {
        guard normalizedQuery == normalizedDebouncedQuery else { return [] }
        return fileSearchResults.filter { healthFilter.matches($0.item) }
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
            hasher.combine(document.submissionStatus.rawValue)
            hasher.combine(document.responsiblePerson)
            hasher.combine(document.formedAt)
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
            .filter { healthFilter.matches($0) }
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
        .fileExporter(
            isPresented: $showDeliveryInspectionExporter,
            document: ExportDocument(data: deliveryInspectionExportPayload?.data ?? Data()),
            contentType: deliveryInspectionExportPayload?.contentType ?? .pdf,
            defaultFilename: deliveryInspectionExportPayload?.defaultFilename ?? String(localized: "交付体检清单.pdf")
        ) { result in
            switch result {
            case .success:
                AppHaptics.success()
                operationNotice = .info(String(localized: "已导出体检清单"))
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    AppHaptics.error()
                    operationNotice = .info(String(format: String(localized: "导出失败：%@"), error.localizedDescription))
                }
            }
            deliveryInspectionExportPayload = nil
        }
        .operationToast(notice: $operationNotice)
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
        .onChange(of: healthFilter) { _, _ in
            syncSplitSelectionIfNeeded()
        }
        .onDisappear {
            isSearchingFiles = false
        }
    }

    @ViewBuilder
    private func deliveryInspectionSection(isSplitNavigation: Bool) -> some View {
        let inspections = visibleDeliveryInspections
        let issueInspections = inspections.filter { !$0.isReadyForDelivery }
        let issueCount = issueInspections.reduce(0) { $0 + $1.issueDetailCount }

        if !inspections.isEmpty {
            Section(String(localized: "交付体检")) {
                if issueInspections.isEmpty {
                    ProjectFileMicroGuideRow(
                        icon: "checkmark.seal.fill",
                        color: .appSuccess,
                        title: String(localized: "一键体检通过"),
                        detail: String(localized: "资料类别、原件、归档状态、责任人和形成日期暂未发现交付风险。")
                    )
                } else {
                    ProjectFileMicroGuideRow(
                        icon: "checklist.unchecked",
                        color: .appWarning,
                        title: String(
                            format: String(localized: "%lld 个项目需处理"),
                            Int64(issueInspections.count)
                        ),
                        detail: String(
                            format: String(localized: "共 %lld 条交付前检查项，优先处理缺件、退回和未归档资料。"),
                            Int64(issueCount)
                        )
                    )

                    ForEach(issueInspections.prefix(4)) { inspection in
                        if isSplitNavigation {
                            ProjectFileDeliveryInspectionRow(inspection: inspection) { issue in
                                Button {
                                    selectDeliveryInspection(inspection, issue: issue)
                                } label: {
                                    ProjectFileDeliveryIssueLine(issue: issue, showsAction: true)
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            ProjectFileDeliveryInspectionRow(inspection: inspection) { issue in
                                NavigationLink {
                                    deliveryDestination(for: inspection, issue: issue)
                                } label: {
                                    ProjectFileDeliveryIssueLine(issue: issue, showsAction: true)
                                }
                            }
                        }
                    }

                    if issueInspections.count > 4 {
                        Text(
                            String(
                                format: String(localized: "还有 %lld 个项目待体检处理，可用搜索缩小范围。"),
                                Int64(issueInspections.count - 4)
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                deliveryInspectionExportMenu(inspections)
            }
        }
    }

    private func deliveryInspectionExportMenu(_ inspections: [ProjectDocumentDeliveryInspection]) -> some View {
        Menu {
            Button {
                exportDeliveryInspections(inspections, format: .pdf)
            } label: {
                Label(String(localized: "导出 PDF"), systemImage: "doc.richtext")
            }
            Button {
                exportDeliveryInspections(inspections, format: .csv)
            } label: {
                Label(String(localized: "导出 CSV"), systemImage: "tablecells")
            }
        } label: {
            Label(String(localized: "导出体检清单"), systemImage: "square.and.arrow.up")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
    }

    private func exportDeliveryInspections(
        _ inspections: [ProjectDocumentDeliveryInspection],
        format: ProjectDocumentDeliveryInspectionExportFormat
    ) {
        guard !inspections.isEmpty else { return }
        deliveryInspectionExportPayload = ProjectDocumentDeliveryInspectionExport.makePayload(
            for: inspections,
            format: format
        )
        showDeliveryInspectionExporter = true
    }

    @ViewBuilder
    private func deliveryDestination(
        for inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) -> some View {
        if let category = issue.kind.preferredCategory {
            ProjectFileListView(
                project: inspection.project,
                category: category,
                initialHealthFilter: issue.kind.preferredHealthFilter
            )
        } else {
            ProjectFileCategoryView(
                project: inspection.project,
                initialHealthFilter: issue.kind.preferredHealthFilter
            )
        }
    }

    private func selectDeliveryInspection(
        _ inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) {
        selectedProjectId = inspection.project.id
        selectedCategory = issue.kind.preferredCategory ?? deliveryFallbackCategory(for: inspection, issue: issue)
        healthFilter = issue.kind.preferredHealthFilter
        selectedSplitItemId = nil
        syncSplitSelectionIfNeeded()
    }

    private func deliveryFallbackCategory(
        for inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) -> ProjectFileCategory {
        guard issue.kind == .missingFiles else { return .documents }
        return ProjectFileCategory.allCases.first { category in
            ProjectFileCollector.items(for: inspection.project.id, category: category, store: store)
                .contains { !$0.exists }
        } ?? .documents
    }

    private var compactBrowserLayout: some View {
        List {
            deliveryInspectionSection(isSplitNavigation: false)

            ProjectFileHealthFilterSection(selection: $healthFilter)

            if !normalizedQuery.isEmpty {
                Section(String(localized: "文件搜索结果")) {
                    if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(String(localized: "正在搜索文件…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if displayedFileSearchResults.isEmpty {
                        Text(String(localized: "未找到匹配文件，请尝试不同关键词。"))
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
                            Text(String(localized: "仅显示前 30 条结果，请继续输入缩小范围。"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !displayedFileSearchResults.isEmpty {
                    Section(String(localized: "建议下一步")) {
                        ProjectFileMicroGuideRow(
                            icon: "sparkle.magnifyingglass",
                            color: .appDoc,
                            title: String(localized: "已命中文件，可直接预览"),
                            detail: String(localized: "点条目可查看，点右侧菜单可分享或打开。")
                        )

                        if missingResultCount > 0 {
                            ProjectFileMicroGuideRow(
                                icon: "exclamationmark.triangle.fill",
                                color: .appRisk,
                                title: String(
                                    format: String(localized: "发现 %lld 个缺失文件"),
                                    Int64(missingResultCount)
                                ),
                                detail: String(localized: "建议回到项目详情重新导入图纸或资料，避免交付时缺件。")
                            )
                            NavigationLink {
                                ProjectListView(initialOverviewFilter: .active)
                            } label: {
                                Label(String(localized: "去项目列表排查"), systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if filteredProjects.isEmpty {
                if normalizedQuery.isEmpty {
                    Section(String(localized: "建议下一步")) {
                        ContentUnavailableView(
                            String(localized: "暂无项目资料"),
                            systemImage: "folder",
                            description: Text(String(localized: "先新建项目并补充日志、图纸、票据或随手记附件，这里会自动聚合显示。"))
                        )
                        NavigationLink {
                            ProjectListView(autoOpenComposerToken: 1)
                        } label: {
                            Label(String(localized: "去新建项目"), systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.appProminent())
                    }
                } else {
                    Section(String(localized: "建议下一步")) {
                        ContentUnavailableView(
                            String(localized: "未找到匹配项目"),
                            systemImage: "magnifyingglass",
                            description: Text(
                                displayedFileSearchResults.isEmpty
                                    ? String(localized: "请尝试其他关键词。")
                                    : String(localized: "未匹配到项目名，可直接使用上方文件结果。")
                            )
                        )
                        Button {
                            searchText = ""
                        } label: {
                            Label(String(localized: "清除关键词"), systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
            } else {
                Section(String(localized: "项目")) {
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
        .navigationTitle(String(localized: "项目资料"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "搜索项目或资料文件"))
    }

    private var splitBrowserLayout: some View {
        NavigationSplitView {
            List {
                deliveryInspectionSection(isSplitNavigation: true)

                ProjectFileHealthFilterSection(selection: $healthFilter)

                if !normalizedQuery.isEmpty {
                    Section(String(localized: "文件搜索结果")) {
                        if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(String(localized: "正在搜索文件…"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if displayedFileSearchResults.isEmpty {
                            Text(String(localized: "未找到匹配文件，请尝试不同关键词。"))
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

                Section(String(localized: "全部项目")) {
                    if filteredProjects.isEmpty {
                        Text(normalizedQuery.isEmpty ? String(localized: "暂无项目") : String(localized: "未找到匹配项目"))
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
            .navigationTitle(String(localized: "项目资料"))
            .searchable(text: $searchText, prompt: String(localized: "搜索项目或资料文件"))
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

                    Section(String(localized: "文件分类")) {
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
                            Text(String(localized: "当前分类暂无文件"))
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
                        String(localized: "请选择项目"),
                        systemImage: "building.2.crop.circle",
                        description: Text(String(localized: "左侧是项目列表；选择后查看该项目资料。"))
                    )
                }
            }
            .navigationTitle(selectedProject?.name ?? String(localized: "文件分类"))
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
                                LabeledContent(String(localized: "类型"), value: item.fileType.uppercased())
                                LabeledContent(String(localized: "大小"), value: item.formattedSize)
                                LabeledContent(String(localized: "状态"), value: item.exists ? String(localized: "可用") : String(localized: "文件缺失"))
                                if let documentStatus = item.documentStatus {
                                    LabeledContent(String(localized: "报验状态"), value: documentStatus.displayName)
                                }
                                if item.isLargeFile {
                                    LabeledContent(String(localized: "体积提示"), value: String(localized: "大文件"))
                                }
                            }
                            .font(.subheadline)

                            if item.exists {
                                Button {
                                    previewURL = item.url
                                } label: {
                                    Label(String(localized: "预览文件"), systemImage: "eye")
                                }
                                .buttonStyle(.appProminent())
                                ShareLink(item: item.url) {
                                    Label(
                                        item.category == .drawings
                                            ? String(localized: "用外部专业看图软件打开")
                                            : String(localized: "分享/打开"),
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                            } else {
                                Text(String(localized: "该文件在本地已缺失，请回到项目详情重新导入。"))
                                    .font(.caption)
                                    .foregroundStyle(.appRisk)
                            }
                        }
                        .padding(AppSpacing.relaxed)
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "请选择文件"),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(String(localized: "在中栏点击文件后，右侧显示详情并支持 QuickLook 预览。"))
                    )
                }
            }
            .navigationTitle(String(localized: "文件预览"))
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

    private func projectMatchesHealthFilter(_ project: Project) -> Bool {
        ProjectFileCollector.allItems(for: project.id, store: store).contains {
            healthFilter.matches($0)
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
                    Text(String(format: String(localized: "%lld 个文件"), Int64(summary.totalCount)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.totalCount > 0 ? Color.appPrimaryAction : .secondary)
                }
                HStack(spacing: AppSpacing.tight) {
                    ProjectFileCountChip(title: String(localized: "图片"), value: summary.imageCount, color: .appDoc)
                    ProjectFileCountChip(title: "图纸", value: summary.drawingCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: String(localized: "资料"), value: summary.documentCount, color: .appPrimaryAction)
                    ProjectFileCountChip(title: String(localized: "附件"), value: summary.quickNoteAttachmentCount, color: .appPrimaryAction)
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

private struct ProjectFileDeliveryInspectionRow<IssueContent: View>: View {
    let inspection: ProjectDocumentDeliveryInspection
    let issueContent: (ProjectDocumentDeliveryInspectionIssue) -> IssueContent

    init(
        inspection: ProjectDocumentDeliveryInspection,
        @ViewBuilder issueContent: @escaping (ProjectDocumentDeliveryInspectionIssue) -> IssueContent
    ) {
        self.inspection = inspection
        self.issueContent = issueContent
    }

    private var visibleIssues: ArraySlice<ProjectDocumentDeliveryInspectionIssue> {
        inspection.issues.prefix(3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appWarning)
                    .frame(width: 18)
                Text(inspection.project.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(
                    String(
                        format: String(localized: "%lld 条"),
                        Int64(inspection.issueDetailCount)
                    )
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appRisk)
            }

            ForEach(visibleIssues) { issue in
                issueContent(issue)
            }

            if inspection.issues.count > visibleIssues.count {
                Text(
                    String(
                        format: String(localized: "另有 %lld 类问题"),
                        Int64(inspection.issues.count - visibleIssues.count)
                    )
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppSpacing.tight)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appWarning.opacity(0.08))
        )
    }
}

private struct ProjectFileDeliveryIssueLine: View {
    let issue: ProjectDocumentDeliveryInspectionIssue
    var showsAction = false

    private var sampleText: String {
        let text = issue.samples.prefix(3).joined(separator: "、")
        if issue.samples.count > 3 {
            return String(
                format: String(localized: "%@ 等"),
                text
            )
        }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: issue.kind.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(issue.kind.tint)
                .frame(width: 14, height: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(
                        String(
                            format: String(localized: "%@ %lld"),
                            issue.kind.title,
                            Int64(issue.count)
                        )
                    )
                    .font(.caption.weight(.semibold))

                    if showsAction {
                        Text(issue.kind.actionTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(issue.kind.tint)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(issue.kind.tint)
                    }
                }

                if !sampleText.isEmpty {
                    Text(sampleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
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
                    if let status = item.documentStatus {
                        Text(status.displayName)
                            .foregroundStyle(status.requiresArchiveAttention ? Color.appWarning : Color.secondary)
                    }
                    if item.hasDocumentLedgerIssues {
                        Text(String(localized: "台账缺项"))
                            .foregroundStyle(.appWarning)
                    }
                    if item.isLargeFile {
                        Text(String(localized: "大文件"))
                            .foregroundStyle(.appRisk)
                    }
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
