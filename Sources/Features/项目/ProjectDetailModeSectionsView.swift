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
    let prefersInlineSections: Bool
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
        if showsAllSections {
            inlineFocusedSections
        } else {
            ProjectDetailModeContent(mode: mode) {
                overviewSections
            } records: {
                recordHubSections
            } assets: {
                assetHubSections
            } finance: {
                financeHubSections
            } timeline: {
                ProjectTimelineSectionView(items: timelineItems, onSelect: onOpenTimelineItem)
            }
        }
    }

    private var inlineFocusedSections: some View {
        Group {
            anchorMarker(.overview)
            if mode == .overview {
                overviewSections
            } else {
                collapsedModeSection(
                    mode: .overview,
                    title: "概览",
                    subtitle: overviewCollapsedSummary,
                    systemImage: "rectangle.grid.2x2.fill",
                    tint: .appPrimaryAction
                )
            }
            anchorMarker(.records)
            if mode == .records {
                logSections
                progressSections
                photoSections
            } else {
                collapsedModeSection(
                    mode: .records,
                    title: "现场",
                    subtitle: recordsCollapsedSummary,
                    systemImage: "checklist.checked",
                    tint: .appWarning
                )
            }
            anchorMarker(.assets)
            if mode == .assets {
                drawingSections
                projectDocumentSections
                contactSections
            } else {
                collapsedModeSection(
                    mode: .assets,
                    title: "资料",
                    subtitle: assetsCollapsedSummary,
                    systemImage: "folder.fill",
                    tint: .appDoc
                )
            }
            anchorMarker(.finance)
            if mode == .finance {
                projectBookkeepingSection
                quoteSections
                materialSections
                laborSections
                Section("项目仓库") {
                    NavigationLink {
                        ProjectWarehouseView(project: project)
                    } label: {
                        Label("查看项目仓库（\(relatedWarehouseMovements.count) 条出入库）", systemImage: "shippingbox.and.arrow.backward.fill")
                    }
                }
            } else {
                collapsedModeSection(
                    mode: .finance,
                    title: "财务",
                    subtitle: financeCollapsedSummary,
                    systemImage: "yensign.circle.fill",
                    tint: .appFinance
                )
            }
            anchorMarker(.timeline)
            if mode == .timeline {
                ProjectTimelineSectionView(
                    items: timelineItems,
                    showsFilters: false,
                    previewLimit: 5,
                    onSelect: onOpenTimelineItem
                )
            } else {
                collapsedModeSection(
                    mode: .timeline,
                    title: "时间线",
                    subtitle: timelineCollapsedSummary,
                    systemImage: "timeline.selection",
                    tint: .appPrimaryAction
                )
            }
        }
    }

    private var overviewCollapsedSummary: String {
        let openTodoCount = relatedTodos.filter { !$0.isDone }.count
        let unpaidText = unpaidAmount > 0 ? ReportBuilder.money(unpaidAmount) : "已收清"
        return "待办 \(openTodoCount) 项 · 未收款 \(unpaidText)"
    }

    private var recordsCollapsedSummary: String {
        let openTodoCount = relatedTodos.filter { !$0.isDone }.count
        return "\(relatedLogs.count) 条日志 · \(relatedProgress.count) 项进度 · \(openTodoCount) 项待办"
    }

    private var assetsCollapsedSummary: String {
        "\(relatedDrawings.count) 份图纸 · \(relatedDocuments.count) 份资料 · \(relatedContacts.count) 位联系人"
    }

    private var financeCollapsedSummary: String {
        "\(relatedFinancialRecords.count) 笔流水 · \(relatedMaterials.count) 项材料 · \(relatedQuotes.count) 项报价 · \(relatedLabor.count) 条人工"
    }

    private var timelineCollapsedSummary: String {
        guard !timelineItems.isEmpty else { return "暂无操作记录" }
        let visibleCount = min(5, timelineItems.count)
        return "最近 \(visibleCount) 条 · 共 \(timelineItems.count) 条操作"
    }

    private func collapsedModeSection(
        mode targetMode: ProjectDetailMode,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Section {
            Button {
                onOpenMode(targetMode)
            } label: {
                HStack(spacing: AppSpacing.normal) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
    }

    private var overviewSections: some View {
        ProjectOverviewView(
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

    private var recordHubSections: some View {
        Group {
            if prefersInlineSections {
                logSections
                progressSections
                photoSections
            } else {
                ProjectRecordHubSectionView(
                    logsCount: relatedLogs.count,
                    progressCount: relatedProgress.count,
                    photoCount: relatedLogs.flatMap(\.photoAttachments).count,
                    logsDestination: { List { logSections } },
                    progressDestination: { List { progressSections } },
                    photoDestination: { List { photoSections } }
                )
            }
        }
    }

    private var financeHubSections: some View {
        Group {
            if prefersInlineSections {
                projectBookkeepingSection
                quoteSections
                materialSections
                laborSections
                Section("项目仓库") {
                    NavigationLink {
                        ProjectWarehouseView(project: project)
                    } label: {
                        Label("查看项目仓库（\(relatedWarehouseMovements.count) 条出入库）", systemImage: "shippingbox.and.arrow.backward.fill")
                    }
                }
            } else if financeJumpFilter == .none {
                ProjectFinanceHubSectionView(
                    financialCount: relatedFinancialRecords.count,
                    quoteCount: relatedQuotes.count,
                    materialCount: relatedMaterials.count,
                    laborCount: relatedLabor.count,
                    warehouseCount: relatedWarehouseMovements.count,
                    bookDestination: { projectBookkeepingDestination },
                    quoteDestination: { List { quoteSections } },
                    materialDestination: { List { materialSections } },
                    laborDestination: { List { laborSections } },
                    warehouseDestination: { ProjectWarehouseView(project: project) }
                )
            } else {
                projectBookkeepingDestination
            }
        }
    }

    private var assetHubSections: some View {
        Group {
            drawingSections
            projectDocumentSections
            contactSections
        }
    }

    private var projectBookkeepingDestination: some View {
        ProjectDetailPrimaryActionList(
            title: "新增账目",
            systemImage: "plus.circle.fill",
            tint: .appPrimaryAction,
            action: onAddFinancialRecord
        ) {
            projectBookkeepingSection
        }
    }

    private var projectDocumentDestination: some View {
        ProjectDetailPrimaryActionList(
            title: "扫描并添加资料",
            systemImage: "viewfinder",
            tint: .appDoc,
            action: {
                onScanDocument()
            }
        ) {
            projectDocumentSections
        }
    }

    private var projectContactDestination: some View {
        ProjectDetailPrimaryActionList(
            title: "添加联系人",
            systemImage: "person.crop.circle.badge.plus",
            tint: .appPrimaryAction,
            action: onAddContact
        ) {
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
                documents: relatedDocuments,
                financialRecords: relatedFinancialRecords,
                constructionMethods: constructionMethods,
                icon: ProjectDetailFinanceDocumentHelper.documentIcon(_:),
                onOpen: onOpenDocument,
                onLink: onLinkDocumentToFinancialRecord
            )
        }
    }

    @ViewBuilder
    private func anchorMarker(_ anchor: ProjectDetailAnchor) -> some View {
        Color.clear
            .frame(height: 0)
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
