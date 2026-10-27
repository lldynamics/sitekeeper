import Foundation

struct ProjectDocumentMatchSuggestion: Identifiable {
    let id = UUID()
    let document: ProjectDocument
    let record: ProjectFinancialRecord
    let score: Int
}

struct FinancialRecordDocumentSuggestion: Identifiable {
    let id = UUID()
    let document: ProjectDocument
    let score: Int
}

enum ProjectFinancialDocumentMatcher {
    static func bestMatch(
        for document: ProjectDocument,
        in records: [ProjectFinancialRecord]
    ) -> ProjectDocumentMatchSuggestion? {
        records
            .compactMap { record -> ProjectDocumentMatchSuggestion? in
                let score = score(document: document, record: record)
                guard score >= 3 else { return nil }
                return ProjectDocumentMatchSuggestion(document: document, record: record, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return Formatters.isLater(lhs.record.date, than: rhs.record.date)
            }
            .first
    }

    static func suggestedDocuments(
        for record: ProjectFinancialRecord,
        in documents: [ProjectDocument],
        limit: Int = 5
    ) -> [FinancialRecordDocumentSuggestion] {
        documents
            .compactMap { document -> FinancialRecordDocumentSuggestion? in
                let score = score(document: document, record: record)
                guard score >= 3 else { return nil }
                return FinancialRecordDocumentSuggestion(document: document, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return Formatters.isLater(lhs.document.createdAt, than: rhs.document.createdAt)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(document: ProjectDocument, record: ProjectFinancialRecord) -> Int {
        var score = 0
        let docAmount = document.amount
        let recordAmount = record.amount
        let amountDelta = (recordAmount - docAmount).magnitude

        if docAmount > 0 {
            if amountDelta <= 1 {
                score += 4
            } else if amountDelta <= max(1, docAmount * 0.02) {
                score += 3
            } else if amountDelta <= max(2, docAmount * 0.05) {
                score += 1
            }
        }

        if let docDate = parseDate(document.createdAt),
           let recordDate = parseDate(record.date) {
            let dayDelta = abs(Calendar.current.dateComponents([.day], from: docDate, to: recordDate).day ?? 99)
            if dayDelta <= 3 {
                score += 2
            } else if dayDelta <= 7 {
                score += 1
            }
        }

        let counterparty = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let documentText = [document.title, document.note]
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !counterparty.isEmpty, documentText.contains(counterparty) {
            score += 2
        }

        if document.category.matchesFinancialCategory(record.category) {
            score += 1
        }

        return score
    }

    private static func parseDate(_ text: BusinessDateValue) -> Date? {
        if let dt = Formatters.parseDateOrDateTime(text) {
            return dt
        }
        return Formatters.date.date(from: text)
    }
}

extension ProjectDocumentCategory {
    func matchesFinancialCategory(_ category: ProjectFinancialCategory) -> Bool {
        switch self {
        case .invoice:
            return category == .invoice
        case .receipt:
            return category == .receipt
        case .paymentRequest:
            return category == .paymentRequest
        case .construction:
            return category == .material
                || category == .labor
        case .constructionMaterial:
            return category == .material
        case .constructionRecord:
            return category == .labor
        case .constructionTechnical,
             .constructionSurvey,
             .constructionTest,
             .constructionManagement,
             .processAcceptance,
             .completionAcceptance:
            return false
        case .contract, .acceptance, .other:
            return false
        }
    }
}
