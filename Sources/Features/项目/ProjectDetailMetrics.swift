import Foundation

enum ProjectDetailMetrics {
    static func paidAmount(
        project: Project,
        relatedFinancialRecords: [ProjectFinancialRecord]
    ) -> Double {
        ProjectFinancialMetrics.paidAmount(project: project, records: relatedFinancialRecords)
    }

    static func unpaidAmount(project: Project, paidAmount: Double) -> Double {
        max(project.contractAmountValue.doubleValue - paidAmount, 0)
    }

    static func currentMaterialCost(project: Project, materialCostAuto: Double) -> Double {
        materialCostAuto > 0 ? materialCostAuto : project.materialCostValue.doubleValue
    }

    static func currentLaborCost(project: Project, laborCostAuto: Double) -> Double {
        laborCostAuto > 0 ? laborCostAuto : project.laborCostValue.doubleValue
    }

    static func estimatedProfit(project: Project, materialCost: Double, laborCost: Double) -> Double {
        project.contractAmountValue.doubleValue - materialCost - laborCost
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
