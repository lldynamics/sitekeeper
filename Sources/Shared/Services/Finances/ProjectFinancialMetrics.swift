import Foundation

struct CollectionSnapshot {
    let date: BusinessDateValue
    let amount: MoneyValue
    let projectName: String?
}

struct ProjectFinancialSummary: Equatable {
    let income: MoneyValue
    let expense: MoneyValue
    let collectionAmount: MoneyValue
    var balance: MoneyValue { income - expense }
}

enum ProjectFinancialMetrics {
    static func businessRecords(_ records: [ProjectFinancialRecord]) -> [ProjectFinancialRecord] {
        records.filter(\.countsInBusinessMetrics)
    }

    static func income(_ records: [ProjectFinancialRecord]) -> MoneyValue {
        summary(records).income
    }

    static func expense(_ records: [ProjectFinancialRecord]) -> MoneyValue {
        summary(records).expense
    }

    static func collectionAmount(_ records: [ProjectFinancialRecord]) -> MoneyValue {
        summary(records).collectionAmount
    }

    /// Empty historical amounts are unknown, not zero. Keep the existing
    /// generic ledger summary intact for callers that use its legacy contract.
    static func strictCollectionAmount(_ records: [ProjectFinancialRecord]) -> MoneyValue? {
        var total = MoneyValue.zero
        for record in records where record.countsInBusinessMetrics && record.isCollectionIncome {
            guard record.amount.isValid, !record.amount.isNegative else { return nil }
            total += record.amount
            guard total.isValid else { return nil }
        }
        return total
    }

    static func missingReceiptRecords(
        _ records: [ProjectFinancialRecord],
        hasLinkedDocument: (ProjectFinancialRecord) -> Bool
    ) -> [ProjectFinancialRecord] {
        businessRecords(records).filter { record in
            record.requiresAttachment && !hasLinkedDocument(record)
        }
    }

    static func summary(_ records: [ProjectFinancialRecord]) -> ProjectFinancialSummary {
        var income = MoneyValue.zero
        var expense = MoneyValue.zero
        var collection = MoneyValue.zero
        for record in records where record.countsInBusinessMetrics {
            switch record.normalizedDirection {
            case .income:
                income = income + record.amount
            case .expense:
                expense = expense + record.amount
            }
            if record.isCollectionIncome {
                collection = collection + record.amount
            }
        }
        return ProjectFinancialSummary(
            income: income,
            expense: expense,
            collectionAmount: collection
        )
    }

    static func effectivePaidAmount(
        recordedCollectionAmount: MoneyValue,
        manualPaidAmount: MoneyValue
    ) -> MoneyValue {
        guard recordedCollectionAmount.isValid || recordedCollectionAmount.isEmpty else { return recordedCollectionAmount }
        return recordedCollectionAmount.isPositive ? recordedCollectionAmount : nonNegative(manualPaidAmount)
    }

    static func paidAmount(project: Project, records: [ProjectFinancialRecord]) -> MoneyValue {
        guard let collection = strictCollectionAmount(records.filter { $0.projectId == project.id }) else {
            return MoneyValue(.nan)
        }
        return effectivePaidAmount(recordedCollectionAmount: collection, manualPaidAmount: project.paidAmount)
    }

    static func unpaidAmount(project: Project, records: [ProjectFinancialRecord]) -> MoneyValue {
        unpaidAmount(contractAmount: project.contractAmount, paidAmount: paidAmount(project: project, records: records))
    }

    /// Clamp valid overpayments only. Unknown legacy amounts must remain unknown.
    static func unpaidAmount(contractAmount: MoneyValue, paidAmount: MoneyValue) -> MoneyValue {
        guard contractAmount.isValid, paidAmount.isValid else { return MoneyValue(.nan) }
        return nonNegative(contractAmount - paidAmount)
    }

    static func totalReceivableAmount(
        projects: [Project],
        recordedCollections: [UUID: MoneyValue]
    ) -> MoneyValue {
        projects.reduce(MoneyValue.zero) { total, project in
            let recorded = recordedCollections[project.id] ?? .zero
            let paid = effectivePaidAmount(recordedCollectionAmount: recorded, manualPaidAmount: project.paidAmount)
            return total + unpaidAmount(contractAmount: project.contractAmount, paidAmount: paid)
        }
    }

    private static func nonNegative(_ amount: MoneyValue) -> MoneyValue {
        guard let value = amount.optionalDecimal else { return amount.isEmpty ? .zero : amount }
        return MoneyValue(max(value, .zero))
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
                    amount: $0.amount,
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
            AppLocalization.string("票号相同")
        case .amountAndDate:
            AppLocalization.string("金额和日期相同")
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
        ignoring ignoredID: UUID? = nil,
        timeZone: TimeZone = .current
    ) -> [ProjectFinancialDuplicateWarning] {
        let draftInvoice = normalizedInvoiceNumber(draft.invoiceNumber)
        let draftDay = normalizedDay(from: draft.date, timeZone: timeZone)
        let draftAmount = draft.amount

        return records.compactMap { record -> ProjectFinancialDuplicateWarning? in
            guard record.projectId == draft.projectId, record.id != ignoredID else { return nil }
            var reasons: [ProjectFinancialDuplicateReason] = []

            let recordInvoice = normalizedInvoiceNumber(record.invoiceNumber)
            if !draftInvoice.isEmpty, draftInvoice == recordInvoice {
                reasons.append(.invoiceNumber)
            }

            if draft.normalizedDirection == record.normalizedDirection,
               draftAmount.isPositive,
               draftAmount == record.amount,
               let draftDay,
               draftDay == normalizedDay(from: record.date, timeZone: timeZone) {
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

    static func normalizedDay(from value: BusinessDateValue, timeZone: TimeZone = .current) -> String? {
        value.calendarDay(in: timeZone)?.storageText
    }
}
