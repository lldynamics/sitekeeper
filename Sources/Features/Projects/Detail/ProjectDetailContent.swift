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
    @State private var receivingMaterial: MaterialItem?

    var body: some View {
        ProjectDetailContentView(
            isWide: prefersInlineSections,
            scrollRequest: anchorRequest,
            onVisibleAnchorChange: { anchor in
                guard prefersInlineSections, showsAllSections else { return }
                inlineFocusedMode = mode(for: anchor)
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
        .sheet(item: $receivingMaterial) { material in
            MaterialReceiptSheet(material: material)
        }
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
        Picker(AppLocalization.string("内容"), selection: selection) {
            ForEach(ProjectDetailMode.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(AppLocalization.string("项目详情焦点"))
    }

    private func projectHeader(showsStatus: Bool) -> some View {
        ProjectDetailOverviewHeader(
            snapshot: snapshot, statusBinding: statusBinding, showsStatus: showsStatus,
            onOpenRecordsMetric: onOpenRecordsMetric, onAddLog: onAddLog,
            onOpenFinanceFilter: onOpenFinanceFilter, onOpenMode: onOpenMode,
            onOpenTodoFilter: onOpenTodoFilter, onOpenDeliveryGuide: onOpenDeliveryGuide
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
            onReceiveMaterial: { receivingMaterial = $0 },
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
