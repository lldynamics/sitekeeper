import SwiftUI
import PhotosUI

struct ProjectDetailContent: View {
    let snapshot: ProjectDetailSnapshot
    let projectId: UUID
    let useMetric: Bool
    let statusBinding: Binding<ProjectStatus>
    let mode: ProjectDetailMode
    let anchorRequest: ProjectDetailAnchorRequest?
    let financeJumpFilter: ProjectFinanceJumpFilter
    let prefersInlineSections: Bool
    let showsAllSections: Bool
    let allProjectContacts: [ProjectContact]
    let constructionMethods: [ConstructionMethod]
    let supplierProfiles: [SupplierProfile]
    let allProjects: [Project]
    let allFinancialRecords: [ProjectFinancialRecord]
    let allDocuments: [ProjectDocument]

    @Binding var drawingFilter: DrawingListFilter
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var showDocumentFileImporter: Bool

    let onSelectMode: (ProjectDetailMode) -> Void
    let onOpenRecordsMetric: () -> Void
    let onOpenFinanceFromQuoteMetric: () -> Void
    let onOpenTodoFilter: () -> Void
    let onOpenFinanceFilter: (ProjectFinanceJumpFilter) -> Void
    let onEditProject: () -> Void
    let onOpenDeliveryGuide: () -> Void
    let onAddLog: () -> Void
    let onAddMaterial: () -> Void
    let onAddQuote: () -> Void
    let onAddLabor: () -> Void
    let onAddFinancialRecord: () -> Void
    let onAddContact: () -> Void
    let onImportDrawing: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onScanDocument: () -> Void
    let onScanDocumentCategory: (ProjectDocumentCategory) -> Void
    let onCaptureDocumentPhoto: () -> Void
    let onEditMaterial: (MaterialItem) -> Void
    let onEditQuote: (QuoteItem) -> Void
    let onEditLabor: (LaborRecord) -> Void
    let onEditProgress: (ProgressTask) -> Void
    let onOpenPhotoContext: (ProjectPhotoContext) -> Void
    let onEditDrawing: (ProjectDrawing) -> Void
    let onShowDrawingTimeline: (String) -> Void
    let onPreviewDrawing: (ProjectDrawing) -> Void
    let onDeleteDrawing: (ProjectDrawing) -> Void
    let onEditContact: (ProjectContact) -> Void
    let onDeleteContacts: (Set<UUID>) -> Void
    let onEditFinancialRecord: (ProjectFinancialRecord) -> Void
    let onDeleteFinancialRecords: (Set<UUID>) -> Void
    let onOpenDocument: (ProjectDocument) -> Void
    let onLinkDocumentToFinancialRecord: (UUID, UUID) -> Void
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let onResetFinanceJumpFilter: () -> Void
    @State private var inlineFocusedMode: ProjectDetailMode?

    var body: some View {
        ProjectDetailContentView(
            isWide: prefersInlineSections,
            scrollRequest: anchorRequest,
            onVisibleAnchorChange: { anchor in
                guard prefersInlineSections, showsAllSections else { return }
                inlineFocusedMode = mode(for: anchor)
            },
            jumpBar: {
                EmptyView()
            },
            header: {
                projectHeader(showsStatus: prefersInlineSections || mode == .overview)
            },
            modePicker: {
                modePickerSection
            },
            content: {
                detailModeSections
            }
        )
        .onChange(of: mode) { _, newMode in
            guard prefersInlineSections, showsAllSections else { return }
            inlineFocusedMode = newMode
        }
        .onChange(of: showsAllSections) { _, isAllSections in
            if !isAllSections {
                inlineFocusedMode = nil
            } else {
                inlineFocusedMode = mode
            }
        }
    }

    private var modePickerSection: some View {
        let modeBinding = Binding<ProjectDetailMode>(
            get: {
                if prefersInlineSections, showsAllSections {
                    return inlineFocusedMode ?? mode
                }
                return mode
            },
            set: { newMode in
                if prefersInlineSections, showsAllSections {
                    inlineFocusedMode = newMode
                }
                onSelectMode(newMode)
            }
        )
        return Group {
            if prefersInlineSections {
                focusPicker(selection: modeBinding)
            } else {
                Section {
                    focusPicker(selection: modeBinding)
                }
            }
        }
    }

    private func focusPicker(selection: Binding<ProjectDetailMode>) -> some View {
        Picker(String(localized: "内容"), selection: selection) {
            ForEach(ProjectDetailMode.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "项目详情焦点"))
    }

    private func projectHeader(showsStatus: Bool) -> some View {
        let project = snapshot.project
        let missingOriginalEntries = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        )
        let deliveryHealth = ProjectDeliveryHealth(
            missingReceiptCount: snapshot.missingReceiptCount,
            drawingCount: snapshot.relatedDrawings.count,
            openTodoCount: snapshot.openTodoCount,
            backupState: ProjectDeliveryBackupState.current(),
            missingOriginalCount: missingOriginalEntries.count,
            drawingWithoutCurrentCount: ReportBuilder.projectPackageDrawingGroupsWithoutCurrentVersion(snapshot.relatedDrawings).count
        )
        let documentArchiveChecklist = DocumentArchiveChecklistSnapshot(
            documents: snapshot.relatedDocuments,
            requiredCategories: project.requiredDocumentCategories
        )
        let paidAmountValue = ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
        let unpaidAmountValue = ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paidAmountValue)
        return ProjectDetailHeaderSection(
            project: project,
            status: statusBinding,
            todayValue: snapshot.hasTodayLog ? String(localized: "已写日志") : String(localized: "未写日志"),
            todayColor: snapshot.hasTodayLog ? .appSuccess : .appWarning,
            riskValue: riskSignalCount(
                unpaidAmount: unpaidAmountValue,
                checklist: documentArchiveChecklist
            ) == 0
                ? String(localized: "正常")
                : String(format: String(localized: "%lld 项"), Int64(riskSignalCount(unpaidAmount: unpaidAmountValue, checklist: documentArchiveChecklist))),
            riskColor: riskSignalCount(unpaidAmount: unpaidAmountValue, checklist: documentArchiveChecklist) == 0 ? .appSuccess : .appRisk,
            pendingValue: pendingSignalCount(checklist: documentArchiveChecklist) == 0
                ? String(localized: "无待处理")
                : String(format: String(localized: "%lld 项"), Int64(pendingSignalCount(checklist: documentArchiveChecklist))),
            pendingColor: pendingSignalCount(checklist: documentArchiveChecklist) == 0 ? .appSuccess : .appWarning,
            deliveryValue: deliveryHealth.verdictTitle,
            deliveryColor: deliveryHealth.isDeliverable ? .appSuccess : .appRisk,
            showsStatus: showsStatus,
            onOpenToday: {
                if snapshot.hasTodayLog {
                    onOpenRecordsMetric()
                } else {
                    onAddLog()
                }
            },
            onOpenRisk: {
                openPrimaryRisk(
                    unpaidAmount: unpaidAmountValue,
                    checklist: documentArchiveChecklist
                )
            },
            onOpenPending: onOpenTodoFilter,
            onOpenDelivery: onOpenDeliveryGuide
        )
    }

    private func riskSignalCount(unpaidAmount: Double, checklist: DocumentArchiveChecklistSnapshot) -> Int {
        snapshot.overdueProgressCount
            + snapshot.overdueTodoCount
            + snapshot.missingReceiptCount
            + snapshot.unpricedQuoteCount
            + checklist.missingCount
            + checklist.returnedDocumentCount
            + checklist.legacyDocumentCount
            + (snapshot.hasTodayLog ? 0 : 1)
            + (unpaidAmount > 0 ? 1 : 0)
    }

    private func pendingSignalCount(checklist: DocumentArchiveChecklistSnapshot) -> Int {
        snapshot.openTodoCount
            + checklist.actionCount
            + checklist.returnedDocumentCount
            + checklist.legacyDocumentCount
    }

    private func openPrimaryRisk(unpaidAmount: Double, checklist: DocumentArchiveChecklistSnapshot) {
        if snapshot.missingReceiptCount > 0 {
            onOpenFinanceFilter(.missingReceipt)
            return
        }
        if unpaidAmount > 0 {
            onOpenFinanceFilter(.unsettled)
            return
        }
        if checklist.missingCount > 0 || checklist.returnedDocumentCount > 0 || checklist.legacyDocumentCount > 0 {
            onOpenMode(.assets)
            return
        }
        if snapshot.overdueProgressCount > 0 || snapshot.overdueTodoCount > 0 {
            onOpenTodoFilter()
            return
        }
        if !snapshot.hasTodayLog {
            onAddLog()
            return
        }
        onOpenRecordsMetric()
    }

    private var detailModeSections: some View {
        let project = snapshot.project
        let paidAmountValue = ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
        let materialCostValue = ProjectDetailMetrics.currentMaterialCost(
            project: project,
            materialCostAuto: snapshot.materialCostAuto,
            hasMaterialDetails: !snapshot.relatedMaterials.isEmpty
        )
        let laborCostValue = ProjectDetailMetrics.currentLaborCost(
            project: project,
            laborCostAuto: snapshot.laborCostAuto,
            hasLaborDetails: !snapshot.relatedLabor.isEmpty
        )
        return ProjectDetailModeSectionsView(
            mode: mode,
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
            laborHours: ProjectDetailMetrics.trim(snapshot.laborHoursTotal),
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
            allProjectContacts: allProjectContacts,
            constructionMethods: constructionMethods,
            supplierProfiles: supplierProfiles,
            allProjects: allProjects,
            allFinancialRecords: allFinancialRecords,
            relatedFinancialRecords: snapshot.relatedFinancialRecords,
            allDocuments: allDocuments,
            relatedDocuments: snapshot.relatedDocuments,
            relatedQuickNotes: snapshot.relatedQuickNotes,
            relatedTodos: snapshot.relatedTodos,
            filteredDrawings: snapshot.filteredDrawings(for: drawingFilter),
            financeJumpFilter: financeJumpFilter,
            showsAllSections: showsAllSections,
            drawingFilter: $drawingFilter,
            selectedPhotoItem: $selectedPhotoItem,
            showDocumentFileImporter: $showDocumentFileImporter,
            onAddLog: onAddLog,
            onAddMaterial: onAddMaterial,
            onAddQuote: onAddQuote,
            onAddLabor: onAddLabor,
            onAddFinancialRecord: onAddFinancialRecord,
            onAddContact: onAddContact,
            onImportDrawing: onImportDrawing,
            onOpenMode: onOpenMode,
            onOpenFinanceFilter: onOpenFinanceFilter,
            onOpenTodoFilter: onOpenTodoFilter,
            onOpenTimelineItem: { item in
                onOpenMode(item.targetMode)
            },
            onScanDocument: onScanDocument,
            onScanDocumentCategory: onScanDocumentCategory,
            onCaptureDocumentPhoto: onCaptureDocumentPhoto,
            onEditMaterial: onEditMaterial,
            onEditQuote: onEditQuote,
            onEditLabor: onEditLabor,
            onEditProgress: onEditProgress,
            onOpenPhotoContext: onOpenPhotoContext,
            onEditDrawing: onEditDrawing,
            onShowDrawingTimeline: onShowDrawingTimeline,
            onPreviewDrawing: onPreviewDrawing,
            onDeleteDrawing: onDeleteDrawing,
            onEditContact: onEditContact,
            onDeleteContacts: onDeleteContacts,
            onEditFinancialRecord: onEditFinancialRecord,
            onDeleteFinancialRecords: onDeleteFinancialRecords,
            onOpenDocument: onOpenDocument,
            onLinkDocumentToFinancialRecord: onLinkDocumentToFinancialRecord,
            linkedDocuments: linkedDocuments,
            onResetFinanceJumpFilter: onResetFinanceJumpFilter
        )
    }

    private func mode(for anchor: ProjectDetailAnchor) -> ProjectDetailMode {
        switch anchor {
        case .overview:
            return .overview
        case .records:
            return .records
        case .assets:
            return .assets
        case .finance:
            return .finance
        case .timeline:
            return .timeline
        }
    }
}
