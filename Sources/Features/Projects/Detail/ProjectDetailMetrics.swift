import Foundation

enum ProjectDetailMetrics {
    static func paidAmount(
        project: Project,
        relatedFinancialRecords: [ProjectFinancialRecord]
    ) -> MoneyValue {
        ProjectFinancialMetrics.paidAmount(project: project, records: relatedFinancialRecords)
    }

    static func unpaidAmount(project: Project, paidAmount: MoneyValue) -> MoneyValue {
        ProjectFinancialMetrics.unpaidAmount(contractAmount: project.contractAmount, paidAmount: paidAmount)
    }

    static func currentMaterialCost(
        project: Project,
        materialCostAuto: MoneyValue,
        hasMaterialDetails: Bool
    ) -> MoneyValue {
        hasMaterialDetails ? materialCostAuto : project.materialCost
    }

    static func currentLaborCost(
        project: Project,
        laborCostAuto: MoneyValue,
        hasLaborDetails: Bool
    ) -> MoneyValue {
        hasLaborDetails ? laborCostAuto : project.laborCost
    }

    static func estimatedProfit(project: Project, materialCost: MoneyValue, laborCost: MoneyValue) -> MoneyValue {
        project.contractAmount - materialCost - laborCost
    }

    static func averageProgress(_ tasks: [ProgressTask]) -> Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
    }

    static func trim(_ value: QuantityValue) -> String {
        value.decimal.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Estimates and formal expenses are separate views of different records.
/// In particular, an empty price is not a zero price, and an incomplete
/// detail list must never fall back to an older manually entered total.
struct ProjectCostComponent {
    enum Source: Equatable {
        case details
        case manual
        case unavailable
    }

    let source: Source
    let amount: MoneyValue?
    let incompleteCount: Int
}

struct ProjectCostBasisSummary {
    let material: ProjectCostComponent
    let labor: ProjectCostComponent
    let formalExpense: MoneyValue?
    let formalExpenseCount: Int
    let incompleteExpenseCount: Int

    func estimatedProfit(contract: MoneyValue) -> MoneyValue? {
        guard contract.isValid, !contract.isNegative,
              let materialAmount = material.amount, let laborAmount = labor.amount else { return nil }
        let value = contract - materialAmount - laborAmount
        return value.isValid ? value : nil
    }
}

enum ProjectCostBasisMetrics {
    static func summary(project: Project, materials: [MaterialItem], labor: [LaborRecord],
                        records: [ProjectFinancialRecord]) -> ProjectCostBasisSummary {
        let projectMaterials = materials.filter { $0.projectId == project.id }
        let projectLabor = labor.filter { $0.projectId == project.id }
        let expenses = records.filter { $0.projectId == project.id && $0.countsInBusinessMetrics && $0.isExpenseDirection }

        let material = component(manual: project.materialCost, values: projectMaterials.map { item in
            guard item.quantity.isValid, item.unitPrice.isValid,
                  !item.quantity.isNegative, !item.unitPrice.isNegative else { return nil }
            let total = ReportBuilder.materialLineTotal(item)
            return total.isValid ? total : nil
        })
        let laborCost = component(manual: project.laborCost, values: projectLabor.map { item in
            // Historical empty worker counts retain the existing one-person convention.
            guard item.workloadUnit != .legacyUnspecified,
                  (item.workers.isValid || item.workers.isEmpty), item.hours.isValid, item.unitRate.isValid,
                  !item.workers.isNegative, !item.hours.isNegative, !item.unitRate.isNegative else { return nil }
            let total = ReportBuilder.laborLineTotal(item)
            return total.isValid ? total : nil
        })
        let expenseValues: [MoneyValue?] = expenses.map { record in
            guard record.amount.isValid, !record.amount.isNegative else { return nil }
            return record.amount
        }
        let expense = sumComplete(expenseValues)
        return ProjectCostBasisSummary(
            material: material,
            labor: laborCost,
            formalExpense: expense,
            formalExpenseCount: expenses.count,
            incompleteExpenseCount: expenseValues.filter { $0 == nil }.count + (expense == nil && expenseValues.allSatisfy { $0 != nil } ? 1 : 0)
        )
    }

    private static func component(manual: MoneyValue, values: [MoneyValue?]) -> ProjectCostComponent {
        guard !values.isEmpty else {
            let amount = manual.isValid && !manual.isNegative ? manual : nil
            return ProjectCostComponent(source: amount == nil ? .unavailable : .manual, amount: amount, incompleteCount: amount == nil ? 1 : 0)
        }
        let amount = sumComplete(values)
        let missing = values.filter { $0 == nil }.count
        return ProjectCostComponent(source: .details, amount: amount,
                                    incompleteCount: missing + (amount == nil && missing == 0 ? 1 : 0))
    }

    private static func sumComplete(_ values: [MoneyValue?]) -> MoneyValue? {
        var total = MoneyValue.zero
        for value in values {
            guard let value else { return nil }
            total += value
            guard total.isValid else { return nil }
        }
        return total
    }
}
