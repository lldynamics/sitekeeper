import Foundation

/// Lossless normalized rows for the candidate stage. JSON payloads are per record;
/// indexed query fields and relationships live in columns/tables, never one database blob.
struct RepositoryDataset: Equatable, Sendable {
    var records: [RepositoryCollection: [RepositoryRecord]] = [:]
    var fields: [String: Data] = [:]

    init(snapshot: BackupSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        var root = try RepositoryJSON.object(data)
        for collection in RepositoryCollection.allCases {
            let objects = root.removeValue(forKey: collection.rawValue) as? [[String: Any]] ?? []
            records[collection] = try objects.enumerated().map { position, object in
                try RepositoryRecord(collection: collection,
                                     payload: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), position: position)
            }
        }
        // Set encoding has no stable order; normalize this set only, preserving ordered arrays.
        if let keys = root["hiddenPresetKeys"] as? [String] { root["hiddenPresetKeys"] = keys.sorted() }
        fields = try root.mapValues { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }
        try validate()
    }

    func snapshot() throws -> BackupSnapshot {
        var root = try fields.mapValues { try JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        for collection in RepositoryCollection.allCases {
            root[collection.rawValue] = try (records[collection] ?? []).sorted { $0.position < $1.position }.map {
                try JSONSerialization.jsonObject(with: $0.payload)
            }
        }
        return try JSONDecoder().decode(BackupSnapshot.self, from: JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]))
    }

    func validate() throws {
        var keys = Set<String>()
        let projects = Set((records[.projects] ?? []).map(\.id))
        for collection in RepositoryCollection.allCases {
            for row in records[collection] ?? [] {
                guard keys.insert(collection.rawValue + "/" + row.id).inserted else {
                    throw RepositoryError.duplicateID(collection.rawValue + "/" + row.id)
                }
                // Historical audit entries may deliberately outlive their project.
                if collection != .historyRecords, let id = row.projectID, !projects.contains(id) {
                    throw RepositoryError.danglingReference(collection.rawValue + "/projectId/" + id)
                }
            }
        }
        let byKey = Dictionary(uniqueKeysWithValues: records.values.flatMap { $0 }.map { ($0.collection.rawValue + "/" + $0.id, $0) })
        for row in records.values.flatMap({ $0 }) {
            for link in try Self.links(for: row) {
                guard let target = byKey[link.target.rawValue + "/" + link.targetID] else {
                    throw RepositoryError.danglingReference(link.field + "/" + link.targetID)
                }
                try Self.checkProjectScope(owner: row, targetProjectID: target.projectID, link: link)
            }
            _ = try Self.attachments(for: row)
        }
    }

    static func checkProjectScope(owner: RepositoryRecord, targetProjectID: String?, link: RepositoryLink) throws {
        guard link.target != .projects, link.target != .constructionMethods else { return }
        if owner.projectID != targetProjectID { throw RepositoryError.crossProjectReference(link.field) }
    }

    static func links(for row: RepositoryRecord) throws -> [RepositoryLink] {
        let object = try RepositoryJSON.object(row.payload)
        var specifications: [(String, RepositoryCollection)] = []
        switch row.collection {
        case .projectDrawings:
            specifications = [("linkedTodoIDs", .siteTodos), ("linkedLogIDs", .dailyLogs), ("linkedDocumentIDs", .projectDocuments)]
        case .projectContacts: specifications = [("relatedProjectIds", .projects)]
        case .dailyLogs, .siteTodos: specifications = [("linkedConstructionMethodIDs", .constructionMethods)]
        case .projectFinancialRecords, .projectWarehouseMovements: specifications = [("linkedDocumentIds", .projectDocuments)]
        case .projectDocuments:
            specifications = [("linkedFinancialRecordId", .projectFinancialRecords), ("replacedByDocumentId", .projectDocuments), ("replacesDocumentId", .projectDocuments), ("linkedConstructionMethodIDs", .constructionMethods)]
        default: break
        }
        return try specifications.flatMap { field, target in
            let values = object[field] as? [String] ?? (object[field] as? String).map { [$0] } ?? []
            return try Set(values).map { raw in
                guard let id = UUID(uuidString: raw) else { throw RepositoryError.invalidRecord(field) }
                return RepositoryLink(owner: row.collection, ownerID: row.id, field: field, target: target, targetID: id.uuidString)
            }
        }
    }

    static func attachments(for row: RepositoryRecord) throws -> [RepositoryAttachment] {
        let object = try RepositoryJSON.object(row.payload)
        var files: [(RepositoryAssetFamily, String)] = []
        func add(_ key: String, _ family: RepositoryAssetFamily) {
            if let name = object[key] as? String, !name.isEmpty { files.append((family, name)) }
        }
        switch row.collection {
        case .dailyLogs:
            add("photoFileName", .photos)
            files += (object["photos"] as? [[String: Any]] ?? []).compactMap { ($0["fileName"] as? String).map { (.photos, $0) } }
        case .siteTodos:
            add("rectificationBeforePhotoFileName", .photos)
            add("rectificationAfterPhotoFileName", .photos)
        case .projectDrawings: add("fileName", .drawings)
        case .projectDocuments: add("fileName", .documents)
        case .quickNotes, .constructionMethods:
            for field in ["attachments", "tutorialAttachments"] {
                files += (object[field] as? [[String: Any]] ?? []).compactMap { ($0["fileName"] as? String).map { (.attachments, $0) } }
            }
        default: break
        }
        var seen = Set<String>()
        return try files.compactMap { family, name in
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
                throw RepositoryError.invalidRecord("attachment filename")
            }
            guard seen.insert(family.rawValue + "/" + name).inserted else { return nil }
            return RepositoryAttachment(owner: row.collection, ownerID: row.id, family: family, fileName: name)
        }
    }
}
