import Foundation
import SwiftUI

extension ProjectListView {
    var shouldUseProminentProjectCreateAction: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || projectStore.projects.isEmpty
    }

    func clearAllFilters() {
        searchText = ""
        statusFilter = nil
        overviewFilter = nil
    }

    func handleAutoOpenComposer() {
        guard autoOpenComposerToken > 0,
              autoOpenComposerToken != lastHandledAutoOpenComposerToken else { return }
        lastHandledAutoOpenComposerToken = autoOpenComposerToken
        showAdd = true
        onAutoOpenComposerConsumed(autoOpenComposerToken)
    }

    func deleteProject(keepData: Bool) {
        guard let pid = projectToDelete?.id else { return }
        if keepData {
            archiveProject()
            return
        }

        let projectName = projectToDelete?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedName = projectName.isEmpty ? AppLocalization.string("项目") : projectName
        let relationCount = relatedCount
        let deletion = store.removeProjectCascade(pid)
        guard !deletion.isEmpty else {
            projectToDelete = nil
            return
        }

        projectToDelete = nil
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已删除项目 %@"), normalizedName),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreProjectCascade(deletion)
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: AppLocalization.string("删除项目及全部关联数据"),
                detail: [
                    "\(normalizedName)",
                    "related=\(relationCount)",
                    "records=\(deletion.deletedRecordCount)",
                    "files=\(deletion.deferredFileCleanup?.fileCount ?? 0)"
                ].joined(separator: " · "),
                source: "ProjectListView"
            )
        )
    }

    func archiveProject() {
        guard let pid = projectToDelete?.id,
              let index = projectStore.projects.firstIndex(where: { $0.id == pid }) else { return }
        var project = projectStore.projects[index]
        project.status = .archived
        guard store.updateProject(project) else { return }
        projectToDelete = nil
        store.scheduleSave()
    }

    @discardableResult
    func addProject() -> Bool {
        guard canCreateProject else { return false }
        do {
            try store.createProject(Project(
                name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                location: newLocation,
                status: .active,
                customerName: newCustomerName,
                customerPhone: newCustomerPhone,
                startDate: .day(CalendarDay(date: newStartDate)),
                expectedEndDate: .day(CalendarDay(date: newExpectedEndDate)),
                managerName: newManagerName,
                contractAmount: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(newContractAmount, kind: .amount)),
                paidAmount: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(newPaidAmount, kind: .amount)),
                paymentStatus: newPaymentStatus,
                materialCost: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(newMaterialCost, kind: .amount)),
                laborCost: NumericInputSupport.money(NumericInputSupport.normalizedStorageText(newLaborCost, kind: .amount)),
                requiredDocumentCategories: ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
                    Array(newRequiredDocumentCategories)
                )
            ))
            clearProject()
            return true
        } catch {
            store.persistenceErrorMessage = error.localizedDescription
            return false
        }
    }

    func completeProjectCreation() {
        if addProject() { showAdd = false }
    }

    func clearProject() {
        newName = ""
        newLocation = ""
        newCustomerName = ""
        newCustomerPhone = ""
        newManagerName = ""
        newContractAmount = ""
        newPaidAmount = ""
        newMaterialCost = ""
        newLaborCost = ""
        newPaymentStatus = .unpaid
        newRequiredDocumentCategories = Set(ProjectDocumentRecommendationStage.preConstruction.recommendedCategories)
        newStartDate = Date()
        newExpectedEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    var canCreateProject: Bool {
        store.canEditBusinessData &&
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newRequiredDocumentCategories.isEmpty &&
        InputValidator.validate(newContractAmount, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newPaidAmount, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newMaterialCost, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newLaborCost, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    var relatedCount: Int {
        guard let pid = projectToDelete?.id else { return 0 }
        return store.relatedDataCount(for: pid)
    }

    func expectedEndDate(for project: Project) -> Date {
        Formatters.date.date(from: project.expectedEndDate) ?? .distantFuture
    }

    func paidAmount(for project: Project) -> MoneyValue {
        ProjectFinancialMetrics.paidAmount(project: project, records: projectStore.projectFinancialRecords(for: project.id))
    }

    func customerPhoneURL(for project: Project) -> URL? {
        let raw = project.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        return URL(string: "tel:\(normalized)")
    }

    func unpaidAmount(for project: Project) -> MoneyValue {
        ProjectFinancialMetrics.unpaidAmount(contractAmount: project.contractAmount, paidAmount: paidAmount(for: project))
    }

    func projectRiskBadges(for project: Project) -> [ProjectRiskBadge] {
        var badges: [ProjectRiskBadge] = []
        if hasOverdueItem(for: project) {
            badges.append(ProjectRiskBadge(title: AppLocalization.string("延期"), systemImage: "exclamationmark.triangle.fill", color: .appRisk))
        }
        let todos = openTodoCount(for: project)
        if todos > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: AppLocalization.string("%d待办"), todos),
                systemImage: "checklist",
                color: .appWarning
            ))
        }
        let missingReceipts = unattachedReceiptCount(for: project)
        if missingReceipts > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: AppLocalization.string("%d缺票"), missingReceipts),
                systemImage: "doc.badge.exclamationmark",
                color: .appFinance
            ))
        }
        let priceSpikes = materialPriceSpikeCount(for: project)
        if priceSpikes > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: AppLocalization.string("%d价格异动"), priceSpikes),
                systemImage: "arrow.up.right.circle.fill",
                color: .appFinance
            ))
        }
        if unpaidAmount(for: project) > 0 {
            badges.append(ProjectRiskBadge(title: AppLocalization.string("未收"), systemImage: "yensign.circle.fill", color: .appDoc))
        }
        return Array(badges.prefix(4))
    }

    func applyProjectSuggestion(_ suggestion: RealtimeSearchSuggestion) {
        guard suggestion.category == .project else { return }
        if let project = projectStore.projects.first(where: { $0.id == suggestion.entityId }) {
            searchText = project.name
        } else {
            searchText = suggestion.title
        }
    }

    func hasOverdueItem(for project: Project) -> Bool {
        projectStore.projectActivitySummary(for: project.id).overdueItemCount > 0
    }

    func openTodoCount(for project: Project) -> Int {
        projectStore.projectActivitySummary(for: project.id).openTodoCount
    }

    func unattachedReceiptCount(for project: Project) -> Int {
        projectStore.projectActivitySummary(for: project.id).unattachedReceiptCount
    }

    func hasUnsettledFinancial(for project: Project) -> Bool {
        projectStore.projectActivitySummary(for: project.id).hasUnsettledFinancial
    }

    func hasReceivableAging(for project: Project) -> Bool {
        let context = projectStore.dayContext
        let schedule = ProjectReceivableScheduleSummary(
            project: project,
            records: projectStore.projectFinancialRecords(for: project.id),
            today: context.day,
            timeZone: context.calendar.timeZone
        )
        switch schedule.state {
        case .needsReview: return true
        case .noActiveIncomePlan:
            let amount = unpaidAmount(for: project)
            return !project.contractAmount.isValid || !amount.isValid || amount.isPositive
        case .ready:
            return (schedule.dueUnpaidAmount?.isPositive ?? false)
                || (schedule.futureUnpaidAmount?.isPositive ?? false)
        }
    }

    func hasRecentCollection(for project: Project, withinDays: Int = 30) -> Bool {
        let records = projectStore.projectFinancialRecordsByProjectID[project.id] ?? []
        guard let latest = ProjectFinancialMetrics.latestCollection(records: records, projectName: { _ in project.name }),
              let collectionDate = DataValueParser.parseDate(latest.date) else {
            return false
        }
        let startOfCollectionDay = Calendar.current.startOfDay(for: collectionDate)
        let today = Calendar.current.startOfDay(for: Date())
        let dayDiff = Calendar.current.dateComponents([.day], from: startOfCollectionDay, to: today).day ?? .max
        return dayDiff >= 0 && dayDiff <= max(withinDays, 1)
    }

    func hasCostAnomaly(for project: Project) -> Bool {
        let contract = project.contractAmount
        let materialItems = financeStore.materialItems.filter { $0.projectId == project.id }
        let quoteItems = financeStore.quoteItems.filter { $0.projectId == project.id }
        let laborRecords = financeStore.laborRecords.filter { $0.projectId == project.id }

        let basis = ProjectCostBasisMetrics.summary(project: project, materials: materialItems, labor: laborRecords,
                                                    records: projectStore.projectFinancialRecords(for: project.id))
        guard let materialCost = basis.material.amount, let laborCost = basis.labor.amount else { return true }
        let pendingCount = materialItems.filter { $0.quantity.isZero }.count
            + quoteItems.filter { !$0.unitPrice.isPositive }.count

        let totalCost = materialCost + laborCost
        guard contract > 0 else { return true }
        guard totalCost > 0 else { return pendingCount > 0 }

        let ratio = totalCost / contract
        return ratio >= 0.85 || pendingCount > 0
    }

    func hasLowMarginRisk(for project: Project) -> Bool {
        let contract = project.contractAmount
        guard contract.isValid, contract > 0 else { return true }

        let materialItems = financeStore.materialItems.filter { $0.projectId == project.id }
        let laborRecords = financeStore.laborRecords.filter { $0.projectId == project.id }
        let basis = ProjectCostBasisMetrics.summary(project: project, materials: materialItems, labor: laborRecords,
                                                    records: projectStore.projectFinancialRecords(for: project.id))
        guard let profit = basis.estimatedProfit(contract: contract) else { return true }
        let margin = profit / contract
        return profit < 0 || margin < 0.10
    }

    func materialPriceSpikeCount(for project: Project) -> Int {
        financeStore.materialPriceSpikeCount(for: project.id)
    }

    func missingTodayLog(for project: Project) -> Bool {
        guard project.status.isActiveOrPaused else {
            return false
        }
        return !projectStore.hasTodayLog(for: project.id)
    }

    func recentActivityDate(for project: Project) -> Date {
        let projectId = project.id
        var latest = projectStore.projectActivitySummary(for: projectId).latestActivityDate ?? .distantPast
        if let startDate = Formatters.parseDateOrDateTime(project.startDate) {
            latest = max(latest, startDate)
        }
        if let latestLabor = financeStore.latestLaborDate(for: projectId) {
            latest = max(latest, latestLabor)
        }
        return latest
    }
}
