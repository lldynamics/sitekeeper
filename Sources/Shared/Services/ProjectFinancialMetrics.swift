import Foundation

struct CollectionSnapshot {
    let date: String
    let amount: Double
    let projectName: String?
}

struct ProjectFinancialSummary: Equatable {
    let income: Double
    let expense: Double
    let collectionAmount: Double

    var balance: Double { income - expense }
}

enum ProjectFinancialMetrics {
    static func businessRecords(_ records: [ProjectFinancialRecord]) -> [ProjectFinancialRecord] {
        records.filter(\.countsInBusinessMetrics)
    }

    static func income(_ records: [ProjectFinancialRecord]) -> Double {
        summary(records).income
    }

    static func expense(_ records: [ProjectFinancialRecord]) -> Double {
        summary(records).expense
    }

    static func collectionAmount(_ records: [ProjectFinancialRecord]) -> Double {
        summary(records).collectionAmount
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
                income = income + record.amountValue
            case .expense:
                expense = expense + record.amountValue
            }
            if record.isCollectionIncome {
                collection = collection + record.amountValue
            }
        }
        return ProjectFinancialSummary(
            income: income.doubleValue,
            expense: expense.doubleValue,
            collectionAmount: collection.doubleValue
        )
    }

    static func effectivePaidAmount(
        recordedCollectionAmount: Double,
        manualPaidAmount: Double
    ) -> Double {
        recordedCollectionAmount > 0 ? recordedCollectionAmount : max(manualPaidAmount, 0)
    }

    static func paidAmount(
        project: Project,
        records: [ProjectFinancialRecord]
    ) -> Double {
        effectivePaidAmount(
            recordedCollectionAmount: collectionAmount(records),
            manualPaidAmount: project.paidAmountValue.doubleValue
        )
    }

    static func unpaidAmount(
        project: Project,
        records: [ProjectFinancialRecord]
    ) -> Double {
        max(project.contractAmountValue.doubleValue - paidAmount(project: project, records: records), 0)
    }

    static func totalReceivableAmount(
        projects: [Project],
        recordedCollections: [UUID: MoneyValue]
    ) -> Double {
        projects.reduce(MoneyValue.zero) { total, project in
            let recorded = recordedCollections[project.id] ?? .zero
            let paid = recorded.isPositive ? recorded : project.paidAmountValue
            return total + MoneyValue(max(project.contractAmountValue.decimal - paid.decimal, .zero))
        }.doubleValue
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
        ignoring ignoredID: UUID? = nil,
        timeZone: TimeZone = .current
    ) -> [ProjectFinancialDuplicateWarning] {
        let draftInvoice = normalizedInvoiceNumber(draft.invoiceNumber)
        let draftDay = normalizedDay(from: draft.date, timeZone: timeZone)
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

    static func normalizedDay(from text: String, timeZone: TimeZone = .current) -> String? {
        guard let date = Formatters.parseDateOrDateTime(text, timeZone: timeZone) else { return nil }
        return Formatters.dateFormatter(timeZone: timeZone).string(from: date)
    }
}
