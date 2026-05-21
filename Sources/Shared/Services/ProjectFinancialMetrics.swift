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

enum ProjectFinancialDuplicateReason: String, CaseIterable {
    case invoiceNumber
    case amountAndDate

    var displayName: String {
        switch self {
        case .invoiceNumber:
            String(localized: "票号相同")
        case .amountAndDate:
            String(localized: "金额和日期相同")
        }
    }
}

struct ProjectFinancialDuplicateWarning: Identifiable {
    let record: ProjectFinancialRecord
    let reasons: [ProjectFinancialDuplicateReason]

    var id: UUID { record.id }

    var reasonText: String {
        reasons.map(\.displayName).joined(separator: " / ")
    }
}

enum ProjectFinancialDuplicateDetector {
    static func warnings(
        for draft: ProjectFinancialRecord,
        in records: [ProjectFinancialRecord],
        ignoring ignoredID: UUID? = nil
    ) -> [ProjectFinancialDuplicateWarning] {
        let draftInvoice = normalizedInvoiceNumber(draft.invoiceNumber)
        let draftDay = normalizedDay(from: draft.date)
        let draftAmount = draft.amountValue

        return records.compactMap { record -> ProjectFinancialDuplicateWarning? in
            guard record.projectId == draft.projectId, record.id != ignoredID else { return nil }
            var reasons: [ProjectFinancialDuplicateReason] = []

            let recordInvoice = normalizedInvoiceNumber(record.invoiceNumber)
            if !draftInvoice.isEmpty, draftInvoice == recordInvoice {
                reasons.append(.invoiceNumber)
            }

            if draft.normalizedDirection == record.normalizedDirection,
               draftAmount.isPositive,
               draftAmount == record.amountValue,
               let draftDay,
               draftDay == normalizedDay(from: record.date) {
                reasons.append(.amountAndDate)
            }

            guard !reasons.isEmpty else { return nil }
            return ProjectFinancialDuplicateWarning(record: record, reasons: reasons)
        }
        .sorted { lhs, rhs in
            let leftHasInvoice = lhs.reasons.contains(.invoiceNumber)
            let rightHasInvoice = rhs.reasons.contains(.invoiceNumber)
            if leftHasInvoice != rightHasInvoice {
                return leftHasInvoice
            }
            return (Formatters.parseDateOrDateTime(lhs.record.date) ?? .distantPast) >
                (Formatters.parseDateOrDateTime(rhs.record.date) ?? .distantPast)
        }
    }

    static func normalizedInvoiceNumber(_ text: String) -> String {
        let normalized = text
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.count >= 6 ? String(normalized) : ""
    }

    static func normalizedDay(from text: String) -> String? {
        guard let date = Formatters.parseDateOrDateTime(text) else { return nil }
        return Formatters.date.string(from: date)
    }
}
