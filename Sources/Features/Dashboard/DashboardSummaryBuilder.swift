import Foundation

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

        return DashboardSummaryModel(
            activeProjects: projects,
            activeProjectIDs: projectIDs,
            projectNameByID: names,
            todayLogs: todayLogs,
            openTodos: openTodos,
            todayTodos: openTodos.filter { $0.dueDate.calendarDay(in: context.calendar.timeZone) == context.day },
            overdueTasks: input.progressTasks.filter {
                projectIDs.contains($0.projectId) && $0.clampedCompletion < 1 && context.isOverdue(date: $0.dueDate)
            },
            overdueTodos: openTodos.filter { context.isOverdue(date: $0.dueDate) },
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
        var maximumReceivableAgeDays: Int?
        for project in projects {
            let quotes = input.quotesByProjectID[project.id] ?? []
            let materials = input.materialsByProjectID[project.id] ?? []
            let labor = input.laborByProjectID[project.id] ?? []
            let financial = input.financialRecordsByProjectID[project.id] ?? []
            records.append(contentsOf: financial)
            let collected = financial.reduce(MoneyValue.zero) { total, record in
                record.countsInBusinessMetrics && record.isCollectionIncome ? total + record.amount : total
            }
            collections[project.id] = collected
            let paid = ProjectFinancialMetrics.effectivePaidAmount(recordedCollectionAmount: collected, manualPaidAmount: project.paidAmount)
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
            if let age = receivableAgeDays(project: project, receivable: receivable, context: input.dayContext) {
                maximumReceivableAgeDays = max(maximumReceivableAgeDays ?? age, age)
            }
        }
        return ProjectBusinessSummary(
            quoteTotal: quoteTotal,
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: ProjectFinancialMetrics.totalReceivableAmount(projects: projects, recordedCollections: collections),
            receivableAgeDays: maximumReceivableAgeDays,
            recentCollection: ProjectFinancialMetrics.latestCollection(records: records) { projectNames[$0] },
            materialCost: materialCost,
            laborCostAmount: laborCost,
            pendingMaterialCount: pendingMaterialCount,
            unpricedQuoteCount: unpricedQuoteCount
        )
    }

    private static func receivableAgeDays(project: Project, receivable: MoneyValue, context: ProjectDayContext) -> Int? {
        guard receivable > 0,
              let endDate = project.expectedEndDate.date(in: context.calendar.timeZone) else { return nil }
        let due = context.calendar.startOfDay(for: endDate)
        return max(context.calendar.dateComponents([.day], from: due, to: context.dayStart).day ?? 0, 0)
    }
}
