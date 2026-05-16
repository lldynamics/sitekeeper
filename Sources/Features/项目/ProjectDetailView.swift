import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import VisionKit
import PhotosUI

struct ProjectDetailView: View {
    let projectId: UUID
    let initialMode: ProjectDetailMode?
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool
    let autoOpenDeliveryGuide: Bool

    init(
        projectId: UUID,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false
    ) {
        self.projectId = projectId
        self.initialMode = initialMode
        self.focus = focus
        self.autoOpenFinancialAdd = autoOpenFinancialAdd
        self.autoOpenDocumentScanSetup = autoOpenDocumentScanSetup
        self.autoOpenDeliveryGuide = autoOpenDeliveryGuide
    }

    var body: some View {
        ProjectDetailContainer(
            projectId: projectId,
            initialMode: initialMode,
            focus: focus,
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide
        )
    }
}

struct ProjectDetailContainer: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    let projectId: UUID
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool
    let autoOpenDeliveryGuide: Bool

    @State var exportState = ProjectDetailExportStateModel()
    @State var routeState: ProjectDetailRouteState
    @State var financeState = ProjectDetailFinanceState()
    @State var assetState = ProjectDetailAssetState()
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    @State var didAutoOpenFinancialAdd = false
    @State var didAutoOpenDocumentScanSetup = false
    @State var didAutoOpenDeliveryGuide = false
    @State var didOpenFocusedItem = false
    @State var showTodoFilterView = false

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

    var usesSingleCanvasLayoutOnPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var drawingImportConflictDialogMessage: String {
        let names = assetState.drawingImportConflictNames
        guard !names.isEmpty else {
            return String(localized: "检测到同名图纸，请选择导入策略。")
        }
        let preview = names.prefix(3).joined(separator: "、")
        if names.count > 3 {
            return String(
                format: String(localized: "检测到同名图纸：%@ 等 %lld 项，请选择导入策略。"),
                preview,
                Int64(names.count)
            )
        }
        return String(
            format: String(localized: "检测到同名图纸：%@，请选择导入策略。"),
            preview
        )
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
            ProjectDetailContent(
                snapshot: snapshot,
                projectId: projectId,
                useMetric: useMetric,
                statusBinding: statusBinding,
                mode: routeState.mode,
                anchorRequest: routeState.anchorRequest,
                financeJumpFilter: routeState.financeJumpFilter,
                prefersInlineSections: usesInlineDetailLayout(for: proxy.size.width),
                showsAllSections: usesInlineDetailLayout(for: proxy.size.width),
                allProjectContacts: projectStore.projectContacts,
                constructionMethods: store.constructionMethods,
                supplierProfiles: store.supplierProfiles,
                allProjects: projectStore.projects,
                allFinancialRecords: projectStore.projectFinancialRecords,
                allDocuments: projectStore.projectDocuments,
                drawingFilter: $routeState.drawingFilter,
                selectedPhotoItem: $assetState.selectedPhotoItem,
                showDocumentFileImporter: $assetState.showDocumentFileImporter,
                onSelectMode: { newMode in
                    routeState.mode = newMode
                    if usesInlineDetailLayout(for: proxy.size.width) {
                        requestAnchorScroll(anchor(for: newMode))
                    }
                },
                onOpenRecordsMetric: openRecordsModeFromMetric,
                onOpenFinanceFromQuoteMetric: openFinanceModeFromQuoteMetric,
                onOpenTodoFilter: openTodoFilterFromMetric,
                onOpenFinanceFilter: openFinanceModeFromMetric(filter:),
                onEditProject: { routeState.presentation = .editProject },
                onExportDeliveryPackage: { routeState.presentation = .deliveryGuide },
                onAddLog: { routeState.presentation = .quickAdd(.log) },
                onAddMaterial: { routeState.presentation = .quickAdd(.material) },
                onAddQuote: { routeState.presentation = .quickAdd(.quote) },
                onAddLabor: { routeState.presentation = .quickAdd(.labor) },
                onAddFinancialRecord: { routeState.presentation = .addFinancial },
                onAddContact: { routeState.presentation = .addContact },
                onImportDrawing: { assetState.showDrawingImporter = true },
                onOpenMode: { mode in
                    openMode(mode, prefersInlineSections: usesInlineDetailLayout(for: proxy.size.width))
                },
                onScanDocument: {
                    routeState.documentScanCategory = nil
                    routeState.presentation = .documentScanSetup
                },
                onScanDocumentCategory: { category in
                    routeState.documentScanCategory = category
                    routeState.presentation = .documentScanSetup
                },
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
            documentScanCategory: $routeState.documentScanCategory,
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
                store.appendProjectContact(contact)
                store.scheduleSave()
            },
            onCreateFinancialRecord: { record, shouldScan in
                store.appendProjectFinancialRecord(record)
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
            CADPreviewContainer(request: request)
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
            flushPendingProjectDeletionIfNeeded()
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
        .operationToast(notice: $operationNotice)
    }

}

enum DetailSheet: String, Identifiable {
    case material, quote, log, labor
    var id: String { rawValue }
}
