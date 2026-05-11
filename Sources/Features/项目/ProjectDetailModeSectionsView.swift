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
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let relatedDocuments: [ProjectDocument]
    let relatedQuickNotes: [QuickNote]
    let relatedTodos: [SiteTodo]
    let legacyPayments: [PaymentRecord]
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
    let onMigrateLegacyPayments: () -> Void
    let onResetFinanceJumpFilter: () -> Void

    var body: some View {
        if showsAllSections {
            allSections
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
                ProjectTimelineSectionView(items: timelineItems)
            }
        }
    }

    private var allSections: some View {
        Group {
            anchorMarker(.overview)
            overviewSections
            anchorMarker(.records)
            logSections
            progressSections
            photoSections
            anchorMarker(.assets)
            drawingSections
            projectDocumentSections
            contactSections
            anchorMarker(.finance)
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
            legacyPaymentMigrationSection
            anchorMarker(.timeline)
            ProjectTimelineSectionView(items: timelineItems)
        }
    }

    private var overviewSections: some View {
        ProjectOverviewView(
            project: project,
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
            onOpenFinance: { onOpenMode(.finance) },
            onOpenRecords: { onOpenMode(.records) },
            onOpenAssets: { onOpenMode(.assets) },
            onAddLog: onAddLog,
            onEditProgress: onEditProgress,
            logRow: { log in
                ProjectDetailLogRowView(log: log)
            }
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
                legacyPaymentMigrationSection
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
                    warehouseDestination: { ProjectWarehouseView(project: project) },
                    legacyPaymentsCount: legacyPayments.count,
                    onMigrateLegacyPayments: onMigrateLegacyPayments
                )
            } else {
                projectBookkeepingDestination
            }
        }
    }

    private var assetHubSections: some View {
        Group {
            if prefersInlineSections {
                drawingSections
                projectDocumentSections
                contactSections
            } else {
                ProjectAssetHubSectionView(
                    drawingCount: relatedDrawings.count,
                    documentCount: relatedDocuments.count,
                    contactCount: relatedContacts.count,
                    drawingDestination: { List { drawingSections } },
                    documentDestination: { projectDocumentDestination },
                    contactDestination: { projectContactDestination }
                )
            }
        }
    }

    private var projectBookkeepingDestination: some View {
        ProjectDetailPrimaryActionList(
            title: "新增账目",
            systemImage: "plus.circle.fill",
            tint: .pink,
            action: onAddFinancialRecord
        ) {
            projectBookkeepingSection
        }
    }

    private var projectDocumentDestination: some View {
        ProjectDetailPrimaryActionList(
            title: "扫描并添加资料",
            systemImage: "viewfinder",
            tint: .brown,
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
            tint: .blue,
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

    @ViewBuilder
    private var legacyPaymentMigrationSection: some View {
        if legacyPayments.count > 0 {
            Section("旧版收款记录") {
                Text(String(format: String(localized: "检测到 %d 条历史收款记录，建议迁移到\"项目财务流水\"统一管理。"), legacyPayments.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("迁移收款到财务流水") {
                    onMigrateLegacyPayments()
                }
            }
        }
    }
}
