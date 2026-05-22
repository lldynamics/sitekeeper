import SwiftUI
import PhotosUI
import UIKit

struct ProjectDetailModeSectionsView: View {
    let mode: ProjectDetailMode
    let project: Project
    let useMetric: Bool
    let paidAmount: Double
    let unpaidAmount: Double
    let materialCost: Double
    let laborCost: Double
    let estimatedProfit: Double
    let laborHours: String
    let projectBookIncome: Double
    let projectBookExpense: Double
    let relatedMaterials: [MaterialItem]
    let relatedQuotes: [QuoteItem]
    let relatedLabor: [LaborRecord]
    let relatedWarehouseMovements: [ProjectWarehouseMovement]
    let relatedLogs: [DailyLog]
    let relatedProgress: [ProgressTask]
    let relatedDrawings: [ProjectDrawing]
    let relatedContacts: [ProjectContact]
    let allProjectContacts: [ProjectContact]
    let constructionMethods: [ConstructionMethod]
    let supplierProfiles: [SupplierProfile]
    let allProjects: [Project]
    let allFinancialRecords: [ProjectFinancialRecord]
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let allDocuments: [ProjectDocument]
    let relatedDocuments: [ProjectDocument]
    let relatedQuickNotes: [QuickNote]
    let relatedTodos: [SiteTodo]
    let filteredDrawings: [ProjectDrawing]
    let financeJumpFilter: ProjectFinanceJumpFilter
    let showsAllSections: Bool
    @Binding var drawingFilter: DrawingListFilter
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var showDocumentFileImporter: Bool

    let onAddLog: () -> Void
    let onAddMaterial: () -> Void
    let onAddQuote: () -> Void
    let onAddLabor: () -> Void
    let onAddFinancialRecord: () -> Void
    let onAddContact: () -> Void
    let onImportDrawing: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onOpenFinanceFilter: (ProjectFinanceJumpFilter) -> Void
    let onOpenTodoFilter: () -> Void
    let onOpenTimelineItem: (ProjectTimelineItem) -> Void
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

    var body: some View {
        Group {
            if showsAllSections {
                anchorMarker(.overview)
                overviewSections
                anchorMarker(.records)
                recordModeSections
                anchorMarker(.assets)
                assetModeSections
                anchorMarker(.finance)
                financeModeSections
                anchorMarker(.timeline)
                timelineSection
            } else {
                CompactProjectDetailModeContent(mode: mode) {
                    overviewSections
                } records: {
                    recordModeSections
                } assets: {
                    assetModeSections
                } finance: {
                    financeModeSections
                } timeline: {
                    timelineSection
                }
            }
        }
    }

    private var timelineSection: some View {
        ProjectTimelineSectionView(items: timelineItems, onSelect: onOpenTimelineItem)
    }

    private var overviewSections: some View {
        let documentArchiveChecklist = DocumentArchiveChecklistSnapshot(
            documents: relatedDocuments,
            requiredCategories: project.requiredDocumentCategories
        )
        return ProjectOverviewView(
            project: project,
            businessSummary: overviewBusinessSummary,
            paidAmount: paidAmount,
            unpaidAmount: unpaidAmount,
            materialCost: materialCost,
            laborCost: laborCost,
            estimatedProfit: estimatedProfit,
            laborHours: laborHours,
            projectBookIncome: projectBookIncome,
            projectBookExpense: projectBookExpense,
            logDayCount: Set(relatedLogs.map(\.date)).count,
            materialCount: relatedMaterials.count,
            contactCount: relatedContacts.count,
            financialCount: relatedFinancialRecords.count,
            documentCount: relatedDocuments.count,
            documentMissingCategoryCount: documentArchiveChecklist.missingCount,
            documentActionCount: documentArchiveChecklist.actionCount,
            documentReturnedCount: documentArchiveChecklist.returnedDocumentCount,
            documentArchivedCount: documentArchiveChecklist.archivedDocumentCount,
            recentLogs: relatedLogs,
            progressTasks: relatedProgress,
            todos: relatedTodos.filter { !$0.isDone },
            recentItems: Array(timelineItems.prefix(4)),
            overdueCount: overviewOverdueCount,
            missingReceiptCount: overviewMissingReceiptCount,
            hasTodayLog: overviewHasTodayLog,
            onOpenFinance: { onOpenFinanceFilter(.none) },
            onOpenFinanceUnsettled: {
                onOpenFinanceFilter(.unsettled)
            },
            onOpenFinanceMissingReceipt: {
                onOpenFinanceFilter(.missingReceipt)
            },
            onOpenRecords: { onOpenMode(.records) },
            onOpenAssets: { onOpenMode(.assets) },
            onOpenLogs: { onOpenMode(.records) },
            onOpenTodos: onOpenTodoFilter,
            onOpenTimeline: { onOpenMode(.timeline) },
            onAddLog: onAddLog,
            onEditProgress: onEditProgress,
            onOpenTimelineItem: onOpenTimelineItem,
            logRow: { log in
                ProjectDetailLogRowView(log: log)
            }
        )
    }

    private var overviewBusinessSummary: ProjectBusinessSummary {
        ProjectBusinessSummary(
            quoteTotal: relatedQuotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) },
            contractAmount: project.contractAmountValue.doubleValue,
            paidAmount: paidAmount,
            receivableAmount: unpaidAmount,
            receivableAgeDays: overviewReceivableAgeDays,
            recentCollection: overviewRecentCollection,
            materialCost: materialCost,
            laborCostAmount: laborCost,
            pendingMaterialCount: relatedMaterials.filter { $0.quantityValue.doubleValue == 0 }.count,
            unpricedQuoteCount: relatedQuotes.filter { $0.unitPriceValue.doubleValue == 0 }.count
        )
    }

    private var overviewReceivableAgeDays: Int? {
        guard unpaidAmount > 0 else { return nil }
        guard let endDate = Formatters.date.date(from: project.expectedEndDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDate = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: today).day ?? 0
        return max(days, 0)
    }

    private var overviewRecentCollection: CollectionSnapshot? {
        ProjectFinancialMetrics.latestCollection(
            records: relatedFinancialRecords,
            projectName: { _ in project.name }
        )
    }

    private var recordModeSections: some View {
        Group {
            logSections
            progressSections
            photoSections
        }
    }

    private var financeModeSections: some View {
        Group {
            projectBookkeepingSection
            quoteSections
            materialSections
            laborSections
            Section(String(localized: "项目仓库")) {
                NavigationLink {
                    ProjectWarehouseView(project: project)
                } label: {
                    Label(
                        String(
                            format: String(localized: "查看项目仓库（%lld 条出入库）"),
                            Int64(relatedWarehouseMovements.count)
                        ),
                        systemImage: "shippingbox.and.arrow.backward.fill"
                    )
                }
            }
        }
    }

    private var assetModeSections: some View {
        Group {
            drawingSections
            projectDocumentSections
            contactSections
        }
    }

    private var logSections: some View {
        ProjectLogSectionView(
            logs: relatedLogs,
            onAddLog: onAddLog,
            logRow: { log in ProjectDetailLogRowView(log: log) }
        )
    }

    private var materialSections: some View {
        ProjectMaterialSectionView(
            items: relatedMaterials,
            useMetric: useMetric,
            onAdd: onAddMaterial,
            onEdit: onEditMaterial
        )
    }

    private var quoteSections: some View {
        ProjectQuoteSectionView(
            items: relatedQuotes,
            onAdd: onAddQuote,
            onEdit: onEditQuote
        )
    }

    private var laborSections: some View {
        ProjectLaborSectionView(
            items: relatedLabor,
            onAdd: onAddLabor,
            onEdit: onEditLabor
        )
    }

    private var progressSections: some View {
        ProjectProgressSectionView(tasks: relatedProgress, onEdit: onEditProgress)
    }

    private var photoSections: some View {
        ProjectPhotoSectionView(logs: relatedLogs, onOpen: onOpenPhotoContext)
    }

    private var drawingSections: some View {
        ProjectDrawingSectionView(
            drawingFilter: $drawingFilter,
            relatedDrawings: relatedDrawings,
            filteredDrawings: filteredDrawings,
            icon: ProjectDetailDrawingHelper.drawingIcon(_:),
            onImportDrawing: onImportDrawing,
            onEdit: onEditDrawing,
            onTimeline: { onShowDrawingTimeline($0.name) },
            onPreview: onPreviewDrawing,
            onDelete: onDeleteDrawing
        )
    }

    private var contactSections: some View {
        ProjectContactsView(
            contacts: relatedContacts,
            onAdd: onAddContact,
            onEdit: onEditContact
        ) { ids in
            onDeleteContacts(ids)
        }
    }

    private var projectBookkeepingSection: some View {
        ProjectBookkeepingView(
            records: relatedFinancialRecords,
            supplierProfiles: supplierProfiles,
            projectContacts: allProjectContacts,
            projects: allProjects,
            allFinancialRecords: allFinancialRecords,
            allProjectDocuments: allDocuments,
            projectCustomerName: project.customerName,
            linkedDocuments: linkedDocuments,
            onEdit: onEditFinancialRecord,
            onDelete: onDeleteFinancialRecords,
            onAddRecord: onAddFinancialRecord,
            quickFilter: financeJumpFilter,
            onResetQuickFilter: onResetFinanceJumpFilter
        )
    }

    private var projectDocumentSections: some View {
        Group {
            ProjectDetailDocumentActionSection(
                selectedPhotoItem: $selectedPhotoItem,
                onScanDocument: onScanDocument,
                onImportFiles: {
                    showDocumentFileImporter = true
                },
                onCapturePhoto: onCaptureDocumentPhoto
            )
            ProjectDocumentsView(
                project: project,
                documents: relatedDocuments,
                requiredCategories: project.requiredDocumentCategories,
                progressTasks: relatedProgress,
                financialRecords: relatedFinancialRecords,
                constructionMethods: constructionMethods,
                icon: ProjectDetailFinanceDocumentHelper.documentIcon(_:),
                onOpen: onOpenDocument,
                onLink: onLinkDocumentToFinancialRecord,
                onScanCategory: onScanDocumentCategory
            )
        }
    }

    @ViewBuilder
    private func anchorMarker(_ anchor: ProjectDetailAnchor) -> some View {
        Color.clear
            .frame(height: 0)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ProjectDetailAnchorOffsetPreferenceKey.self,
                        value: [anchor: proxy.frame(in: .named(ProjectDetailScrollTracking.coordinateSpaceName)).minY]
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .id(anchor.scrollID)
    }

    private var timelineItems: [ProjectTimelineItem] {
        ProjectTimelineBuilder.makeItems(
            logs: relatedLogs,
            progress: relatedProgress,
            materials: relatedMaterials,
            quotes: relatedQuotes,
            labor: relatedLabor,
            financialRecords: relatedFinancialRecords,
            documents: relatedDocuments,
            warehouseMovements: relatedWarehouseMovements,
            quickNotes: relatedQuickNotes,
            siteTodos: relatedTodos,
            drawings: relatedDrawings
        )
    }

    private var overviewOverdueCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let progressCount = relatedProgress.filter { task in
            guard task.clampedCompletion < 1,
                  let due = Formatters.parseDateOrDateTime(task.dueDate) else { return false }
            return due < today
        }.count
        return progressCount + relatedTodos.filter(\.isOverdue).count
    }

    private var overviewMissingReceiptCount: Int {
        relatedFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = relatedDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }

    private var overviewHasTodayLog: Bool {
        let today = Formatters.date.string(from: Date())
        return relatedLogs.contains { $0.date == today }
    }
}
