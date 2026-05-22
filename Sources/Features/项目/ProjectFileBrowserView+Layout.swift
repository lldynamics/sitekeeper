import SwiftUI

extension ProjectFileBrowserView {
    var filteredProjects: [Project] {
        let result = searchMatchedProjects
        guard healthFilter != .all else { return result }
        return result.filter { projectMatchesHealthFilter($0) }
    }

    var visibleDeliveryInspections: [ProjectDocumentDeliveryInspection] {
        searchMatchedProjects
            .map { ProjectDocumentDeliveryInspection(project: $0, projectStore: projectStore) }
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

    var usesThreeColumnLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return projectStore.projects.first { $0.id == selectedProjectId }
    }

    var splitCategoryItems: [ProjectFileItem] {
        guard let selectedProjectId else { return [] }
        return ProjectFileCollector.items(for: selectedProjectId, category: selectedCategory, projectStore: projectStore)
            .filter { healthFilter.matches($0) }
    }

    var selectedSplitItem: ProjectFileItem? {
        guard let selectedSplitItemId else { return nil }
        return splitCategoryItems.first { $0.id == selectedSplitItemId }
    }

    @ViewBuilder
    func deliveryInspectionSection(isSplitNavigation: Bool) -> some View {
        let inspections = visibleDeliveryInspections
        ProjectFileDeliveryInspectionSection(
            inspections: inspections,
            isSplitNavigation: isSplitNavigation,
            onSelectIssue: { inspection, issue in
                selectDeliveryInspection(inspection, issue: issue)
            },
            onExport: { format in
                exportDeliveryInspections(inspections, format: format)
            },
            destination: { inspection, issue in
                deliveryDestination(for: inspection, issue: issue)
            }
        )
    }

    var compactBrowserLayout: some View {
        List {
            searchPanelSection
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
                        let summary = ProjectFileSummary(projectId: project.id, projectStore: projectStore)
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
    }

    var splitBrowserLayout: some View {
        NavigationSplitView {
            List {
                searchPanelSection
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
                                            .appListSecondaryTextLayout(lines: 1)
                                        Text(result.item.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .appListSecondaryTextLayout()
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
                            let summary = ProjectFileSummary(projectId: project.id, projectStore: projectStore)
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
                            let count = ProjectFileSummary(projectId: selectedProject.id, projectStore: projectStore).count(for: category)
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
                                            .appListSecondaryTextLayout()
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
            ProjectFileBrowserDetailPanel(item: selectedSplitItem) { url in
                previewURL = url
            }
            .navigationTitle(String(localized: "文件预览"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
    }

    var searchPanelSection: some View {
        Section(String(localized: "快速查找")) {
            InlineSearchPanel(
                text: $searchText,
                prompt: String(localized: "搜索项目或资料文件"),
                suggestions: fileBrowserSearchSuggestions,
                emptyStateText: String(localized: "未找到匹配项目或资料文件")
            ) { suggestion in
                if suggestion.id.hasPrefix("file-"),
                   let result = displayedFileSearchResults.first(where: { "file-\($0.id)" == suggestion.id }) {
                    selectedProjectId = result.project.id
                    selectedCategory = result.item.category
                    selectedSplitItemId = result.item.id
                    previewURL = result.item.exists && !ProjectDetailDrawingHelper.requiresExternalViewer(result.item.fileType)
                        ? result.item.url
                        : nil
                    syncSplitSelectionIfNeeded()
                    return
                }

                selectedProjectId = suggestion.entityId
                selectedSplitItemId = nil
                syncSplitSelectionIfNeeded()
            }
        }
    }
}
