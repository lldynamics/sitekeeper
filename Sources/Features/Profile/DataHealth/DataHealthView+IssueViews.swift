import SwiftUI

extension DataHealthView {
    @ViewBuilder
    var issueFilterSection: some View {
        Section(l("问题筛选")) {
            Picker(l("排序"), selection: $selectedIssueSort) {
                ForEach(DataHealthIssueSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Picker(l("按项目过滤"), selection: $selectedIssueProjectFilter) {
                Text(l("全部问题")).tag(DataHealthIssueProjectFilter.all)
                Text(l("无项目线索")).tag(DataHealthIssueProjectFilter.noProject)
                Text(l("无效项目关联")).tag(DataHealthIssueProjectFilter.invalidProject)
                ForEach(store.projects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                    Text(project.name.isEmpty ? l("未命名项目") : project.name)
                        .tag(DataHealthIssueProjectFilter.project(project.id))
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $showsOnlyAutoFixableIssues) {
                Label(l("只看可自动修复"), systemImage: "wrench.and.screwdriver")
            }

            if !issueSearchKeyword.isEmpty {
                LabeledContent(l("搜索关键词"), value: issueSearchKeyword)
            }
            LabeledContent(l("当前筛选结果"), value: "\(filteredIssueCount)")

            if hasActiveIssueFilters {
                Button {
                    resetIssueFilters()
                } label: {
                    Label(l("重置筛选"), systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    @ViewBuilder
    var issueRepairImpactPreviewSection: some View {
        Section(l("批量修复影响预览")) {
            LabeledContent(l("筛选内问题"), value: "\(filteredIssueCount)")
            LabeledContent(l("可自动修复"), value: "\(autoFixableFilteredIssueCount)")
            LabeledContent(l("需手动处理"), value: "\(manualFilteredIssueCount)")
            LabeledContent(l("预计修复引用/关联"), value: "\(filteredRepairActionCount)")
            LabeledContent(l("预计移入回收站"), value: "\(filteredTrashActionCount)")

            if repairImpactRows.isEmpty {
                Text(l("当前筛选项没有可批量执行的修复动作"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(repairImpactRows.prefix(8).indices), id: \.self) { index in
                    let row = repairImpactRows[index]
                    LabeledContent(row.title, value: "\(row.count)")
                        .font(.caption)
                }
                if repairImpactRows.count > 8 {
                    Text(lf("其余 %lld 项可在筛选后分批处理", Int64(repairImpactRows.count - 8)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    var issueRepairRecordPreviewSection: some View {
        Section(l("修复前影响记录预览")) {
            LabeledContent(l("引用修复目标"), value: "\(referenceIssueCount)")
            if referenceRepairPreviewIssues.isEmpty {
                Text(l("当前没有可执行的引用修复目标"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(referenceRepairPreviewIssues.prefix(impactRecordPreviewLimit).indices), id: \.self) { index in
                    let issue = referenceRepairPreviewIssues[index]
                    impactPreviewIssueRow(issue)
                }
                let remaining = max(referenceRepairPreviewIssues.count - impactRecordPreviewLimit, 0)
                if remaining > 0 {
                    Text(lf("其余 %lld 条可在下方异常列表查看", Int64(remaining)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent(l("孤立清理目标"), value: "\(orphanFileIssueCount)")
            if orphanCleanupPreviewFiles.isEmpty {
                Text(l("当前没有可清理的孤立原文件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orphanCleanupPreviewFiles.prefix(impactRecordPreviewLimit).indices), id: \.self) { index in
                    let file = orphanCleanupPreviewFiles[index]
                    Label(
                        "\(orphanFileKindTitle(file.kind)) · \(file.fileName)",
                        systemImage: orphanFileKindSymbol(file.kind)
                    )
                    .font(.caption)
                    .lineLimit(1)
                }
                let remaining = max(orphanCleanupPreviewFiles.count - impactRecordPreviewLimit, 0)
                if remaining > 0 {
                    Text(lf("其余 %lld 个孤立文件可在下方异常列表查看", Int64(remaining)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    func issueSection(_ section: DataHealthIssueSection) -> some View {
        let filteredItems = filteredIssueItems(section.items)
        let isExpanded = expandedIssueSectionIDs.contains(section.id)
        let visibleItems = isExpanded ? filteredItems : Array(filteredItems.prefix(issuePreviewLimit))
        Section(issueSectionTitle(section.title, filteredCount: filteredItems.count, totalCount: section.items.count)) {
            if section.items.isEmpty {
                Text(l("未发现问题"))
                    .foregroundStyle(.secondary)
            } else if filteredItems.isEmpty {
                Text(l("当前筛选无结果"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleItems) { item in
                    issueRow(item)
                }
                if filteredItems.count > issuePreviewLimit {
                    Button {
                        toggleIssueSectionExpansion(section.id)
                    } label: {
                        Label(
                            isExpanded
                            ? l("收起到前 50 条")
                            : lf("查看全部 %lld 条", Int64(filteredItems.count)),
                            systemImage: isExpanded ? "chevron.up.circle" : "list.bullet.rectangle"
                        )
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    func impactPreviewIssueRow(_ issue: DataHealthIssue) -> some View {
        if let route = issue.route {
            NavigationLink {
                issueDestination(route)
            } label: {
                Label(issue.exportText, systemImage: issue.systemImage)
                    .font(.caption)
                    .lineLimit(2)
            }
        } else {
            Label(issue.exportText, systemImage: issue.systemImage)
                .font(.caption)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    func issueRow(_ item: DataHealthIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            issueLabel(item)
            issueActionBar(item)
        }
        .padding(.vertical, 2)
    }

    func issueLabel(_ item: DataHealthIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.color)
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    issueSeverityBadge(item.severity)
                }
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.exportText)
    }

    func issueSeverityBadge(_ severity: DataHealthIssueSeverity) -> some View {
        Text(severity.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(severity.tintColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severity.tintColor.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    func issueActionBar(_ item: DataHealthIssue) -> some View {
        let actions = issueActions(for: item)
        if !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(actions) { action in
                        issueActionControl(action, for: item)
                    }
                }
            }
            .padding(.leading, 34)
        }
    }

    func issueActions(for item: DataHealthIssue) -> [DataHealthIssueAction] {
        var actions = item.actions
        if let route = item.route,
           !actions.contains(where: { action in
               if case .navigate = action.kind { return true }
               return false
           }) {
            actions.insert(
                .navigate(
                    title: item.actionTitle ?? l("打开记录"),
                    route: route
                ),
                at: 0
            )
        }
        if !actions.contains(where: { action in
            if case .createTodo = action.kind { return true }
            return false
        }) {
            actions.append(.createTodo(title: l("生成专项待办")))
        }
        return actions
    }

    @ViewBuilder
    func issueActionControl(_ action: DataHealthIssueAction, for item: DataHealthIssue) -> some View {
        switch action.kind {
        case .navigate(let route):
            NavigationLink {
                issueDestination(route)
            } label: {
                issueActionLabel(action)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        case .repair, .moveOrphanFileToTrash, .createTodo:
            Button(role: action.role) {
                performIssueAction(action, for: item)
            } label: {
                issueActionLabel(action)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    func issueActionLabel(_ action: DataHealthIssueAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.caption2.weight(.semibold))
    }

    @ViewBuilder
    func issueDestination(_ route: DataHealthIssueRoute) -> some View {
        switch route {
        case .project(let projectId, let mode):
            ProjectDetailView(projectId: projectId, initialMode: mode)
        case .financialRecord(let projectId, let recordId):
            ProjectDetailView(projectId: projectId, initialMode: .finance, focus: .financialRecord(recordId))
        case .document(let projectId, let documentId):
            ProjectDetailView(projectId: projectId, initialMode: .records, focus: .document(documentId))
        case .dailyLog(let projectId, let logId):
            DailyLogView(initialProjectId: projectId, focusedLogId: logId)
        case .siteTodo(let projectId, let todoId):
            SiteTodoView(initialProjectId: projectId, focusedTodoId: todoId)
        case .material(let materialId):
            MaterialListView(focusedMaterialId: materialId)
        case .quote(let quoteId):
            QuotationView(focusedQuoteId: quoteId)
        case .labor(let laborId):
            LaborRecordView(focusedLaborId: laborId)
        case .quickNote(let noteId):
            QuickNoteView(focusedNoteId: noteId)
        case .contact(let contactId):
            ProjectContactDatabaseView(focusedContactId: contactId)
        case .warehouseProject(let projectId):
            if let project = store.projects.first(where: { $0.id == projectId }) {
                ProjectWarehouseView(project: project)
            } else {
                ContentUnavailableView(l("项目不存在"), systemImage: "questionmark.folder")
            }
        }
    }
}
