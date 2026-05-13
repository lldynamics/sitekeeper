import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import VisionKit
import PhotosUI

struct ProjectDetailView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) private var financeStore
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    let projectId: UUID
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool
    let autoOpenDeliveryGuide: Bool

    @State private var exportState = ProjectDetailExportStateModel()
    @State private var routeState: ProjectDetailRouteState
    @State private var financeState = ProjectDetailFinanceState()
    @State var assetState = ProjectDetailAssetState()

    @State private var didAutoOpenFinancialAdd = false
    @State private var didAutoOpenDocumentScanSetup = false
    @State private var didAutoOpenDeliveryGuide = false
    @State private var didOpenFocusedItem = false
    @State private var showTodoFilterView = false

    init(
        projectId: UUID,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false
    ) {
        self.projectId = projectId
        self.focus = focus
        self.autoOpenFinancialAdd = autoOpenFinancialAdd
        self.autoOpenDocumentScanSetup = autoOpenDocumentScanSetup
        self.autoOpenDeliveryGuide = autoOpenDeliveryGuide
        _routeState = State(initialValue: ProjectDetailRouteState(mode: initialMode ?? .overview))
    }

    private static let drawingImportTypes: [UTType] = {
        var types: [UTType] = [.pdf, .zip]
        if let dwg = UTType(filenameExtension: "dwg") {
            types.append(dwg)
        }
        if let dxf = UTType(filenameExtension: "dxf") {
            types.append(dxf)
        }
        // Fallback for file providers that cannot surface DWG/DXF UTTypes reliably.
        if !types.contains(.item) {
            types.append(.item)
        }
        return types
    }()
    private static let documentImportTypes: [UTType] = [.item]

    private var project: Project? { projectStore.projects.first { $0.id == projectId } }
    private var projectSnapshot: ProjectDetailSnapshot? {
        guard let project else { return nil }
        return ProjectDetailSnapshot(
            project: project,
            projectId: projectId,
            projectStore: projectStore,
            financeStore: financeStore
        )
    }

    private var usesSingleCanvasLayoutOnPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var drawingImportConflictDialogMessage: String {
        let names = assetState.drawingImportConflictNames
        guard !names.isEmpty else {
            return String(localized: "检测到同名图纸，请选择导入策略。")
        }
        let preview = names.prefix(3).joined(separator: "、")
        if names.count > 3 {
            return String(localized: "检测到同名图纸：\(preview) 等 \(names.count) 项，请选择导入策略。")
        }
        return String(localized: "检测到同名图纸：\(preview)，请选择导入策略。")
    }

    private var editingMaterialBinding: Binding<MaterialItem?> {
        Binding(
            get: {
                guard case .material(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .material(item)
                case (.material, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    private var editingQuoteBinding: Binding<QuoteItem?> {
        Binding(
            get: {
                guard case .quote(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .quote(item)
                case (.quote, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    private var editingLaborBinding: Binding<LaborRecord?> {
        Binding(
            get: {
                guard case .labor(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .labor(item)
                case (.labor, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    private var editingProgressBinding: Binding<ProgressTask?> {
        Binding(
            get: {
                guard case .progress(let item) = routeState.editingRoute else { return nil }
                return item
            },
            set: { value in
                switch (routeState.editingRoute, value) {
                case (_, .some(let item)):
                    routeState.editingRoute = .progress(item)
                case (.progress, .none):
                    routeState.editingRoute = nil
                default:
                    break
                }
            }
        )
    }

    var body: some View {
        Group {
            if let snapshot = projectSnapshot {
                content(snapshot: snapshot)
            } else {
                ContentUnavailableView("项目不存在", systemImage: "questionmark.folder")
            }
        }
    }

    private func content(snapshot: ProjectDetailSnapshot) -> some View {
        let project = snapshot.project
        let statusBinding = Binding(
            get: { project.status },
            set: { newVal in
                if let idx = projectStore.projects.firstIndex(where: { $0.id == projectId }) {
                    store.projects[idx].status = newVal
                    store.scheduleSave()
                }
            }
        )

        return GeometryReader { proxy in
            detailScaffold(
                snapshot: snapshot,
                statusBinding: statusBinding,
                availableWidth: proxy.size.width
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        routeState.presentation = .editProject
                    } label: {
                        Label("编辑资料", systemImage: "square.and.pencil")
                    }
                    Button {
                        routeState.presentation = .deliveryGuide
                    } label: {
                        Label("完工交付向导", systemImage: "checklist.checked")
                    }
                    Button {
                        requestExportProjectPackage(project, snapshot: snapshot)
                    } label: {
                        Label("导出项目交付包 ZIP", systemImage: "archivebox.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel("导出与交付")
            }
        }
        .projectDetailExportHost(
            exportPayload: $exportState.exportPayload,
            showExporter: $exportState.showExporter,
            pendingPackageProject: $exportState.pendingPackageProject,
            packageSizeWarningMessage: $exportState.packageSizeWarningMessage,
            showPackageSizeWarning: $exportState.showPackageSizeWarning,
            onContinuePackageExport: { exportProjectPackage($0, snapshot: snapshot) }
        )
        .projectDetailEntrySheetCoordinator(
            project: project,
            projectId: projectId,
            presentation: $routeState.presentation,
            financialAddSeed: $financeState.financialAddSeed,
            imagePickerSource: $assetState.imagePickerSource,
            deliveryGuideData: deliveryGuideData(snapshot: snapshot),
            constructionMethods: store.constructionMethods,
            recentFinancialRecords: snapshot.relatedFinancialRecords,
            onOpenModeFromDeliveryGuide: { mode in
                routeState.mode = mode
                focusModeInSingleCanvas(mode)
            },
            onStartDeliveryExport: {
                requestExportProjectPackage(project, snapshot: snapshot)
            },
            onUpdateProject: updateProject(_:),
            onCreateContact: { contact in
                store.projectContacts.append(contact)
                store.scheduleSave()
            },
            onCreateFinancialRecord: { record, shouldScan in
                store.projectFinancialRecords.append(record)
                if shouldScan {
                    assetState.scanTarget = scanTarget(for: record)
                }
                store.scheduleSave()
            },
            onCreateScanTarget: { target in
                assetState.scanTarget = target
            },
            onImportCapturedImage: { image in
                importCapturedImage(image)
            }
        )
        .projectDetailEditingSheetCoordinator(
            editingMaterial: editingMaterialBinding,
            editingQuote: editingQuoteBinding,
            editingLabor: editingLaborBinding,
            editingProgress: editingProgressBinding,
            selectedPhotoContext: $assetState.selectedPhotoContext,
            editingDrawing: $assetState.editingDrawing,
            editingDocument: $assetState.editingDocument,
            editingContact: $assetState.editingContact,
            editingFinancialRecord: $financeState.editingFinancialRecord,
            attachmentManagingRecord: $financeState.attachmentManagingRecord,
            timelineContext: $assetState.timelineContext,
            dependencies: ProjectDetailEditingCoordinatorDependencies(
                useMetric: useMetric,
                projects: projectStore.projects,
                constructionMethods: store.constructionMethods,
                relatedLogs: snapshot.relatedLogs,
                relatedDrawings: snapshot.relatedDrawings,
                relatedFinancialRecords: snapshot.relatedFinancialRecords,
                linkedDocuments: linkedDocuments(for:),
                attachmentSheetBuilder: { record in
                    attachmentSheet(record: record, documents: snapshot.relatedDocuments)
                },
                timelineDrawings: { name in
                    timelineDrawings(name: name, drawings: snapshot.relatedDrawings)
                }
            ),
            handlers: ProjectDetailEditingCoordinatorHandlers(
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
                    assetState.scanTarget = scanTarget(for: target)
                },
                onManageAttachments: { target in
                    financeState.attachmentManagingRecord = target
                },
                onSetDrawingCurrentVersion: setDrawingAsCurrentVersion(_:),
                onEditDrawingFromTimeline: { drawing in
                    assetState.editingDrawing = drawing
                }
            )
        )
        .projectDetailImportFlowCoordinator(
            showDrawingImporter: $assetState.showDrawingImporter,
            drawingImportTypes: Self.drawingImportTypes,
            onImportDrawings: importDrawings(_:),
            showDocumentFileImporter: $assetState.showDocumentFileImporter,
            documentImportTypes: Self.documentImportTypes,
            onImportDocuments: { urls in
                importProjectDocuments(urls)
            },
            selectedPhotoItem: $assetState.selectedPhotoItem,
            onImportPhotoItem: { item in
                await importPhotoItem(item)
            },
            quickLookURL: $assetState.quickLookURL,
            scanTarget: $assetState.scanTarget,
            onSaveScannedDocument: saveScannedDocument(target:data:pageCount:),
            onPresentImportError: presentImportError(_:),
            showImportError: $assetState.showImportError,
            importErrorMessage: $assetState.importErrorMessage
        )
        .fullScreenCover(item: $assetState.cadPreviewRequest) { request in
            ProjectCADPreviewView(request: request)
        }
        .onAppear {
            handleOnAppear(snapshot: snapshot)
            if usesSingleCanvasLayoutOnPad {
                focusModeInSingleCanvas(routeState.mode)
            }
        }
        .onChange(of: routeState.mode) { _, newValue in
            if newValue != .finance {
                routeState.financeJumpFilter = .none
            }
            if usesSingleCanvasLayoutOnPad {
                focusModeInSingleCanvas(newValue)
            }
        }
        .onDisappear {
            exportState.cancelExportTask()
        }
        .navigationDestination(isPresented: $showTodoFilterView) {
            SiteTodoView(initialProjectId: projectId)
                .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("删除账目", isPresented: $financeState.showFinancialDeleteConfirm, titleVisibility: .visible) {
            Button("仅删除账目（保留票据）", role: .destructive) {
                performDeleteFinancialRecords(deleteLinkedDocuments: false)
            }
            Button("删除账目并删除票据", role: .destructive) {
                performDeleteFinancialRecords(deleteLinkedDocuments: true)
            }
            Button("取消", role: .cancel) {
                financeState.pendingDeleteFinancialRecordIDs.removeAll()
            }
        } message: {
            Text(String(format: String(localized: "将删除 %d 条账目。可选择保留票据为项目资料。"), financeState.pendingDeleteFinancialRecordIDs.count))
        }
        .confirmationDialog("同名图纸导入策略", isPresented: $assetState.showDrawingImportStrategyDialog, titleVisibility: .visible) {
            ForEach(ProjectDrawingImportStrategy.allCases) { strategy in
                Button(strategy.displayName) {
                    applyPendingDrawingImportStrategy(strategy)
                }
            }
            Button("取消", role: .cancel) {
                clearPendingDrawingImportStrategy()
            }
        } message: {
            Text(drawingImportConflictDialogMessage)
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
    private func detailScaffold(snapshot: ProjectDetailSnapshot, statusBinding: Binding<ProjectStatus>, availableWidth: CGFloat) -> some View {
        let usesSinglePageLayout = usesInlineDetailLayout(for: availableWidth)
        ProjectDetailContentView(
            isWide: usesSinglePageLayout,
            scrollRequest: routeState.anchorRequest,
            jumpBar: {
                EmptyView()
            },
            header: {
                projectHeader(
                    snapshot: snapshot,
                    statusBinding: statusBinding,
                    showsStatus: usesSinglePageLayout || routeState.mode == .overview
                )
            },
            quickActions: {
                quickActionSection
            },
            modePicker: {
                modePickerSection(prefersInlineSections: usesSinglePageLayout)
            },
            content: {
                detailContent(
                    snapshot: snapshot,
                    prefersInlineSections: usesSinglePageLayout,
                    showsAllSections: usesSinglePageLayout
                )
            }
        )
    }

    private func modePickerSection(prefersInlineSections: Bool) -> some View {
        let modeBinding = Binding<ProjectDetailMode>(
            get: { routeState.mode },
            set: { newMode in
                routeState.mode = newMode
                if prefersInlineSections {
                    requestAnchorScroll(anchor(for: newMode))
                }
            }
        )
        return Section {
            Picker("内容", selection: modeBinding) {
                ForEach(ProjectDetailMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func projectHeader(snapshot: ProjectDetailSnapshot, statusBinding: Binding<ProjectStatus>, showsStatus: Bool) -> some View {
        let project = snapshot.project
        let paidAmountValue = ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
        let unpaidAmountValue = ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paidAmountValue)
        return ProjectDetailHeaderSection(
            project: project,
            status: statusBinding,
            progressValue: "\(Int(averageProgress(snapshot.relatedProgress) * 100))%",
            quoteValue: ReportBuilder.money(snapshot.quoteTotal),
            todoValue: "\(snapshot.openTodoCount)",
            unpaidAmount: unpaidAmountValue,
            riskStrip: ProjectDetailRiskStripView(
                overdueCount: snapshot.overdueProgressCount + snapshot.overdueTodoCount,
                unpaidAmount: unpaidAmountValue,
                unpricedQuoteCount: snapshot.unpricedQuoteCount,
                hasTodayLog: snapshot.hasTodayLog
            ),
            customerLine: (!project.customerName.isEmpty || !project.customerPhone.isEmpty)
                ? "客户: \(project.customerName) \(project.customerPhone)"
                : nil,
            periodLine: (!project.startDate.isEmpty || !project.expectedEndDate.isEmpty)
                ? "工期: \(project.startDate.isEmpty ? "未填写" : project.startDate) 至 \(project.expectedEndDate.isEmpty ? "未填写" : project.expectedEndDate)"
                : nil,
            showsStatus: showsStatus,
            onOpenRecords: openRecordsModeFromMetric,
            onOpenFinanceFromQuote: openFinanceModeFromQuoteMetric,
            onOpenTodoFilter: openTodoFilterFromMetric,
            onOpenFinanceFromUnpaid: { openFinanceModeFromMetric(filter: .none) },
            onEditProject: { routeState.presentation = .editProject },
            canExportDeliveryPackage: project.status == .completed || project.status == .settled,
            onExportDeliveryPackage: { routeState.presentation = .deliveryGuide }
        )
    }

    private var quickActionSection: some View {
        ProjectDetailQuickActionSection(
            onAddLog: { routeState.presentation = .quickAdd(.log) },
            onAddFinance: { routeState.presentation = .addFinancial },
            onAddContact: { routeState.presentation = .addContact },
            onImportDrawing: { assetState.showDrawingImporter = true },
            onAddMaterial: { routeState.presentation = .quickAdd(.material) },
            onAddQuote: { routeState.presentation = .quickAdd(.quote) },
            onAddLabor: { routeState.presentation = .quickAdd(.labor) }
        )
    }

    @ViewBuilder
    private func detailContent(snapshot: ProjectDetailSnapshot, prefersInlineSections: Bool, showsAllSections: Bool) -> some View {
        let project = snapshot.project
        let paidAmountValue = ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
        let materialCostValue = ProjectDetailMetrics.currentMaterialCost(
            project: project,
            materialCostAuto: snapshot.materialCostAuto
        )
        let laborCostValue = ProjectDetailMetrics.currentLaborCost(
            project: project,
            laborCostAuto: snapshot.laborCostAuto
        )
        ProjectDetailModeSectionsView(
            mode: routeState.mode,
            project: project,
            useMetric: useMetric,
            paidAmount: paidAmountValue,
            unpaidAmount: ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paidAmountValue),
            materialCost: materialCostValue,
            laborCost: laborCostValue,
            estimatedProfit: ProjectDetailMetrics.estimatedProfit(
                project: project,
                materialCost: materialCostValue,
                laborCost: laborCostValue
            ),
            laborHours: trim(snapshot.laborHoursTotal),
            projectBookIncome: snapshot.projectBookIncome,
            projectBookExpense: snapshot.projectBookExpense,
            relatedMaterials: snapshot.relatedMaterials,
            relatedQuotes: snapshot.relatedQuotes,
            relatedLabor: snapshot.relatedLabor,
            relatedWarehouseMovements: snapshot.relatedWarehouseMovements,
            relatedLogs: snapshot.relatedLogs,
            relatedProgress: snapshot.relatedProgress,
            relatedDrawings: snapshot.relatedDrawings,
            relatedContacts: snapshot.relatedContacts,
            allProjectContacts: projectStore.projectContacts,
            constructionMethods: store.constructionMethods,
            supplierProfiles: store.supplierProfiles,
            allProjects: projectStore.projects,
            allFinancialRecords: projectStore.projectFinancialRecords,
            relatedFinancialRecords: snapshot.relatedFinancialRecords,
            allDocuments: projectStore.projectDocuments,
            relatedDocuments: snapshot.relatedDocuments,
            relatedQuickNotes: snapshot.relatedQuickNotes,
            relatedTodos: snapshot.relatedTodos,
            filteredDrawings: snapshot.filteredDrawings(for: routeState.drawingFilter),
            financeJumpFilter: routeState.financeJumpFilter,
            prefersInlineSections: prefersInlineSections,
            showsAllSections: showsAllSections,
            drawingFilter: $routeState.drawingFilter,
            selectedPhotoItem: $assetState.selectedPhotoItem,
            showDocumentFileImporter: $assetState.showDocumentFileImporter,
            onAddLog: { routeState.presentation = .quickAdd(.log) },
            onAddMaterial: { routeState.presentation = .quickAdd(.material) },
            onAddQuote: { routeState.presentation = .quickAdd(.quote) },
            onAddLabor: { routeState.presentation = .quickAdd(.labor) },
            onAddFinancialRecord: { routeState.presentation = .addFinancial },
            onAddContact: { routeState.presentation = .addContact },
            onImportDrawing: { assetState.showDrawingImporter = true },
            onOpenMode: { openMode($0, prefersInlineSections: prefersInlineSections) },
            onOpenFinanceFilter: openFinanceModeFromMetric(filter:),
            onOpenTodoFilter: openTodoFilterFromMetric,
            onOpenTimelineItem: { item in
                openMode(item.targetMode, prefersInlineSections: prefersInlineSections)
            },
            onScanDocument: { routeState.presentation = .documentScanSetup },
            onCaptureDocumentPhoto: {
                assetState.imagePickerSource = .camera
                routeState.presentation = .imagePicker
            },
            onEditMaterial: { routeState.editingRoute = .material($0) },
            onEditQuote: { routeState.editingRoute = .quote($0) },
            onEditLabor: { routeState.editingRoute = .labor($0) },
            onEditProgress: { routeState.editingRoute = .progress($0) },
            onOpenPhotoContext: { assetState.selectedPhotoContext = $0 },
            onEditDrawing: { assetState.editingDrawing = $0 },
            onShowDrawingTimeline: { assetState.timelineContext = DrawingTimelineContext(name: $0) },
            onPreviewDrawing: previewDrawing(_:),
            onDeleteDrawing: deleteDrawing(_:),
            onEditContact: { assetState.editingContact = $0 },
            onDeleteContacts: { ids in
                ids.forEach { removeContactAssociation(contactID: $0, from: projectId) }
                store.scheduleSave()
            },
            onEditFinancialRecord: { financeState.editingFinancialRecord = $0 },
            onDeleteFinancialRecords: deleteFinancialRecords(ids:),
            onOpenDocument: { assetState.editingDocument = $0 },
            onLinkDocumentToFinancialRecord: linkDocument(_:to:),
            linkedDocuments: linkedDocuments(for:),
            onResetFinanceJumpFilter: resetFinanceJumpFilter
        )
    }

    private func openRecordsModeFromMetric() {
        openMode(.records, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    private func openFinanceModeFromQuoteMetric() {
        openFinanceModeFromMetric(filter: .none)
    }

    private func openTodoFilterFromMetric() {
        showTodoFilterView = true
    }

    private func openFinanceModeFromMetric(filter: ProjectFinanceJumpFilter) {
        routeState.financeJumpFilter = filter
        openMode(.finance, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    private func resetFinanceJumpFilter() {
        routeState.financeJumpFilter = .none
    }

    private func openMode(_ mode: ProjectDetailMode, prefersInlineSections: Bool) {
        if prefersInlineSections {
            routeState.mode = mode
            requestAnchorScroll(anchor(for: mode))
            return
        }
        routeState.mode = mode
    }

    private func requestAnchorScroll(_ anchor: ProjectDetailAnchor) {
        routeState.anchorRequest = ProjectDetailAnchorRequest(anchor: anchor)
    }

    private func focusModeInSingleCanvas(_ mode: ProjectDetailMode) {
        guard mode != .overview else { return }
        requestAnchorScroll(anchor(for: mode))
    }

    private func anchor(for mode: ProjectDetailMode) -> ProjectDetailAnchor {
        switch mode {
        case .overview:
            .overview
        case .records:
            .records
        case .assets:
            .assets
        case .finance:
            .finance
        case .timeline:
            .timeline
        }
    }

    private func usesInlineDetailLayout(for availableWidth: CGFloat) -> Bool {
        _ = availableWidth
        return usesSingleCanvasLayoutOnPad
    }

    private func paidAmount(_ project: Project, snapshot: ProjectDetailSnapshot) -> Double {
        ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
    }

    private func requestExportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        switch ProjectDetailExportWorkflow.packageRequestDecision(
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        ) {
        case .proceed:
            exportProjectPackage(project, snapshot: snapshot)
        case .warn(let warningMessage):
            exportState.pendingPackageProject = project
            exportState.packageSizeWarningMessage = warningMessage
            exportState.showPackageSizeWarning = true
        case .reject(let errorMessage):
            presentImportError(errorMessage)
        }
    }

    private func deliveryGuideData(snapshot: ProjectDetailSnapshot) -> ProjectDeliveryGuideData {
        ProjectDeliveryGuideData(
            projectName: snapshot.project.name,
            logCount: snapshot.relatedLogs.count,
            drawingCount: snapshot.relatedDrawings.count,
            drawingWithoutCurrentCount: drawingWithoutCurrentCount(snapshot.relatedDrawings),
            documentCount: snapshot.relatedDocuments.count,
            contactCount: snapshot.relatedContacts.count,
            missingReceiptCount: snapshot.missingReceiptCount,
            unsettledFinancialCount: snapshot.unsettledFinancialCount,
            missingOriginalEntries: ProjectDetailImportExportActions.missingProjectPackageFiles(
                documents: snapshot.relatedDocuments,
                drawings: snapshot.relatedDrawings,
                logs: snapshot.relatedLogs,
                quickNotes: snapshot.relatedQuickNotes
            ),
            estimatedPackageBytes: ProjectDetailImportExportActions.estimatedProjectPackageBytes(
                documents: snapshot.relatedDocuments,
                drawings: snapshot.relatedDrawings,
                logs: snapshot.relatedLogs,
                quickNotes: snapshot.relatedQuickNotes
            )
        )
    }

    private func drawingWithoutCurrentCount(_ drawings: [ProjectDrawing]) -> Int {
        guard !drawings.isEmpty else { return 0 }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? drawing.fileName : name
        }
        return grouped.values.filter { group in
            !group.contains(where: \.isCurrentVersion)
        }.count
    }

    private func exportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        exportState.projectPackageExportTask?.cancel()
        exportState.isExportingProjectPackage = true
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")

        exportState.projectPackageExportTask = ProjectDetailExportWorkflow.makeProjectPackageExportTask(
            project: project,
            projectId: projectId,
            materials: snapshot.relatedMaterials,
            quotes: snapshot.relatedQuotes,
            labor: snapshot.relatedLabor,
            logs: snapshot.relatedLogs,
            tasks: snapshot.relatedProgress,
            todos: snapshot.relatedTodos,
            drawings: snapshot.relatedDrawings,
            contacts: snapshot.relatedContacts,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            quickNotes: snapshot.relatedQuickNotes,
            paidAmountOverride: paidAmount(project, snapshot: snapshot),
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

    private func averageProgress(_ tasks: [ProgressTask]) -> Double {
        ProjectDetailMetrics.averageProgress(tasks)
    }

    private func trim(_ value: Double) -> String {
        ProjectDetailMetrics.trim(value)
    }

    private func updateProject(_ updated: Project) {
        guard let idx = projectStore.projects.firstIndex(where: { $0.id == updated.id }) else { return }
        store.projects[idx] = updated
        store.scheduleSave()
    }

    private func saveMaterial(_ updated: MaterialItem) {
        if let index = financeStore.materialItems.firstIndex(where: { $0.id == updated.id }) {
            store.materialItems[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteMaterial(id: UUID) {
        store.materialItems.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveQuote(_ updated: QuoteItem) {
        if let index = financeStore.quoteItems.firstIndex(where: { $0.id == updated.id }) {
            store.quoteItems[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteQuote(id: UUID) {
        store.quoteItems.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveLabor(_ updated: LaborRecord) {
        if let index = financeStore.laborRecords.firstIndex(where: { $0.id == updated.id }) {
            store.laborRecords[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteLabor(_ target: LaborRecord) {
        store.laborRecords.removeAll { $0.id == target.id }
        store.scheduleSave()
    }

    private func saveProgress(_ updated: ProgressTask) {
        if let index = projectStore.progressTasks.firstIndex(where: { $0.id == updated.id }) {
            store.progressTasks[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteProgress(id: UUID) {
        store.progressTasks.removeAll { $0.id == id }
        store.scheduleSave()
    }

    private func saveFinancialRecord(_ updated: ProjectFinancialRecord) {
        if let index = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == updated.id }) {
            store.projectFinancialRecords[index] = updated
            store.scheduleSave()
        }
    }

    private func updateProjectPhoto(context: ProjectPhotoContext, note: String, tag: PhotoTag) {
        guard let logIndex = projectStore.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = projectStore.dailyLogs[logIndex]
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
        guard let logIndex = projectStore.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = projectStore.dailyLogs[logIndex]
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
        financeState.pendingDeleteFinancialRecordIDs = ids
        financeState.showFinancialDeleteConfirm = true
    }

    private func performDeleteFinancialRecords(deleteLinkedDocuments: Bool) {
        let ids = financeState.pendingDeleteFinancialRecordIDs
        financeState.pendingDeleteFinancialRecordIDs.removeAll()
        guard !ids.isEmpty else { return }
        ProjectDetailFinanceDocumentActions.deleteFinancialRecords(
            ids: ids,
            deleteLinkedDocuments: deleteLinkedDocuments,
            store: store
        )
    }

    private func linkedDocuments(for record: ProjectFinancialRecord) -> [ProjectDocument] {
        ProjectDetailFinanceDocumentActions.linkedDocuments(for: record, documents: projectStore.projectDocuments)
    }

    private func linkDocument(_ documentID: UUID, to recordID: UUID) {
        guard let docIndex = projectStore.projectDocuments.firstIndex(where: { $0.id == documentID }),
              let targetRecordIndex = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == recordID }) else {
            return
        }

        let previousRecordID = projectStore.projectDocuments[docIndex].linkedFinancialRecordId
        if let previousRecordID,
           let previousRecordIndex = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == previousRecordID }) {
            store.projectFinancialRecords[previousRecordIndex].linkedDocumentIds.removeAll { $0 == documentID }
        }

        store.projectDocuments[docIndex].linkedFinancialRecordId = recordID
        if !projectStore.projectFinancialRecords[targetRecordIndex].linkedDocumentIds.contains(documentID) {
            store.projectFinancialRecords[targetRecordIndex].linkedDocumentIds.append(documentID)
        }
        store.scheduleSave()
    }

    private func handleOnAppear(snapshot: ProjectDetailSnapshot) {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            didAutoOpenFinancialAdd: didAutoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            didAutoOpenDocumentScanSetup: didAutoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide,
            didAutoOpenDeliveryGuide: didAutoOpenDeliveryGuide,
            focus: focus,
            didOpenFocusedItem: didOpenFocusedItem,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            contacts: snapshot.relatedContacts
        )
        if routing.shouldOpenFinancialAdd {
            didAutoOpenFinancialAdd = true
            routeState.mode = .finance
            routeState.presentation = .addFinancial
        }
        if routing.shouldOpenDocumentScanSetup {
            didAutoOpenDocumentScanSetup = true
            routeState.mode = .assets
            routeState.presentation = .documentScanSetup
        }
        if routing.shouldOpenDeliveryGuide {
            didAutoOpenDeliveryGuide = true
            routeState.mode = .overview
            routeState.presentation = .deliveryGuide
        }
        if routing.shouldConsumeFocusRequest {
            didOpenFocusedItem = true
            guard let focusedItem = routing.focusedItem else { return }
            routeState.mode = focusedItem.mode
            Task { @MainActor in
                ProjectDetailFocusedItemApplier.apply(
                    focusedItem,
                    setFinancialRecord: { financeState.editingFinancialRecord = $0 },
                    setDocument: { assetState.editingDocument = $0 },
                    setContact: { assetState.editingContact = $0 }
                )
            }
        }
    }

    @ViewBuilder
    private func attachmentSheet(record: ProjectFinancialRecord, documents: [ProjectDocument]) -> some View {
        ProjectFinancialAttachmentSheet(
            record: record,
            documents: documents,
            onDetach: { document in
                ProjectDetailFinanceDocumentActions.detachDocument(document, from: record, store: store)
            },
            onAttach: { document in
                ProjectDetailFinanceDocumentActions.attachDocument(document, to: record, store: store)
            },
            onBulkSetCategory: { documents, category in
                let ids = Set(documents.map(\.id))
                for index in projectStore.projectDocuments.indices where ids.contains(projectStore.projectDocuments[index].id) {
                    store.projectDocuments[index].category = category
                }
                store.scheduleSave()
            },
            onScan: {
                assetState.scanTarget = scanTarget(for: record)
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
        if let index = projectStore.projectContacts.firstIndex(where: { $0.id == updated.id }) {
            store.projectContacts[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteContact(_ target: ProjectContact) {
        removeContactAssociation(contactID: target.id, from: projectId)
        store.scheduleSave()
    }

    private func removeContactAssociation(contactID: UUID, from currentProjectID: UUID) {
        guard let index = projectStore.projectContacts.firstIndex(where: { $0.id == contactID }) else { return }
        var contact = store.projectContacts[index]
        if contact.projectId == currentProjectID {
            if let promotedProjectID = contact.relatedProjectIds.first(where: { $0 != currentProjectID }) {
                contact.projectId = promotedProjectID
                contact.relatedProjectIds.removeAll { $0 == currentProjectID || $0 == promotedProjectID }
                store.projectContacts[index] = contact
            } else {
                store.projectContacts.remove(at: index)
            }
        } else {
            contact.relatedProjectIds.removeAll { $0 == currentProjectID }
            store.projectContacts[index] = contact
        }
    }

    private func setDrawingAsCurrentVersion(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.setDrawingAsCurrentVersion(drawing, store: store)
    }

    private func deleteDrawing(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.deleteDrawing(drawing, store: store)
    }

    private func timelineDrawings(name: String, drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        ProjectDetailAssetActions.timelineDrawings(name: name, relatedDrawings: drawings)
    }
}

enum DetailSheet: String, Identifiable {
    case material, quote, log, labor
    var id: String { rawValue }
}
