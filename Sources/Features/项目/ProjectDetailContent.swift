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
    let onExportDeliveryPackage: () -> Void
    let onAddLog: () -> Void
    let onAddMaterial: () -> Void
    let onAddQuote: () -> Void
    let onAddLabor: () -> Void
    let onAddFinancialRecord: () -> Void
    let onAddContact: () -> Void
    let onImportDrawing: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onScanDocument: () -> Void
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

    var body: some View {
        ProjectDetailContentView(
            isWide: prefersInlineSections,
            scrollRequest: anchorRequest,
            jumpBar: {
                EmptyView()
            },
            header: {
                projectHeader(showsStatus: prefersInlineSections || mode == .overview)
            },
            quickActions: {
                quickActionSection
            },
            modePicker: {
                modePickerSection
            },
            content: {
                detailModeSections
            }
        )
    }

    private var modePickerSection: some View {
        let modeBinding = Binding<ProjectDetailMode>(
            get: { mode },
            set: { onSelectMode($0) }
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
        Picker("内容", selection: selection) {
            ForEach(ProjectDetailMode.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "项目详情焦点"))
    }

    private func projectHeader(showsStatus: Bool) -> some View {
        let project = snapshot.project
        let paidAmountValue = ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
        let unpaidAmountValue = ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paidAmountValue)
        return ProjectDetailHeaderSection(
            project: project,
            status: statusBinding,
            progressValue: "\(Int(ProjectDetailMetrics.averageProgress(snapshot.relatedProgress) * 100))%",
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
            onOpenRecords: onOpenRecordsMetric,
            onOpenFinanceFromQuote: onOpenFinanceFromQuoteMetric,
            onOpenTodoFilter: onOpenTodoFilter,
            onOpenFinanceFromUnpaid: { onOpenFinanceFilter(.none) },
            onEditProject: onEditProject,
            canExportDeliveryPackage: project.status == .completed || project.status == .settled,
            onExportDeliveryPackage: onExportDeliveryPackage
        )
    }

    private var quickActionSection: some View {
        ProjectDetailQuickActionSection(
            onAddLog: onAddLog,
            onAddFinance: onAddFinancialRecord,
            onAddDocument: onScanDocument,
            onAddContact: onAddContact,
            onImportDrawing: onImportDrawing,
            onAddMaterial: onAddMaterial,
            onAddQuote: onAddQuote,
            onAddLabor: onAddLabor
        )
    }

    private var detailModeSections: some View {
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
}
