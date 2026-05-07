import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import VisionKit
import PhotosUI

struct ProjectDetailView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    let projectId: UUID
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool

    @StateObject private var exportState = ProjectDetailExportStateModel()
    @State private var detailMode: ProjectDetailMode = .overview
    @State private var drawingFilter: DrawingListFilter = .all
    @State private var showProjectEdit = false
    @State private var showContactAdd = false
    @State private var showFinancialAdd = false
    @State private var showDocumentScanSetup = false
    @State private var showDocumentFileImporter = false
    @State private var showImagePicker = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var editingMaterial: MaterialItem?
    @State private var editingQuote: QuoteItem?
    @State private var editingLabor: LaborRecord?
    @State private var editingProgress: ProgressTask?
    @State private var editingDrawing: ProjectDrawing?
    @State private var editingDocument: ProjectDocument?
    @State private var editingFinancialRecord: ProjectFinancialRecord?
    @State private var attachmentManagingRecord: ProjectFinancialRecord?
    @State private var editingContact: ProjectContact?
    @State private var timelineContext: DrawingTimelineContext?
    @State private var selectedPhotoContext: ProjectPhotoContext?
    @State private var quickLookURL: URL?
    @State private var showDrawingImporter = false
    @State private var scanTarget: ProjectScanTarget?
    @State private var importErrorMessage = ""
    @State private var showImportError = false
    @State private var showFinancialDeleteConfirm = false
    @State private var pendingDeleteFinancialRecordIDs: Set<UUID> = []
    @State private var didAutoOpenFinancialAdd = false
    @State private var didAutoOpenDocumentScanSetup = false
    @State private var didOpenFocusedItem = false

    @State private var showSheet: DetailSheet?

    init(
        projectId: UUID,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false
    ) {
        self.projectId = projectId
        self.focus = focus
        self.autoOpenFinancialAdd = autoOpenFinancialAdd
        self.autoOpenDocumentScanSetup = autoOpenDocumentScanSetup
        _detailMode = State(initialValue: initialMode ?? .overview)
    }

    private static let drawingImportTypes: [UTType] = {
        var types: [UTType] = [.pdf]
        if let dwg = UTType(filenameExtension: "dwg") {
            types.append(dwg)
        }
        if let dxf = UTType(filenameExtension: "dxf") {
            types.append(dxf)
        }
        return types
    }()
    private static let documentImportTypes: [UTType] = [.item]

    private var project: Project? { store.projects.first { $0.id == projectId } }
    private var relatedMaterials: [MaterialItem] { store.materialItems.filter { $0.projectId == projectId } }
    private var relatedQuotes: [QuoteItem] { store.quoteItems.filter { $0.projectId == projectId } }
    private var relatedLabor: [LaborRecord] { store.laborRecords.filter { $0.projectId == projectId } }
    private var relatedWarehouseMovements: [ProjectWarehouseMovement] { store.projectWarehouseMovements.filter { $0.projectId == projectId } }
    private var relatedLogs: [DailyLog] { store.dailyLogs.filter { $0.projectId == projectId } }
    private var relatedProgress: [ProgressTask] { store.progressTasks.filter { $0.projectId == projectId } }
    private var relatedDrawings: [ProjectDrawing] {
        store.projectDrawings
            .filter { $0.projectId == projectId }
            .sorted { $0.importedAt > $1.importedAt }
    }
    private var relatedContacts: [ProjectContact] {
        store.projectContacts
            .filter { $0.projectId == projectId }
            .sorted { $0.name < $1.name }
    }
    private var relatedFinancialRecords: [ProjectFinancialRecord] {
        store.projectFinancialRecords
            .filter { $0.projectId == projectId }
            .sorted { $0.date > $1.date }
    }
    private var relatedDocuments: [ProjectDocument] {
        store.projectDocuments
            .filter { $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var relatedQuickNotes: [QuickNote] {
        store.quickNotes
            .filter { $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var filteredDrawings: [ProjectDrawing] {
        switch drawingFilter {
        case .all:
            return relatedDrawings
        case .current:
            return relatedDrawings.filter(\.isCurrentVersion)
        case .withIssue:
            return relatedDrawings.filter {
                let status = DrawingIssueStatus(rawValue: $0.issueStatus) ?? .none
                return status == .open || status == .inProgress || !$0.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
    private var legacyPayments: [PaymentRecord] {
        store.paymentRecords
            .filter { $0.projectId == projectId }
            .sorted { $0.date > $1.date }
    }

    private var quoteTotal: Double {
        relatedQuotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
    }

    private var materialCostAuto: Double {
        relatedMaterials.reduce(0) { $0 + ReportBuilder.materialLineTotal($1) }
    }

    private var laborCostAuto: Double {
        relatedLabor.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    private var laborHoursTotal: Double {
        relatedLabor.reduce(0) { $0 + ReportBuilder.laborHours($1) }
    }
    private var projectBookIncome: Double {
        relatedFinancialRecords
            .filter { $0.direction == ProjectFinancialDirection.income.rawValue }
            .reduce(0) { $0 + ReportBuilder.number($1.amount) }
    }
    private var projectBookExpense: Double {
        relatedFinancialRecords
            .filter { $0.direction == ProjectFinancialDirection.expense.rawValue }
            .reduce(0) { $0 + ReportBuilder.number($1.amount) }
    }
    private var todayStr: String { Formatters.date.string(from: Date()) }
    private var overdueProgressCount: Int {
        relatedProgress.filter { task in
            guard task.clampedCompletion < 1, let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }.count
    }
    private var overdueTodoCount: Int {
        store.siteTodos.filter { $0.projectId == projectId && $0.isOverdue }.count
    }
    private var openTodoCount: Int {
        store.siteTodos.filter { $0.projectId == projectId && !$0.isDone }.count
    }
    private var unpricedQuoteCount: Int {
        relatedQuotes.filter { ReportBuilder.number($0.unitPrice) <= 0 }.count
    }
    private var hasTodayLog: Bool {
        relatedLogs.contains { $0.date == todayStr }
    }

    private var usesCockpitLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if let project = project {
                content(project: project)
            } else {
                ContentUnavailableView("项目不存在", systemImage: "questionmark.folder")
            }
        }
    }

    private func content(project: Project) -> some View {
        let statusBinding = Binding(
            get: { project.status },
            set: { newVal in
                if let idx = store.projects.firstIndex(where: { $0.id == projectId }) {
                    store.projects[idx].status = newVal
                    store.scheduleSave()
                }
            }
        )

        return detailScaffold(project: project, statusBinding: statusBinding)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showProjectEdit = true
                    } label: {
                        Label("编辑资料", systemImage: "square.and.pencil")
                    }
                    Button {
                        requestExportProjectPackage(project)
                    } label: {
                        Label("导出项目交付包 ZIP", systemImage: "archivebox.fill")
                    }
                    Button {
                        exportDailyReport(project)
                    } label: {
                        Label("导出施工日报", systemImage: "doc.text.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("导出与交付")
            }
        }
        .projectDetailExportHost(
            exportPayload: $exportState.exportPayload,
            showExporter: $exportState.showExporter,
            pendingPackageProject: $exportState.pendingPackageProject,
            packageSizeWarningMessage: $exportState.packageSizeWarningMessage,
            showPackageSizeWarning: $exportState.showPackageSizeWarning,
            onContinuePackageExport: exportProjectPackage(_:)
        )
        .projectDetailEntrySheetCoordinator(
            project: project,
            projectId: projectId,
            showSheet: $showSheet,
            showProjectEdit: $showProjectEdit,
            showContactAdd: $showContactAdd,
            showFinancialAdd: $showFinancialAdd,
            showDocumentScanSetup: $showDocumentScanSetup,
            showImagePicker: $showImagePicker,
            imagePickerSource: $imagePickerSource,
            onUpdateProject: updateProject(_:),
            onCreateContact: { contact in
                store.projectContacts.append(contact)
                store.scheduleSave()
            },
            onCreateFinancialRecord: { record, shouldScan in
                store.projectFinancialRecords.append(record)
                if shouldScan {
                    scanTarget = scanTarget(for: record)
                }
                store.scheduleSave()
            },
            onCreateScanTarget: { target in
                scanTarget = target
            },
            onImportCapturedImage: { image in
                importCapturedImage(image)
            }
        )
        .projectDetailEditingSheetCoordinator(
            editingMaterial: $editingMaterial,
            editingQuote: $editingQuote,
            editingLabor: $editingLabor,
            editingProgress: $editingProgress,
            selectedPhotoContext: $selectedPhotoContext,
            editingDrawing: $editingDrawing,
            editingDocument: $editingDocument,
            editingContact: $editingContact,
            editingFinancialRecord: $editingFinancialRecord,
            attachmentManagingRecord: $attachmentManagingRecord,
            scanTarget: $scanTarget,
            timelineContext: $timelineContext,
            useMetric: useMetric,
            projects: store.projects,
            relatedLogs: relatedLogs,
            relatedFinancialRecords: relatedFinancialRecords,
            linkedDocuments: linkedDocuments(for:),
            attachmentSheetBuilder: { record in
                AnyView(attachmentSheet(record: record))
            },
            timelineDrawings: timelineDrawings(name:),
            onSaveMaterial: saveMaterial,
            onDeleteMaterial: deleteMaterial(id:),
            onSaveQuote: saveQuote,
            onDeleteQuote: deleteQuote(id:),
            onSaveLabor: saveLabor,
            onDeleteLabor: deleteLabor,
            onSaveProgress: saveProgress,
            onDeleteProgress: deleteProgress(id:),
            onUpdatePhoto: { context, note, tag in
                updateProjectPhoto(context: context, note: note, tag: tag)
            },
            onDeletePhoto: { context in
                deleteProjectPhoto(context: context)
            },
            onSaveDrawing: saveDrawing(_:),
            onDeleteDrawing: deleteDrawing(_:),
            onPreviewDrawing: previewDrawing(_:),
            onSaveDocument: saveDocumentEdit(_:),
            onDeleteDocument: deleteDocument(_:),
            onPreviewDocument: previewDocument(_:),
            onSaveContact: saveContact(_:),
            onDeleteContact: deleteContact(_:),
            onSaveFinancialRecord: saveFinancialRecord,
            onDeleteFinancialRecord: requestDeleteFinancialRecord(_:),
            onScanFinancialRecord: { target in
                scanTarget = scanTarget(for: target)
            },
            onManageAttachments: { target in
                attachmentManagingRecord = target
            },
            onSaveScannedDocument: saveScannedDocument(target:data:pageCount:),
            onPresentImportError: presentImportError(_:),
            onSetDrawingCurrentVersion: setDrawingAsCurrentVersion(_:),
            onEditDrawingFromTimeline: { drawing in
                editingDrawing = drawing
            }
        )
        .fileImporter(
            isPresented: $showDrawingImporter,
            allowedContentTypes: Self.drawingImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importDrawings(urls)
            case .failure:
                break
            }
        }
        .fileImporter(
            isPresented: $showDocumentFileImporter,
            allowedContentTypes: Self.documentImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importProjectDocuments(urls)
            case .failure:
                break
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await importPhotoItem(item)
                await MainActor.run {
                    selectedPhotoItem = nil
                }
            }
        }
        .quickLookPreview($quickLookURL)
        .onAppear(perform: handleOnAppear)
        .onDisappear {
            exportState.cancelExportTask()
        }
        .alert("操作失败", isPresented: $showImportError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
        .confirmationDialog("删除账目", isPresented: $showFinancialDeleteConfirm, titleVisibility: .visible) {
            Button("仅删除账目（保留票据）", role: .destructive) {
                performDeleteFinancialRecords(deleteLinkedDocuments: false)
            }
            Button("删除账目并删除票据", role: .destructive) {
                performDeleteFinancialRecords(deleteLinkedDocuments: true)
            }
            Button("取消", role: .cancel) {
                pendingDeleteFinancialRecordIDs.removeAll()
            }
        } message: {
            Text(String(localized: "将删除 \(pendingDeleteFinancialRecordIDs.count) 条账目。可选择保留票据为项目资料。"))
        }
        .overlay {
            if exportState.isExportingProjectPackage {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                    ProjectPackageExportOverlayView(
                        progress: exportState.projectPackageExportProgress,
                        onCancel: cancelProjectPackageExport
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func detailScaffold(project: Project, statusBinding: Binding<String>) -> some View {
        if usesCockpitLayout {
            cockpitScaffold(project: project, statusBinding: statusBinding)
        } else {
            compactScaffold(project: project, statusBinding: statusBinding)
        }
    }

    private func compactScaffold(project: Project, statusBinding: Binding<String>) -> some View {
        List {
            projectHeader(project: project, statusBinding: statusBinding)
            quickActionSection
            Section {
                Picker("内容", selection: $detailMode) {
                    ForEach(ProjectDetailMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            detailContent(project: project)
        }
    }

    private func cockpitScaffold(project: Project, statusBinding: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            cockpitSidebar(project: project, statusBinding: statusBinding)
                .frame(minWidth: 276, maxWidth: 330, alignment: .topLeading)

            List {
                detailContent(project: project)
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cockpitSidebar(project: Project, statusBinding: Binding<String>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(project.location.isEmpty ? "未填写地址" : project.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Picker("状态", selection: statusBinding) {
                            ForEach(ProjectStatus.allCases, id: \.rawValue) { item in
                                Text(item.displayName).tag(item.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack(spacing: 8) {
                        cockpitMetric(title: "进度", value: "\(Int(averageProgress(relatedProgress) * 100))%", color: .orange)
                        cockpitMetric(title: "报价", value: ReportBuilder.money(quoteTotal), color: .blue)
                        cockpitMetric(title: "待办", value: "\(openTodoCount)", color: .orange)
                    }

                    ProjectDetailRiskStripView(
                        overdueCount: overdueProgressCount + overdueTodoCount,
                        unpaidAmount: unpaidAmount(project),
                        unpricedQuoteCount: unpricedQuoteCount,
                        hasTodayLog: hasTodayLog
                    )

                    if !project.customerName.isEmpty || !project.customerPhone.isEmpty {
                        Text("客户: \(project.customerName) \(project.customerPhone)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !project.startDate.isEmpty || !project.expectedEndDate.isEmpty {
                        Text("工期: \(project.startDate.isEmpty ? "未填写" : project.startDate) 至 \(project.expectedEndDate.isEmpty ? "未填写" : project.expectedEndDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("内容导航")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(ProjectDetailMode.allCases, id: \.self) { mode in
                        Button {
                            detailMode = mode
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: mode))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 16)
                                Text(mode.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if detailMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(detailMode == mode ? Color.orange.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷工具")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    cockpitActionButton("写日志", systemImage: "book.pages.fill", tint: .green) {
                        showSheet = .log
                    }
                    cockpitActionButton("记账", systemImage: "receipt.fill", tint: .pink) {
                        showFinancialAdd = true
                    }
                    cockpitActionButton("联系人", systemImage: "person.crop.circle.badge.plus", tint: .blue) {
                        showContactAdd = true
                    }
                    cockpitActionButton("导入图纸", systemImage: "doc.viewfinder.fill", tint: .indigo) {
                        showDrawingImporter = true
                    }
                    cockpitActionButton("添加材料", systemImage: "shippingbox.fill", tint: .orange) {
                        showSheet = .material
                    }
                    cockpitActionButton("添加报价", systemImage: "doc.text.fill", tint: .brown) {
                        showSheet = .quote
                    }
                    cockpitActionButton("记人工", systemImage: "person.2.fill", tint: .purple) {
                        showSheet = .labor
                    }
                    NavigationLink {
                        LightingCircuitPlannerView(initialProjectId: projectId)
                    } label: {
                        cockpitActionLabel("照明回路", systemImage: "tablecells.fill", tint: .teal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func cockpitMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .tertiarySystemGroupedBackground)))
    }

    private func cockpitActionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            cockpitActionLabel(title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func cockpitActionLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private func icon(for mode: ProjectDetailMode) -> String {
        switch mode {
        case .overview:
            return "square.grid.2x2"
        case .records:
            return "book.pages"
        case .finance:
            return "receipt"
        case .assets:
            return "folder"
        }
    }

    private func projectHeader(project: Project, statusBinding: Binding<String>) -> some View {
        ProjectDetailHeaderSection(
            project: project,
            status: statusBinding,
            progressValue: "\(Int(averageProgress(relatedProgress) * 100))%",
            quoteValue: ReportBuilder.money(quoteTotal),
            todoValue: "\(openTodoCount)",
            riskStrip: AnyView(
                ProjectDetailRiskStripView(
                    overdueCount: overdueProgressCount + overdueTodoCount,
                    unpaidAmount: unpaidAmount(project),
                    unpricedQuoteCount: unpricedQuoteCount,
                    hasTodayLog: hasTodayLog
                )
            ),
            customerLine: (!project.customerName.isEmpty || !project.customerPhone.isEmpty)
                ? "客户: \(project.customerName) \(project.customerPhone)"
                : nil,
            periodLine: (!project.startDate.isEmpty || !project.expectedEndDate.isEmpty)
                ? "工期: \(project.startDate.isEmpty ? "未填写" : project.startDate) 至 \(project.expectedEndDate.isEmpty ? "未填写" : project.expectedEndDate)"
                : nil,
            onEditProject: { showProjectEdit = true }
        )
    }

    private var quickActionSection: some View {
        ProjectDetailQuickActionSection(
            onAddLog: { showSheet = .log },
            onAddFinance: { showFinancialAdd = true },
            onAddContact: { showContactAdd = true },
            onImportDrawing: { showDrawingImporter = true },
            onAddMaterial: { showSheet = .material },
            onAddQuote: { showSheet = .quote },
            onAddLabor: { showSheet = .labor },
            lightingDestination: AnyView(LightingCircuitPlannerView(initialProjectId: projectId))
        )
    }

    @ViewBuilder
    private func detailContent(project: Project) -> some View {
        ProjectDetailModeContent(mode: detailMode) {
            overviewSections(project: project)
        } records: {
            recordHubSections
        } finance: {
            financeHubSections(project: project)
        } assets: {
            assetHubSections
        }
    }

    private func overviewSections(project: Project) -> some View {
        ProjectOverviewView(
            project: project,
            paidAmount: paidAmount(project),
            unpaidAmount: unpaidAmount(project),
            materialCost: currentMaterialCost(project),
            laborCost: currentLaborCost(project),
            estimatedProfit: estimatedProfit(project),
            laborHours: trim(laborHoursTotal),
            projectBookIncome: projectBookIncome,
            projectBookExpense: projectBookExpense,
            logDayCount: Set(relatedLogs.map(\.date)).count,
            materialCount: relatedMaterials.count,
            contactCount: relatedContacts.count,
            financialCount: relatedFinancialRecords.count,
            documentCount: relatedDocuments.count,
            recentLogs: relatedLogs,
            todos: store.siteTodos.filter { $0.projectId == projectId && !$0.isDone },
            logRow: { log in
                ProjectDetailLogRowView(log: log)
            }
        )
    }

    private var recordHubSections: some View {
        ProjectRecordHubSectionView(
            logsCount: relatedLogs.count,
            progressCount: relatedProgress.count,
            photoCount: relatedLogs.flatMap(\.photoAttachments).count,
            logsDestination: AnyView(List { logSections }),
            progressDestination: AnyView(List { progressSections }),
            photoDestination: AnyView(List { photoSections })
        )
    }

    private func financeHubSections(project: Project) -> some View {
        ProjectFinanceHubSectionView(
            financialCount: relatedFinancialRecords.count,
            quoteCount: relatedQuotes.count,
            materialCount: relatedMaterials.count,
            laborCount: relatedLabor.count,
            warehouseCount: relatedWarehouseMovements.count,
            bookDestination: projectBookkeepingDestination,
            quoteDestination: AnyView(List { quoteSections }),
            materialDestination: AnyView(List { materialSections }),
            laborDestination: AnyView(List { laborSections }),
            warehouseDestination: AnyView(ProjectWarehouseView(project: project)),
            legacyPaymentsCount: legacyPayments.count,
            onMigrateLegacyPayments: { migrateLegacyPayments(project: project) }
        )
    }

    private var assetHubSections: some View {
        ProjectAssetHubSectionView(
            drawingCount: relatedDrawings.count,
            documentCount: relatedDocuments.count,
            contactCount: relatedContacts.count,
            drawingDestination: AnyView(List { drawingSections }),
            documentDestination: projectDocumentDestination,
            contactDestination: projectContactDestination
        )
    }

    private var projectBookkeepingDestination: AnyView {
        AnyView(
            ProjectDetailPrimaryActionList(
                title: "新增账目",
                systemImage: "plus.circle.fill",
                tint: .pink,
                action: { showFinancialAdd = true }
            ) {
                projectBookkeepingSection
            }
        )
    }

    private var projectDocumentDestination: AnyView {
        AnyView(
            ProjectDetailPrimaryActionList(
                title: "扫描并添加资料",
                systemImage: "viewfinder",
                tint: .brown,
                action: { showDocumentScanSetup = true }
            ) {
                projectDocumentSections
            }
        )
    }

    private var projectContactDestination: AnyView {
        AnyView(
            ProjectDetailPrimaryActionList(
                title: "添加联系人",
                systemImage: "person.crop.circle.badge.plus",
                tint: .blue,
                action: { showContactAdd = true }
            ) {
                contactSections
            }
        )
    }

    private var logSections: some View {
        ProjectLogSectionView(
            logs: relatedLogs,
            onAddLog: { showSheet = .log },
            logRow: { log in ProjectDetailLogRowView(log: log) }
        )
    }

    private var materialSections: some View {
        ProjectMaterialSectionView(
            items: relatedMaterials,
            useMetric: useMetric,
            onAdd: { showSheet = .material },
            onEdit: { editingMaterial = $0 }
        )
    }

    private var quoteSections: some View {
        ProjectQuoteSectionView(
            items: relatedQuotes,
            onAdd: { showSheet = .quote },
            onEdit: { editingQuote = $0 }
        )
    }

    private var laborSections: some View {
        ProjectLaborSectionView(
            items: relatedLabor,
            onAdd: { showSheet = .labor },
            onEdit: { editingLabor = $0 }
        )
    }

    private var progressSections: some View {
        ProjectProgressSectionView(tasks: relatedProgress) { editingProgress = $0 }
    }

    private var photoSections: some View {
        ProjectPhotoSectionView(logs: relatedLogs) { selectedPhotoContext = $0 }
    }

    private var drawingSections: some View {
        ProjectDrawingSectionView(
            drawingFilter: $drawingFilter,
            relatedDrawings: relatedDrawings,
            filteredDrawings: filteredDrawings,
            icon: ProjectDetailDrawingHelper.drawingIcon(_:),
            onImportDrawing: { showDrawingImporter = true },
            onEdit: { editingDrawing = $0 },
            onTimeline: { timelineContext = DrawingTimelineContext(name: $0.name) },
            onPreview: previewDrawing(_:),
            onDelete: deleteDrawing(_:)
        )
    }

    private var contactSections: some View {
        ProjectContactsView(
            contacts: relatedContacts,
            onAdd: { showContactAdd = true },
            onEdit: { editingContact = $0 }
        ) { ids in
            store.projectContacts.removeAll { ids.contains($0.id) }
            store.scheduleSave()
        }
    }

    private var projectBookkeepingSection: some View {
        ProjectBookkeepingView(
            records: relatedFinancialRecords,
            linkedDocuments: linkedDocuments(for:),
            onEdit: { editingFinancialRecord = $0 },
            onDelete: deleteFinancialRecords(ids:),
            onAddRecord: { showFinancialAdd = true }
        )
    }

    private var projectDocumentSections: some View {
        Group {
            ProjectDetailDocumentActionSection(
                selectedPhotoItem: $selectedPhotoItem,
                imagePickerSource: $imagePickerSource,
                showImagePicker: $showImagePicker,
                showDocumentScanSetup: $showDocumentScanSetup,
                showDocumentFileImporter: $showDocumentFileImporter
            )
            ProjectDocumentsView(
                documents: relatedDocuments,
                icon: ProjectDetailFinanceDocumentHelper.documentIcon(_:),
                onOpen: { editingDocument = $0 }
            )
        }
    }

    private func paidAmount(_ project: Project) -> Double {
        ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: relatedFinancialRecords,
            legacyPayments: legacyPayments
        )
    }

    private func unpaidAmount(_ project: Project) -> Double {
        ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paidAmount(project))
    }

    private func currentMaterialCost(_ project: Project) -> Double {
        ProjectDetailMetrics.currentMaterialCost(project: project, materialCostAuto: materialCostAuto)
    }

    private func currentLaborCost(_ project: Project) -> Double {
        ProjectDetailMetrics.currentLaborCost(project: project, laborCostAuto: laborCostAuto)
    }

    private func estimatedProfit(_ project: Project) -> Double {
        ProjectDetailMetrics.estimatedProfit(
            project: project,
            materialCost: currentMaterialCost(project),
            laborCost: currentLaborCost(project)
        )
    }

    private func scanTarget(for record: ProjectFinancialRecord) -> ProjectScanTarget {
        ProjectScanTarget(
            title: "\(record.category)-\(record.date)",
            category: ProjectDetailFinanceDocumentHelper.documentCategory(for: record.category),
            amount: record.amount,
            linkedFinancialRecordId: record.id,
            note: record.note
        )
    }

    private func requestExportProjectPackage(_ project: Project) {
        switch ProjectDetailExportWorkflow.packageRequestDecision(
            documents: relatedDocuments,
            drawings: relatedDrawings,
            logs: relatedLogs,
            quickNotes: relatedQuickNotes
        ) {
        case .proceed:
            exportProjectPackage(project)
        case .warn(let warningMessage):
            exportState.pendingPackageProject = project
            exportState.packageSizeWarningMessage = warningMessage
            exportState.showPackageSizeWarning = true
        case .reject(let errorMessage):
            presentImportError(errorMessage)
        }
    }

    private func exportProjectPackage(_ project: Project) {
        exportState.projectPackageExportTask?.cancel()
        exportState.isExportingProjectPackage = true
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")

        exportState.projectPackageExportTask = ProjectDetailExportWorkflow.makeProjectPackageExportTask(
            project: project,
            projectId: projectId,
            materials: relatedMaterials,
            quotes: relatedQuotes,
            labor: relatedLabor,
            logs: relatedLogs,
            tasks: relatedProgress,
            todos: store.siteTodos,
            drawings: relatedDrawings,
            contacts: relatedContacts,
            financialRecords: relatedFinancialRecords,
            documents: relatedDocuments,
            quickNotes: relatedQuickNotes,
            paidAmountOverride: paidAmount(project),
            onProgress: { progress in
                exportState.projectPackageExportProgress = progress
            },
            onCancelled: {
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
            },
            onCompletion: { result in
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
                switch result {
                case .success(let payload):
                    exportState.exportPayload = payload
                    exportState.showExporter = true
                case .failure(let message):
                    if message != ProjectPackageArchiveError.cancelled.localizedDescription {
                        presentImportError(message)
                    }
                }
            }
        )
    }

    private func cancelProjectPackageExport() {
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(
            completedSteps: exportState.projectPackageExportProgress.completedSteps,
            totalSteps: max(exportState.projectPackageExportProgress.totalSteps, 1),
            currentItem: "正在取消..."
        )
        exportState.projectPackageExportTask?.cancel()
    }

    private func exportDailyReport(_ project: Project) {
        exportState.exportPayload = ProjectDetailExportWorkflow.makeDailyReportExport(project: project, logs: relatedLogs)
        exportState.showExporter = true
    }

    private func averageProgress(_ tasks: [ProgressTask]) -> Double {
        ProjectDetailMetrics.averageProgress(tasks)
    }

    private func trim(_ value: Double) -> String {
        ProjectDetailMetrics.trim(value)
    }

    private func updateProject(_ updated: Project) {
        guard let idx = store.projects.firstIndex(where: { $0.id == updated.id }) else { return }
        store.projects[idx] = updated
        store.scheduleSave()
    }

    private func saveMaterial(_ updated: MaterialItem) {
        if let index = store.materialItems.firstIndex(where: { $0.id == updated.id }) {
            store.materialItems[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteMaterial(id: UUID) {
        store.materialItems.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveQuote(_ updated: QuoteItem) {
        if let index = store.quoteItems.firstIndex(where: { $0.id == updated.id }) {
            store.quoteItems[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteQuote(id: UUID) {
        store.quoteItems.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveLabor(_ updated: LaborRecord) {
        if let index = store.laborRecords.firstIndex(where: { $0.id == updated.id }) {
            store.laborRecords[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteLabor(_ target: LaborRecord) {
        store.laborRecords.removeAll { $0.id == target.id }
        store.scheduleSave()
    }

    private func saveProgress(_ updated: ProgressTask) {
        if let index = store.progressTasks.firstIndex(where: { $0.id == updated.id }) {
            store.progressTasks[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteProgress(id: UUID) {
        store.progressTasks.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveFinancialRecord(_ updated: ProjectFinancialRecord) {
        if let index = store.projectFinancialRecords.firstIndex(where: { $0.id == updated.id }) {
            store.projectFinancialRecords[index] = updated
            store.scheduleSave()
        }
    }

    private func updateProjectPhoto(context: ProjectPhotoContext, note: String, tag: String) {
        guard let logIndex = store.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = store.dailyLogs[logIndex]
        if let photoIndex = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            log.photos[photoIndex].note = note
            log.photos[photoIndex].tag = tag
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            log.photos.append(LogPhoto(fileName: legacy, note: note, tag: tag))
        }
        store.dailyLogs[logIndex] = log
        store.scheduleSave()
    }

    private func deleteProjectPhoto(context: ProjectPhotoContext) {
        guard let logIndex = store.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = store.dailyLogs[logIndex]
        if let index = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            let fileName = log.photos[index].fileName
            PhotoStorage.delete(fileName: fileName)
            log.photos.remove(at: index)
            if log.photoFileName == fileName {
                log.photoFileName = log.photos.first?.fileName
            }
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            PhotoStorage.delete(fileName: legacy)
            log.photoFileName = nil
        }
        store.dailyLogs[logIndex] = log
        store.scheduleSave()
    }

    private func importDrawings(_ urls: [URL]) {
        var importedCount = 0
        var failedNames: [String] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
                failedNames.append(url.lastPathComponent)
                continue
            }
            let drawing: ProjectDrawing
            do {
                drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
            } catch {
                failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
                continue
            }
            let nextVersion = ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: relatedDrawings)
            var versioned = drawing
            versioned.version = nextVersion
            versioned.isCurrentVersion = true
            ProjectDetailAssetActions.updateCurrentVersionFlags(for: versioned, store: store)
            store.projectDrawings.append(versioned)
            importedCount += 1
        }
        if importedCount > 0 {
            store.scheduleSave()
        }
        if !failedNames.isEmpty {
            importErrorMessage = "以下文件导入失败：\(failedNames.joined(separator: "、"))"
            showImportError = true
        } else if importedCount == 0 {
            importErrorMessage = "没有可导入的图纸文件，请选择 PDF / DWG / DXF。"
            showImportError = true
        }
    }

    private func saveScannedDocument(target: ProjectScanTarget, data: Data, pageCount: Int) {
        if let error = ProjectDetailAssetActions.saveScannedDocument(
            target: target,
            data: data,
            pageCount: pageCount,
            projectId: projectId,
            store: store
        ) {
            presentImportError(error)
        }
    }

    private func previewDocument(_ document: ProjectDocument) {
        switch ProjectDetailAssetActions.previewDocumentURL(for: document) {
        case .success(let url):
            quickLookURL = url
        case .failure(let message):
            presentImportError(message)
        }
    }

    private func deleteDocument(_ document: ProjectDocument) {
        ProjectDetailAssetActions.deleteDocument(document, store: store)
    }

    private func saveDocumentEdit(_ document: ProjectDocument) {
        ProjectDetailAssetActions.saveDocumentEdit(document, store: store)
    }

    private func requestDeleteFinancialRecord(_ record: ProjectFinancialRecord) {
        requestDeleteFinancialRecords(ids: Set([record.id]))
    }

    private func deleteFinancialRecords(ids: Set<UUID>) {
        requestDeleteFinancialRecords(ids: ids)
    }

    private func requestDeleteFinancialRecords(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteFinancialRecordIDs = ids
        showFinancialDeleteConfirm = true
    }

    private func performDeleteFinancialRecords(deleteLinkedDocuments: Bool) {
        let ids = pendingDeleteFinancialRecordIDs
        pendingDeleteFinancialRecordIDs.removeAll()
        guard !ids.isEmpty else { return }
        ProjectDetailFinanceDocumentActions.deleteFinancialRecords(
            ids: ids,
            deleteLinkedDocuments: deleteLinkedDocuments,
            store: store
        )
    }

    private func migrateLegacyPayments(project: Project) {
        ProjectDetailFinanceDocumentActions.migrateLegacyPayments(project: project, legacyPayments: legacyPayments, store: store)
    }

    private func linkedDocuments(for record: ProjectFinancialRecord) -> [ProjectDocument] {
        ProjectDetailFinanceDocumentActions.linkedDocuments(for: record, documents: store.projectDocuments)
    }

    private func importProjectDocuments(_ urls: [URL], linkedFinancialRecordId: UUID? = nil) {
        let failures = ProjectDetailAssetActions.importProjectDocuments(
            urls,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        )
        if !failures.isEmpty {
            presentImportError("以下资料导入失败：\(failures.joined(separator: "、"))")
        }
    }

    private func importPhotoItem(_ item: PhotosPickerItem, linkedFinancialRecordId: UUID? = nil) async {
        let result = await ProjectDetailFinanceDocumentActions.image(from: item)
        await MainActor.run {
            switch result {
            case .success(let image):
                importCapturedImage(image, note: "来源: 相册", linkedFinancialRecordId: linkedFinancialRecordId)
            case .failure(let message):
                presentImportError(message)
            }
        }
    }

    private func importCapturedImage(_ image: UIImage, note: String = "来源: 拍照", linkedFinancialRecordId: UUID? = nil) {
        if let error = ProjectDetailAssetActions.importCapturedImage(
            image,
            note: note,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        ) {
            presentImportError(error)
        }
    }

    private func presentImportError(_ message: String) {
        importErrorMessage = message
        showImportError = true
    }

    private func handleOnAppear() {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            didAutoOpenFinancialAdd: didAutoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            didAutoOpenDocumentScanSetup: didAutoOpenDocumentScanSetup,
            focus: focus,
            didOpenFocusedItem: didOpenFocusedItem,
            financialRecords: relatedFinancialRecords,
            documents: relatedDocuments,
            contacts: relatedContacts
        )
        if routing.shouldOpenFinancialAdd {
            didAutoOpenFinancialAdd = true
            detailMode = .finance
            showFinancialAdd = true
        }
        if routing.shouldOpenDocumentScanSetup {
            didAutoOpenDocumentScanSetup = true
            detailMode = .assets
            showDocumentScanSetup = true
        }
        if routing.shouldConsumeFocusRequest {
            didOpenFocusedItem = true
            guard let focusedItem = routing.focusedItem else { return }
            detailMode = focusedItem.mode
            DispatchQueue.main.async {
                ProjectDetailFocusedItemApplier.apply(
                    focusedItem,
                    setFinancialRecord: { editingFinancialRecord = $0 },
                    setDocument: { editingDocument = $0 },
                    setContact: { editingContact = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private func attachmentSheet(record: ProjectFinancialRecord) -> some View {
        ProjectFinancialAttachmentSheet(
            record: record,
            documents: relatedDocuments,
            onDetach: { document in
                ProjectDetailFinanceDocumentActions.detachDocument(document, from: record, store: store)
            },
            onAttach: { document in
                ProjectDetailFinanceDocumentActions.attachDocument(document, to: record, store: store)
            },
            onBulkSetCategory: { documents, category in
                let ids = Set(documents.map(\.id))
                for index in store.projectDocuments.indices where ids.contains(store.projectDocuments[index].id) {
                    store.projectDocuments[index].category = category.rawValue
                }
                store.scheduleSave()
            },
            onScan: {
                scanTarget = scanTarget(for: record)
            },
            onImportFiles: { urls in
                importProjectDocuments(urls, linkedFinancialRecordId: record.id)
            },
            onImportImage: { image, note in
                importCapturedImage(image, note: note, linkedFinancialRecordId: record.id)
            }
        )
    }

    private func saveDrawing(_ updated: ProjectDrawing) {
        ProjectDetailAssetActions.saveDrawing(updated, store: store)
    }

    private func saveContact(_ updated: ProjectContact) {
        if let index = store.projectContacts.firstIndex(where: { $0.id == updated.id }) {
            store.projectContacts[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteContact(_ target: ProjectContact) {
        store.projectContacts.removeAll { $0.id == target.id }
        store.scheduleSave()
    }

    private func setDrawingAsCurrentVersion(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.setDrawingAsCurrentVersion(drawing, store: store)
    }

    private func previewDrawing(_ drawing: ProjectDrawing) {
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing) {
        case .success(let url):
            quickLookURL = url
        case .failure(let message):
            presentImportError(message)
        }
    }

    private func deleteDrawing(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.deleteDrawing(drawing, store: store)
    }

    private func timelineDrawings(name: String) -> [ProjectDrawing] {
        ProjectDetailAssetActions.timelineDrawings(name: name, relatedDrawings: relatedDrawings)
    }
}

enum DetailSheet: String, Identifiable {
    case material, quote, log, labor
    var id: String { rawValue }
}
