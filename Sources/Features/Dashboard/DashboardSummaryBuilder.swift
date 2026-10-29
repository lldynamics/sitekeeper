import Foundation

@MainActor
enum DashboardSummaryBuilder {
    /// Pure cold-path entry point, also used by performance and compatibility tests.
    static func build(_ input: DashboardSummaryInput) -> DashboardSummaryModel {
        let context = input.dayContext
        let projects = input.projects.filter { $0.status == .active || $0.status == .paused }
        let projectIDs = Set(projects.map(\.id))
        let names = Dictionary(uniqueKeysWithValues: input.projects.map { ($0.id, $0.name) })
        let todayLogs = input.dailyLogs.filter {
            $0.date.calendarDay(in: context.calendar.timeZone) == context.day
                && ($0.projectId.map(projectIDs.contains) ?? true)
        }
        let openTodos = input.siteTodos.filter {
            !$0.isDone && ($0.projectId.map(projectIDs.contains) ?? false)
        }
        let financialRecords = input.financialRecords.filter { projectIDs.contains($0.projectId) }
        let warehouseMovements = input.warehouseMovements.filter { projectIDs.contains($0.projectId) }
        let stock = projects.flatMap {
            WarehouseStockCalculator.stockLines(
                for: $0.id,
                movements: input.warehouseMovementsByProjectID[$0.id] ?? []
            )
        }
        let linkedRecords = Set(input.documents.compactMap(\.linkedFinancialRecordId))
        let loggedProjects = Set(todayLogs.compactMap(\.projectId))
        let overdueTasks = input.progressTasks.filter {
            projectIDs.contains($0.projectId) && $0.clampedCompletion < 1 && context.isOverdue(date: $0.dueDate)
        }
        let overdueTodos = openTodos.filter { context.isOverdue(date: $0.dueDate) }

        return DashboardSummaryModel(
            activeProjects: projects,
            activeProjectIDs: projectIDs,
            projectNameByID: names,
            todayLogs: todayLogs,
            openTodos: openTodos,
            todayTodos: openTodos.filter { $0.dueDate.calendarDay(in: context.calendar.timeZone) == context.day },
            overdueTasks: overdueTasks,
            overdueTodos: overdueTodos,
            overdueItems: DashboardOverdueItem.sorted(todos: overdueTodos, tasks: overdueTasks, timeZone: context.calendar.timeZone),
            activeFinancialRecords: financialRecords,
            businessSummary: businessSummary(input, projects: projects, projectNames: names),
            warehouseMovements: warehouseMovements,
            warehouseStockLines: stock,
            warehouseTodayMovementCount: warehouseMovements.filter {
                $0.date.calendarDay(in: context.calendar.timeZone) == context.day
            }.count,
            warehouseNegativeCount: stock.filter { $0.quantity.isNegative }.count,
            recentWarehouseMovements: Array(warehouseMovements.sorted { $0.createdAt > $1.createdAt }.prefix(3)),
            projectsWithoutTodayLogCount: projects.filter { !loggedProjects.contains($0.id) }.count,
            unattachedReceiptCount: financialRecords.filter {
                $0.requiresAttachment && $0.linkedDocumentIds.isEmpty && !linkedRecords.contains($0.id)
            }.count,
            unsettledFinancialCount: financialRecords.filter { $0.normalizedStatus == .active && !$0.dueDate.isEmpty }.count,
            materialPriceSpikeCount: projects.reduce(0) { $0 + (input.materialPriceSpikeCountByProjectID[$1.id] ?? 0) }
        )
    }

    private static func businessSummary(
        _ input: DashboardSummaryInput,
        projects: [Project],
        projectNames: [UUID: String]
    ) -> ProjectBusinessSummary {
        var quoteTotal = MoneyValue.zero
        var contractAmount = MoneyValue.zero
        var paidAmount = MoneyValue.zero
        var materialCost = MoneyValue.zero
        var laborCost = MoneyValue.zero
        var collections: [UUID: MoneyValue] = [:]
        var records: [ProjectFinancialRecord] = []
        var pendingMaterialCount = 0
        var unpricedQuoteCount = 0
        var selectedQuote: MoneyValue? = .zero
        var hasQuotes = false
        var quoteReviewCount = 0
        var materialEstimate: MoneyValue? = .zero
        var laborEstimate: MoneyValue? = .zero
        var formalExpense: MoneyValue? = .zero
        var formalExpenseCount = 0
        var contractsAreComplete = true
        var paymentsAreComplete = true
        var duePlanAmount: MoneyValue? = .zero
        var futurePlanAmount: MoneyValue? = .zero
        var readyPlanCount = 0
        var plansNeedingReview = 0
        var projectsWithoutPlan = 0
        for project in projects {
            let quotes = input.quotesByProjectID[project.id] ?? []
            let materials = input.materialsByProjectID[project.id] ?? []
            let labor = input.laborByProjectID[project.id] ?? []
            let financial = input.financialRecordsByProjectID[project.id] ?? []
            records.append(contentsOf: financial)
            let collected = ProjectFinancialMetrics.strictCollectionAmount(financial) ?? MoneyValue(.nan)
            collections[project.id] = collected
            let paid = ProjectFinancialMetrics.effectivePaidAmount(recordedCollectionAmount: collected, manualPaidAmount: project.paidAmount)
            paymentsAreComplete = paymentsAreComplete && paid.isValid
            paidAmount += paid
            contractAmount += project.contractAmount
            quoteTotal += quotes.reduce(MoneyValue.zero) { $0 + ReportBuilder.quoteGrandTotal($1) }
            materialCost += ProjectDetailMetrics.currentMaterialCost(
                project: project,
                materialCostAuto: materials.reduce(MoneyValue.zero) { $0 + ReportBuilder.materialLineTotal($1) },
                hasMaterialDetails: !materials.isEmpty
            )
            laborCost += ProjectDetailMetrics.currentLaborCost(
                project: project,
                laborCostAuto: labor.reduce(MoneyValue.zero) { $0 + ReportBuilder.laborLineTotal($1) },
                hasLaborDetails: !labor.isEmpty
            )
            pendingMaterialCount += materials.filter { $0.quantity.isZero }.count
            unpricedQuoteCount += quotes.filter { !$0.unitPrice.isPositive }.count
            let receivable = ProjectFinancialMetrics.unpaidAmount(contractAmount: project.contractAmount, paidAmount: paid)

            let quote = ProjectBusinessQuoteMetrics(project: project, quotes: quotes)
            if !quotes.isEmpty || project.businessQuoteVersion != nil {
                hasQuotes = true
                if quote.amount == nil { quoteReviewCount += 1 }
                accumulate(quote.amount, into: &selectedQuote)
            }
            let costs = ProjectCostBasisMetrics.summary(project: project, materials: materials, labor: labor, records: financial)
            accumulate(costs.material.amount, into: &materialEstimate)
            accumulate(costs.labor.amount, into: &laborEstimate)
            accumulate(costs.formalExpense, into: &formalExpense)
            formalExpenseCount += costs.formalExpenseCount
            contractsAreComplete = contractsAreComplete && project.contractAmount.isValid && !project.contractAmount.isNegative

            let schedule = ProjectReceivableScheduleSummary(
                project: project, records: financial, today: input.dayContext.day,
                timeZone: input.dayContext.calendar.timeZone
            )
            switch schedule.state {
            case .ready:
                readyPlanCount += 1
                accumulate(schedule.dueUnpaidAmount, into: &duePlanAmount)
                accumulate(schedule.futureUnpaidAmount, into: &futurePlanAmount)
            case .needsReview:
                plansNeedingReview += 1
            case .noActiveIncomePlan:
                if !project.contractAmount.isValid || !receivable.isValid || receivable.isPositive {
                    projectsWithoutPlan += 1
                }
            }
        }
        let profit: MoneyValue?
        if contractsAreComplete, contractAmount.isValid,
           let materialEstimate, let laborEstimate {
            let value = contractAmount - materialEstimate - laborEstimate
            profit = value.isValid ? value : nil
        } else {
            profit = nil
        }
        return ProjectBusinessSummary(
            quoteTotal: quoteTotal,
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: ProjectFinancialMetrics.totalReceivableAmount(projects: projects, recordedCollections: collections),
            recentCollection: ProjectFinancialMetrics.latestCollection(records: records) { projectNames[$0] },
            materialCost: materialCost,
            laborCostAmount: laborCost,
            pendingMaterialCount: pendingMaterialCount,
            unpricedQuoteCount: unpricedQuoteCount,
            scope: ProjectBusinessScope(
                contractAmount: contractsAreComplete && contractAmount.isValid ? contractAmount : nil,
                contractUnpaid: contractsAreComplete && paymentsAreComplete
                    ? ProjectFinancialMetrics.totalReceivableAmount(projects: projects, recordedCollections: collections) : nil,
                selectedQuoteAmount: hasQuotes && quoteReviewCount == 0 ? selectedQuote : nil,
                hasQuotes: hasQuotes,
                quoteProjectsNeedingReview: quoteReviewCount,
                materialEstimate: materialEstimate,
                laborEstimate: laborEstimate,
                formalExpense: formalExpense,
                formalExpenseCount: formalExpenseCount,
                estimatedProfit: profit,
                duePlanAmount: plansNeedingReview == 0 ? duePlanAmount : nil,
                futurePlanAmount: plansNeedingReview == 0 ? futurePlanAmount : nil,
                readyPlanCount: readyPlanCount,
                plansNeedingReview: plansNeedingReview,
                projectsWithoutPlan: projectsWithoutPlan
            )
        )
    }

    private static func accumulate(_ value: MoneyValue?, into total: inout MoneyValue?) {
        guard let current = total, let value else { total = nil; return }
        let next = current + value
        total = next.isValid ? next : nil
    }
}
