import Foundation

enum ProjectDetailMetrics {
    static func paidAmount(
        project: Project,
        relatedFinancialRecords: [ProjectFinancialRecord],
        legacyPayments: [PaymentRecord]
    ) -> Double {
        let paidByFinancialFlow = relatedFinancialRecords.reduce(0) { result, item in
            guard item.direction == ProjectFinancialDirection.income.rawValue else { return result }
            let category = ProjectFinancialCategory(rawValue: item.category)
            guard category == .collection || category == .receipt else { return result }
            return result + ReportBuilder.number(item.amount)
        }
        if paidByFinancialFlow > 0 {
            return paidByFinancialFlow
        }
        if !legacyPayments.isEmpty {
            return legacyPayments.reduce(0) { $0 + ReportBuilder.number($1.amount) }
        }
        return ReportBuilder.number(project.paidAmount)
    }

    static func unpaidAmount(project: Project, paidAmount: Double) -> Double {
        max(ReportBuilder.number(project.contractAmount) - paidAmount, 0)
    }

    static func currentMaterialCost(project: Project, materialCostAuto: Double) -> Double {
        materialCostAuto > 0 ? materialCostAuto : ReportBuilder.number(project.materialCost)
    }

    static func currentLaborCost(project: Project, laborCostAuto: Double) -> Double {
        laborCostAuto > 0 ? laborCostAuto : ReportBuilder.number(project.laborCost)
    }

    static func estimatedProfit(project: Project, materialCost: Double, laborCost: Double) -> Double {
        ReportBuilder.number(project.contractAmount) - materialCost - laborCost
    }

    static func averageProgress(_ tasks: [ProgressTask]) -> Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
    }

    static func trim(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
