import SwiftUI

extension ProjectFileBrowserView {
    var filteredProjects: [Project] {
        let result = searchMatchedProjects
        guard healthFilter != .all else { return result }
        return result.filter { projectMatchesHealthFilter($0) }
    }

    var visibleDeliveryInspections: [ProjectDocumentDeliveryInspection] {
        let projectIDs = Set(searchMatchedProjects.map(\.id))
        return (preparedFiles?.inspections ?? []).filter { projectIDs.contains($0.project.id) }
    }

    var usesThreeColumnLayout: Bool {
        horizontalSizeClass == .regular
    }

    var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return projectStore.projects.first { $0.id == selectedProjectId }
    }

    var splitCategoryItems: [ProjectFileItem] {
        guard let selectedProjectId else { return [] }
        return preparedFiles?.items(for: selectedProjectId, category: selectedCategory, health: healthFilter) ?? []
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
                Section(AppLocalization.string("文件搜索结果")) {
                    if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(AppLocalization.string("正在搜索文件…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if displayedFileSearchResults.isEmpty {
                        Text(AppLocalization.string("未找到匹配文件，请尝试不同关键词。"))
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
                            Text(AppLocalization.string("仅显示前 30 条结果，请继续输入缩小范围。"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !displayedFileSearchResults.isEmpty {
                    Section(AppLocalization.string("建议下一步")) {
                        ProjectFileMicroGuideRow(
                            icon: "sparkle.magnifyingglass",
                            color: .appDoc,
                            title: AppLocalization.string("已命中文件，可直接预览"),
                            detail: AppLocalization.string("点条目可查看，点右侧菜单可分享或打开。")
                        )

                        if missingResultCount > 0 {
                            ProjectFileMicroGuideRow(
                                icon: "exclamationmark.triangle.fill",
                                color: .appRisk,
                                title: String(
                                    format: AppLocalization.string("发现 %lld 个缺失文件"),
                                    Int64(missingResultCount)
                                ),
                                detail: AppLocalization.string("建议回到项目详情重新导入图纸或资料，避免交付时缺件。")
                            )
                            NavigationLink {
                                ProjectListView(initialOverviewFilter: .active)
                            } label: {
                                Label(AppLocalization.string("去项目列表排查"), systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if filteredProjects.isEmpty {
                if normalizedQuery.isEmpty {
                    Section(AppLocalization.string("建议下一步")) {
                        ContentUnavailableView(
                            AppLocalization.string("暂无项目资料"),
                            systemImage: "folder",
                            description: Text(AppLocalization.string("先新建项目并补充日志、图纸、票据或随手记附件，这里会自动聚合显示。"))
                        )
                        NavigationLink {
                            ProjectListView(autoOpenComposerToken: 1)
                        } label: {
                            Label(AppLocalization.string("去新建项目"), systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.appProminent())
                    }
                } else {
                    Section(AppLocalization.string("建议下一步")) {
                        ContentUnavailableView(
                            AppLocalization.string("未找到匹配项目"),
                            systemImage: "magnifyingglass",
                            description: Text(
                                displayedFileSearchResults.isEmpty
                                    ? AppLocalization.string("请尝试其他关键词。")
                                    : AppLocalization.string("未匹配到项目名，可直接使用上方文件结果。")
                            )
                        )
                        Button {
                            searchText = ""
                        } label: {
                            Label(AppLocalization.string("清除关键词"), systemImage: "arrow.uturn.backward.circle")
                        }
                    }
                }
            } else {
                Section(AppLocalization.string("项目")) {
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
        .navigationTitle(AppLocalization.string("项目资料"))
        .navigationBarTitleDisplayMode(.inline)
    }

    var splitBrowserLayout: some View {
        NavigationSplitView {
            List {
                searchPanelSection
                deliveryInspectionSection(isSplitNavigation: true)

                ProjectFileHealthFilterSection(selection: $healthFilter)

                if !normalizedQuery.isEmpty {
                    Section(AppLocalization.string("文件搜索结果")) {
                        if isSearchingFiles || isBuildingFileIndex || normalizedQuery != normalizedDebouncedQuery {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(AppLocalization.string("正在搜索文件…"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if displayedFileSearchResults.isEmpty {
                            Text(AppLocalization.string("未找到匹配文件，请尝试不同关键词。"))
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
                                .accessibilityIdentifier("project-file-result-\(result.item.id)")
                            }
                        }
                    }
                }

                Section(AppLocalization.string("全部项目")) {
                    if filteredProjects.isEmpty {
                        Text(normalizedQuery.isEmpty ? AppLocalization.string("暂无项目") : AppLocalization.string("未找到匹配项目"))
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
            .navigationTitle(AppLocalization.string("项目资料"))
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

                    Section(AppLocalization.string("文件分类")) {
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
                            Text(preparedFiles == nil ? AppLocalization.string("正在搜索文件…") : AppLocalization.string("当前分类暂无文件"))
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
                        AppLocalization.string("请选择项目"),
                        systemImage: "building.2.crop.circle",
                        description: Text(AppLocalization.string("左侧是项目列表；选择后查看该项目资料。"))
                    )
                }
            }
            .navigationTitle(selectedProject?.name ?? AppLocalization.string("文件分类"))
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            ProjectFileBrowserDetailPanel(item: selectedSplitItem) { url in
                previewURL = url
            }
            .navigationTitle(AppLocalization.string("文件预览"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationSplitViewStyle(.balanced)
    }

    var searchPanelSection: some View {
        Section(AppLocalization.string("快速查找")) {
            InlineSearchPanel(
                text: $searchText,
                prompt: AppLocalization.string("搜索项目或资料文件"),
                suggestions: fileBrowserSearchSuggestions,
                emptyStateText: AppLocalization.string("未找到匹配项目或资料文件")
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
