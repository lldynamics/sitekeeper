import SwiftUI

struct ProjectDetailOverviewHeader: View {
    let snapshot: ProjectDetailSnapshot
    let statusBinding: Binding<ProjectStatus>
    let showsStatus: Bool
    let onOpenRecordsMetric: () -> Void
    let onAddLog: () -> Void
    let onOpenFinanceFilter: (ProjectFinanceJumpFilter) -> Void
    let onOpenMode: (ProjectDetailMode) -> Void
    let onOpenTodoFilter: () -> Void
    let onOpenDeliveryGuide: () -> Void

    var body: some View {
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
            todayValue: snapshot.hasTodayLog ? AppLocalization.string("已写日志") : AppLocalization.string("未写日志"),
            todayColor: snapshot.hasTodayLog ? .appSuccess : .appWarning,
            riskValue: riskSignalCount(
                unpaidAmount: unpaidAmountValue,
                checklist: documentArchiveChecklist
            ) == 0
                ? AppLocalization.string("正常")
                : String(format: AppLocalization.string("%lld 项"), Int64(riskSignalCount(unpaidAmount: unpaidAmountValue, checklist: documentArchiveChecklist))),
            riskColor: riskSignalCount(unpaidAmount: unpaidAmountValue, checklist: documentArchiveChecklist) == 0 ? .appSuccess : .appRisk,
            pendingValue: pendingSignalCount(checklist: documentArchiveChecklist) == 0
                ? AppLocalization.string("无待处理")
                : String(format: AppLocalization.string("%lld 项"), Int64(pendingSignalCount(checklist: documentArchiveChecklist))),
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

    private func riskSignalCount(unpaidAmount: MoneyValue, checklist: DocumentArchiveChecklistSnapshot) -> Int {
        snapshot.overdueProgressCount
            + snapshot.overdueTodoCount
            + snapshot.missingReceiptCount
            + snapshot.unpricedQuoteCount
            + checklist.missingCount
            + checklist.returnedDocumentCount
            + checklist.legacyDocumentCount
            + (snapshot.hasTodayLog ? 0 : 1)
            + (!unpaidAmount.isValid || unpaidAmount > 0 ? 1 : 0)
    }

    private func pendingSignalCount(checklist: DocumentArchiveChecklistSnapshot) -> Int {
        snapshot.openTodoCount
            + checklist.actionCount
            + checklist.returnedDocumentCount
            + checklist.legacyDocumentCount
    }

    private func openPrimaryRisk(unpaidAmount: MoneyValue, checklist: DocumentArchiveChecklistSnapshot) {
        if snapshot.missingReceiptCount > 0 {
            onOpenFinanceFilter(.missingReceipt)
            return
        }
        if !unpaidAmount.isValid {
            onOpenFinanceFilter(.none)
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
}
