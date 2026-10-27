import Foundation

extension RealtimeSearchSuggestionBuilder {
    static func businessSuggestions(
        query: String, categories: Set<RealtimeSearchSuggestion.Category>, quotes: [QuoteItem],
        financialRecords: [ProjectFinancialRecord], drawings: [ProjectDrawing], documents: [ProjectDocument],
        projectID: UUID?, projectNameByID: [UUID: String]
    ) -> [RealtimeSearchSuggestion] {
        var results: [RealtimeSearchSuggestion] = []
        if categories.contains(.quote) {
            results += quotes.filter { projectID == nil || $0.projectId == projectID }.compactMap { item in
                let projectName = item.projectId.flatMap { projectNameByID[$0] } ?? ""
                guard let score = matchScore(query: query, fields: [item.name, item.notes, item.versionName, item.status.displayName, projectName]) else { return nil }
                return RealtimeSearchSuggestion(
                    id: "quote-\(item.id.uuidString)", category: .quote, entityId: item.id,
                    title: normalizedTitle(item.name, fallback: AppLocalization.string("预结算信息")),
                    subtitleParts: [projectName, item.versionName, item.status.displayName], score: score
                )
            }
        }
        if categories.contains(.financial) {
            results += financialRecords.filter { projectID == nil || $0.projectId == projectID }.compactMap { record in
                let projectName = projectNameByID[record.projectId] ?? ""
                guard let score = matchScore(query: query, fields: [record.invoiceNumber, record.counterparty, record.note, record.amount.wireText, record.normalizedCategory.displayName, projectName]) else { return nil }
                return RealtimeSearchSuggestion(
                    id: "financial-\(record.id.uuidString)", category: .financial, entityId: record.id,
                    title: "\(record.normalizedDirection.displayName) \(ReportBuilder.money(record.amount))",
                    subtitleParts: [projectName, record.counterparty, record.invoiceNumber, record.normalizedStatus.displayName], score: score
                )
            }
        }
        if categories.contains(.drawing) {
            results += drawings.filter { projectID == nil || $0.projectId == projectID }.compactMap { drawing in
                let projectName = projectNameByID[drawing.projectId] ?? ""
                guard let score = matchScore(query: query, fields: [drawing.name, drawing.drawingNumber, drawing.fileName, drawing.discipline, drawing.floorArea, drawing.version, drawing.note, projectName]) else { return nil }
                return RealtimeSearchSuggestion(
                    id: "drawing-\(drawing.id.uuidString)", category: .drawing, entityId: drawing.id,
                    title: normalizedTitle(drawing.name, fallback: drawing.fileName),
                    subtitleParts: [projectName, drawing.drawingNumber, drawing.version], score: score
                )
            }
        }
        if categories.contains(.file) {
            results += documents.filter { projectID == nil || $0.projectId == projectID }.compactMap { document in
                let projectName = projectNameByID[document.projectId] ?? ""
                guard let score = matchScore(query: query, fields: [document.title, document.fileName, document.archiveNumber, document.workSection, document.responsiblePerson, document.note, document.category.displayName, projectName]) else { return nil }
                return RealtimeSearchSuggestion(
                    id: "document-\(document.id.uuidString)", category: .file, entityId: document.id,
                    title: normalizedTitle(document.title, fallback: document.fileName),
                    subtitleParts: [projectName, document.archiveNumber, document.category.displayName], score: score
                )
            }
        }
        return results
    }
}
