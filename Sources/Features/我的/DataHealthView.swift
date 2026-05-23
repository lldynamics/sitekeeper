import SwiftUI
import UniformTypeIdentifiers

struct DataHealthView: View {
    @Environment(DataStore.self) var store
    @State private var showReferenceFixConfirm = false
    @State private var showOrphanFileCleanupConfirm = false
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var operationNotice: OperationToastNotice?
    @State private var selectedIssueProjectFilter = DataHealthIssueProjectFilter.all
    @State private var showsOnlyAutoFixableIssues = false
    @State private var expandedIssueSectionIDs: Set<String> = []
    private let showsNavigationTitle: Bool
    private let issuePreviewLimit = 50

    init(showsNavigationTitle: Bool = true) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    func l(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    func lf(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    var body: some View {
        List {
            Section(l("健康概览")) {
                LabeledContent(l("问题总数"), value: "\(totalIssues)")
                LabeledContent(l("缺失照片"), value: "\(missingPhotoFiles.count)")
                LabeledContent(l("缺失票据文件"), value: "\(missingDocumentFiles.count)")
                LabeledContent(l("缺失随手记附件"), value: "\(missingQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立照片文件"), value: "\(orphanPhotoFiles.count)")
                LabeledContent(l("孤立图纸文件"), value: "\(orphanDrawingFiles.count)")
                LabeledContent(l("孤立票据文件"), value: "\(orphanDocumentFiles.count)")
                LabeledContent(l("孤立随手记附件"), value: "\(orphanQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立附件映射"), value: "\(orphanAttachmentMappings.count)")
                LabeledContent(l("仓库悬空附件映射"), value: "\(orphanWarehouseAttachmentMappings.count)")
                LabeledContent(l("资料悬空关联"), value: "\(danglingDocumentLinks.count)")
                LabeledContent(l("无效项目关联"), value: "\(invalidProjectRefs.count)")
                LabeledContent(l("可自动修复项目关联"), value: "\(autoFixableInvalidProjectRefs.count)")
                LabeledContent(l("需手动处理项目关联"), value: "\(manualInvalidProjectRefs.count)")
                LabeledContent(l("存储错误记录"), value: "\(storageIssues.count)")
            }

            Section(l("存储空间")) {
                LabeledContent(l("照片"), value: QuickNoteAttachmentStorage.formattedFileSize(photoStorageBytes))
                LabeledContent(l("资料（票据/图纸/附件）"), value: QuickNoteAttachmentStorage.formattedFileSize(projectAssetBytes))
                LabeledContent(l("备份（iCloud）"), value: QuickNoteAttachmentStorage.formattedFileSize(cloudBackupBytes))
                LabeledContent(l("历史计算"), value: "\(store.historyRecords.count) 条 · \(QuickNoteAttachmentStorage.formattedFileSize(historyRecordBytes))")
                LabeledContent(l("缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                LabeledContent(l("合计"), value: QuickNoteAttachmentStorage.formattedFileSize(totalStorageBytes))
            }

            Section(l("Widget 与缓存")) {
                LabeledContent(l("App Group 可读"), value: widgetHealth.appGroupReadable ? l("是") : l("否"))
                LabeledContent(l("Widget 项目数"), value: "\(widgetHealth.projectCount)")
                LabeledContent(l("Widget 待办数"), value: "\(widgetHealth.pendingTodos)")
                LabeledContent(
                    l("Widget 最近同步"),
                    value: widgetHealth.lastUpdatedAt.map { Formatters.dateTime.string(from: $0) } ?? l("暂无")
                )
                LabeledContent(l("照片缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(photoThumbnailCacheBytes))
                LabeledContent(l("附件缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(quickNoteThumbnailCacheBytes))
                LabeledContent(l("缩略图缓存合计"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                Button(role: .destructive) {
                    clearMediaThumbnailCaches()
                } label: {
                    Label(l("清理缩略图缓存"), systemImage: "trash")
                }
                .disabled(mediaThumbnailCacheBytes == 0)
            }

            Section(l("处理")) {
                Button {
                    showReferenceFixConfirm = true
                } label: {
                    Label(l("修复引用与关联（不删原件）"), systemImage: "wrench.and.screwdriver")
                }
                .disabled(referenceIssueCount == 0)
                Button(role: .destructive) {
                    showOrphanFileCleanupConfirm = true
                } label: {
                    Label(l("清理孤立原文件"), systemImage: "trash")
                }
                .disabled(orphanFileIssueCount == 0)
                Button {
                    createDataHealthRepairTodo()
                } label: {
                    Label(l("生成健康整改待办"), systemImage: "checklist.checked")
                }
                .disabled(totalIssues == 0)
                Button {
                    exportHealthReport()
                } label: {
                    Label(l("导出健康报告"), systemImage: "square.and.arrow.up")
                }
                if !storageIssues.isEmpty {
                    Button(role: .destructive) {
                        StorageIssueLog.clear()
                        _ = store.scanDataHealthNow(reason: .manual)
                    } label: {
                        Label(l("清空存储错误记录"), systemImage: "trash")
                    }
                }
            }

            issueFilterSection

            ForEach(issueSections) { section in
                issueSection(section)
            }
        }
        .modifier(OptionalInlineTitleModifier(
            isEnabled: showsNavigationTitle,
            title: l("数据健康检查")
        ))
        .task {
            if store.latestDataHealthSnapshot == nil {
                store.runDataHealthScanNow(reason: .manual)
            } else {
                store.scheduleDataHealthScanIfStale(reason: .scheduled, maxAge: 15 * 60)
            }
        }
        .alert(l("修复引用与关联？"), isPresented: $showReferenceFixConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("修复"), role: .destructive) {
                repairReferenceIssues()
            }
        } message: {
            Text(l("将修复缺失引用、财务/仓库悬空附件映射、资料悬空关联和可置空的无效项目关联，不会删除任何照片、图纸、票据或随手记原文件。无法自动修复的项目关联会保留在“需手动处理项目关联”列表。"))
        }
        .alert(l("清理孤立原文件？"), isPresented: $showOrphanFileCleanupConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("清理"), role: .destructive) {
                cleanupOrphanFiles()
            }
        } message: {
            Text(l("将删除未被任何记录引用的照片、图纸、票据和随手记附件。请先确认这些原件无需保留。"))
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .plainText,
            defaultFilename: exportPayload?.defaultFilename ?? l("数据健康报告.txt")
        ) { _ in }
        .operationToast(notice: $operationNotice)
    }

    @ViewBuilder
    private var issueFilterSection: some View {
        Section(l("问题筛选")) {
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
    private func issueSection(_ section: DataHealthIssueSection) -> some View {
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

    private var issueSections: [DataHealthIssueSection] {
        [
            DataHealthIssueSection(id: "missingPhotoFiles", title: l("缺失照片文件"), items: missingPhotoFileIssues),
            DataHealthIssueSection(id: "missingDocumentFiles", title: l("缺失票据文件"), items: missingDocumentFileIssues),
            DataHealthIssueSection(id: "missingQuickNoteAttachmentFiles", title: l("缺失随手记附件"), items: missingQuickNoteAttachmentIssues),
            DataHealthIssueSection(id: "orphanPhotoFiles", title: l("孤立照片文件"), items: orphanPhotoFileIssues),
            DataHealthIssueSection(id: "orphanDrawingFiles", title: l("孤立图纸文件"), items: orphanDrawingFileIssues),
            DataHealthIssueSection(id: "orphanDocumentFiles", title: l("孤立票据文件"), items: orphanDocumentFileIssues),
            DataHealthIssueSection(id: "orphanQuickNoteAttachmentFiles", title: l("孤立随手记附件"), items: orphanQuickNoteAttachmentIssues),
            DataHealthIssueSection(id: "orphanAttachmentMappings", title: l("孤立附件映射"), items: orphanAttachmentMappingIssues),
            DataHealthIssueSection(id: "orphanWarehouseAttachmentMappings", title: l("仓库悬空附件映射"), items: orphanWarehouseAttachmentMappingIssues),
            DataHealthIssueSection(id: "danglingDocumentLinks", title: l("资料悬空关联"), items: danglingDocumentLinkIssues),
            DataHealthIssueSection(id: "autoFixableInvalidProjectRefs", title: l("无效项目关联（可自动修复）"), items: autoFixableInvalidProjectRefIssues),
            DataHealthIssueSection(id: "manualInvalidProjectRefs", title: l("无效项目关联（需手动处理）"), items: manualInvalidProjectRefIssues),
            DataHealthIssueSection(id: "storageIssueRows", title: l("存储错误记录"), items: storageIssueRows)
        ]
    }

    private var filteredIssueCount: Int {
        issueSections.reduce(0) { total, section in
            total + filteredIssueItems(section.items).count
        }
    }

    private var hasActiveIssueFilters: Bool {
        selectedIssueProjectFilter != DataHealthIssueProjectFilter.all || showsOnlyAutoFixableIssues
    }

    private func filteredIssueItems(_ items: [DataHealthIssue]) -> [DataHealthIssue] {
        items.filter { issue in
            matchesAutoFixableFilter(issue) && matchesProjectFilter(issue)
        }
    }

    private func matchesAutoFixableFilter(_ issue: DataHealthIssue) -> Bool {
        !showsOnlyAutoFixableIssues || issue.isAutoFixable
    }

    private func matchesProjectFilter(_ issue: DataHealthIssue) -> Bool {
        switch selectedIssueProjectFilter {
        case DataHealthIssueProjectFilter.all:
            return true
        case DataHealthIssueProjectFilter.noProject:
            return issue.effectiveProjectId == nil
        case DataHealthIssueProjectFilter.invalidProject:
            guard let projectId = issue.effectiveProjectId else { return false }
            return !projectIdSet.contains(projectId)
        default:
            guard let projectId = issue.effectiveProjectId else { return false }
            return selectedIssueProjectFilter == DataHealthIssueProjectFilter.project(projectId)
        }
    }

    private func issueSectionTitle(_ title: String, filteredCount: Int, totalCount: Int) -> String {
        if filteredCount == totalCount {
            return "\(title) (\(totalCount))"
        }
        return "\(title) (\(filteredCount)/\(totalCount))"
    }

    private func toggleIssueSectionExpansion(_ sectionID: String) {
        withAnimation(.snappy(duration: 0.18)) {
            if expandedIssueSectionIDs.contains(sectionID) {
                expandedIssueSectionIDs.remove(sectionID)
            } else {
                expandedIssueSectionIDs.insert(sectionID)
            }
        }
    }

    private func resetIssueFilters() {
        selectedIssueProjectFilter = DataHealthIssueProjectFilter.all
        showsOnlyAutoFixableIssues = false
        expandedIssueSectionIDs.removeAll()
    }

    @ViewBuilder
    private func issueRow(_ item: DataHealthIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            issueLabel(item)
            issueActionBar(item)
        }
        .padding(.vertical, 2)
    }

    private func issueLabel(_ item: DataHealthIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.color)
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.exportText)
    }

    @ViewBuilder
    private func issueActionBar(_ item: DataHealthIssue) -> some View {
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

    private func issueActions(for item: DataHealthIssue) -> [DataHealthIssueAction] {
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
    private func issueActionControl(_ action: DataHealthIssueAction, for item: DataHealthIssue) -> some View {
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

    private func issueActionLabel(_ action: DataHealthIssueAction) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.caption2.weight(.semibold))
    }

    @ViewBuilder
    private func issueDestination(_ route: DataHealthIssueRoute) -> some View {
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
