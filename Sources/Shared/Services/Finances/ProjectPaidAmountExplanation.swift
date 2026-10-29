import Foundation

/// A read-only explanation of the existing paid-amount rule. The two inputs
/// remain separate historical sources; this type never adds or migrates them.
struct ProjectPaidAmountExplanation {
    enum Source: Equatable {
        case recordedCollections
        case manualHistory
        case unresolvedCollections

        var displayName: String {
            switch self {
            case .recordedCollections: AppLocalization.string("paid_explanation_source_records")
            case .manualHistory: AppLocalization.string("paid_explanation_source_manual")
            case .unresolvedCollections: AppLocalization.string("paid_explanation_source_review")
            }
        }
    }

    let manualPaidAmount: MoneyValue
    let recordedCollectionAmount: MoneyValue
    let effectivePaidAmount: MoneyValue
    let source: Source

    init(project: Project, records: [ProjectFinancialRecord]) {
        manualPaidAmount = project.paidAmount
        recordedCollectionAmount = ProjectFinancialMetrics.strictCollectionAmount(
            records.filter { $0.projectId == project.id }
        ) ?? MoneyValue(.nan)
        effectivePaidAmount = ProjectFinancialMetrics.effectivePaidAmount(
            recordedCollectionAmount: recordedCollectionAmount,
            manualPaidAmount: manualPaidAmount
        )
        if recordedCollectionAmount.isPositive {
            source = .recordedCollections
        } else if recordedCollectionAmount.isValid || recordedCollectionAmount.isEmpty {
            source = .manualHistory
        } else {
            source = .unresolvedCollections
        }
    }

    var requiresReconciliation: Bool {
        guard let manual = manualPaidAmount.optionalDecimal,
              let recorded = recordedCollectionAmount.optionalDecimal else { return false }
        return manual != recorded
    }

    var requiresAmountReview: Bool {
        (!manualPaidAmount.isValid && !manualPaidAmount.isEmpty)
            || (!recordedCollectionAmount.isValid && !recordedCollectionAmount.isEmpty)
    }
}
