import Foundation

/// An immutable audit of v2 text, not a replacement for the live record.
/// Date-only values have no recoverable capture time or zone: keep their calendar day.
struct LegacyDateProvenance: Codable, Hashable, Sendable {
    let path: String
    let originalText: String
    let interpretation: String
    let sourceSchemaVersion: Int

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
        init(stringValue: String) { self.stringValue = stringValue }
    }

    static func capture(from decoder: Decoder) throws -> [Self] {
        var result: [Self] = []
        let fields: Set<String> = [
            "date", "arrivalDate", "exportDate", "createdAt", "updatedAt", "customerConfirmedDate",
            "startDate", "expectedEndDate", "dueDate", "completedAt", "changedAt", "formedAt",
            "issuedAt", "relatedLogDate", "fileAvailabilityCheckedAt", "externalOpenFailedAt",
            "importedAt", "sourceUpdatedAt", "backupCreatedAt"
        ]
        func visit(_ decoder: Decoder, path: String) throws {
            if let object = try? decoder.container(keyedBy: Key.self) {
                let identifier = try? object.decode(String.self, forKey: Key(stringValue: "id"))
                let recordPath = identifier.map { path + "/" + $0 } ?? path
                for key in object.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                    if fields.contains(key.stringValue), let text = try? object.decode(String.self, forKey: key), !text.isEmpty {
                        let kind: String
                        if text.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, options: .regularExpression) != nil {
                            kind = "calendar-day-preserved-origin-unverified"
                        } else if text.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2} \d{2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil {
                            kind = "legacy-UTC"
                        } else {
                            kind = "explicit-zone-or-unrecognized-preserved"
                        }
                        result.append(Self(path: recordPath + "/" + key.stringValue, originalText: text,
                                           interpretation: kind, sourceSchemaVersion: 2))
                    } else {
                        try visit(object.superDecoder(forKey: key), path: recordPath + "/" + key.stringValue)
                    }
                }
            } else if var array = try? decoder.unkeyedContainer() {
                while !array.isAtEnd {
                    try visit(array.superDecoder(), path: path)
                }
            }
        }
        let root = try decoder.container(keyedBy: Key.self)
        // Inspect original JSON, not decoded model defaults, and never attachment bytes.
        let collections = ["materialItems", "quoteItems", "laborRecords", "projects", "dailyLogs",
                           "historyRecords", "progressTasks", "siteTodos", "projectDrawings",
                           "projectFinancialRecords", "projectDocuments", "quickNotes", "projectWarehouseMovements",
                           "materialPriceEntries", "materialSheetDrafts", "supplierProfiles", "constructionMethods"]
        for name in collections {
            let key = Key(stringValue: name)
            if root.contains(key) { try visit(root.superDecoder(forKey: key), path: name) }
        }
        if let text = try root.decodeIfPresent(String.self, forKey: Key(stringValue: "backupCreatedAt")), !text.isEmpty {
            result.append(Self(path: "snapshot/backupCreatedAt", originalText: text,
                               interpretation: "legacy-UTC-or-explicit-zone", sourceSchemaVersion: 2))
        }
        return result
    }
}
