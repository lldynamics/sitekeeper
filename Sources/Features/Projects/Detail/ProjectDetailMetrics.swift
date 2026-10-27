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
