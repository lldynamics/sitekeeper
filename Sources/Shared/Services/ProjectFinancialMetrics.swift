import Foundation

struct CollectionSnapshot {
    let date: String
    let amount: Double
    let projectName: String?
}

enum ProjectFinancialMetrics {
    static func businessRecords(_ records: [ProjectFinancialRecord]) -> [ProjectFinancialRecord] {
        records.filter(\.countsInBusinessMetrics)
    }

    static func income(_ records: [ProjectFinancialRecord]) -> Double {
        let total = businessRecords(records)
            .filter { $0.normalizedDirection == .income }
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
        return total.doubleValue
    }

    static func expense(_ records: [ProjectFinancialRecord]) -> Double {
        let total = businessRecords(records)
            .filter { $0.normalizedDirection == .expense }
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
        return total.doubleValue
    }

    static func collectionAmount(_ records: [ProjectFinancialRecord]) -> Double {
        let total = businessRecords(records)
            .filter(\.isCollectionIncome)
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
        return total.doubleValue
    }

    static func latestCollection(
        records: [ProjectFinancialRecord],
        projectName: (UUID) -> String?
    ) -> CollectionSnapshot? {
        businessRecords(records)
            .filter(\.isCollectionIncome)
            .map {
                CollectionSnapshot(
                    date: $0.date,
                    amount: $0.amountValue.doubleValue,
                    projectName: projectName($0.projectId)
                )
            }
            .max { lhs, rhs in
                (DataValueParser.parseDate(lhs.date) ?? .distantPast) <
                    (DataValueParser.parseDate(rhs.date) ?? .distantPast)
            }
    }
}
