import Foundation

/// Each cached collection is bound to a DataStore mutation generation, never to a
/// record count or a timestamp. The on-disk document stays ordinary schema-3 JSON.
struct SnapshotSectionEncoder {
    private struct Fragment {
        let revision: UInt64
        let data: Data
    }
    private var fragments: [String: Fragment] = [:]
    private let maximumCachedBytes: Int
    private(set) var encodedCollections: Set<String> = []
    var cachedByteCount: Int { fragments.values.reduce(0) { $0 + $1.data.count } }

    init(maximumCachedBytes: Int = 32 * 1024 * 1024) {
        self.maximumCachedBytes = max(0, maximumCachedBytes)
    }

    mutating func encode(_ snapshot: BackupSnapshot, versions: [String: UInt64]) throws -> Data {
        encodedCollections = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var fields: [String: Data] = [:]
        func add<T: Encodable>(_ key: String, _ value: T, cacheRevision: UInt64? = nil) throws {
            try Task.checkCancellation()
            if let cacheRevision, let cached = fragments[key], cached.revision == cacheRevision {
                fields[key] = cached.data
            } else {
                let data = try encoder.encode(value)
                fields[key] = data
                if let cacheRevision {
                    fragments[key] = Fragment(revision: cacheRevision, data: data)
                    encodedCollections.insert(key)
                }
            }
        }
        try add("schemaVersion", snapshot.schemaVersion)
        if !snapshot.legacyDateProvenance.isEmpty { try add("legacyDateProvenance", snapshot.legacyDateProvenance) }
        try add("appVersion", snapshot.appVersion)
        try add("appBuild", snapshot.appBuild)
        try add("backupCreatedAt", snapshot.backupCreatedAt)
        try add("materialItems", snapshot.materialItems, cacheRevision: versions["materialItems", default: 0])
        try add("quoteItems", snapshot.quoteItems, cacheRevision: versions["quoteItems", default: 0])
        try add("laborRecords", snapshot.laborRecords, cacheRevision: versions["laborRecords", default: 0])
        try add("projects", snapshot.projects, cacheRevision: versions["projects", default: 0])
        try add("dailyLogs", snapshot.dailyLogs, cacheRevision: versions["dailyLogs", default: 0])
        try add("historyRecords", snapshot.historyRecords, cacheRevision: versions["historyRecords", default: 0])
        try add("progressTasks", snapshot.progressTasks, cacheRevision: versions["progressTasks", default: 0])
        try add("siteTodos", snapshot.siteTodos, cacheRevision: versions["siteTodos", default: 0])
        try add("projectDrawings", snapshot.projectDrawings, cacheRevision: versions["projectDrawings", default: 0])
        try add("projectContacts", snapshot.projectContacts, cacheRevision: versions["projectContacts", default: 0])
        try add("projectFinancialRecords", snapshot.projectFinancialRecords, cacheRevision: versions["projectFinancialRecords", default: 0])
        try add("projectDocuments", snapshot.projectDocuments, cacheRevision: versions["projectDocuments", default: 0])
        try add("quickNotes", snapshot.quickNotes, cacheRevision: versions["quickNotes", default: 0])
        try add("projectWarehouseMovements", snapshot.projectWarehouseMovements, cacheRevision: versions["projectWarehouseMovements", default: 0])
        try add("templates", snapshot.templates, cacheRevision: versions["templates", default: 0])
        try add("materialPriceEntries", snapshot.materialPriceEntries, cacheRevision: versions["materialPriceEntries", default: 0])
        try add("materialSheetDrafts", snapshot.materialSheetDrafts, cacheRevision: versions["materialSheetDrafts", default: 0])
        try add("supplierProfiles", snapshot.supplierProfiles, cacheRevision: versions["supplierProfiles", default: 0])
        try add("constructionMethods", snapshot.constructionMethods, cacheRevision: versions["constructionMethods", default: 0])
        try add("favoriteMaterialKeys", snapshot.favoriteMaterialKeys, cacheRevision: versions["favoriteMaterialKeys", default: 0])
        try add("recentMaterialKeys", snapshot.recentMaterialKeys, cacheRevision: versions["recentMaterialKeys", default: 0])
        try add("userMaterials", snapshot.userMaterials, cacheRevision: versions["userMaterials", default: 0])
        try add("deletedUserMaterials", snapshot.deletedUserMaterials, cacheRevision: versions["deletedUserMaterials", default: 0])
        try add("hiddenPresetKeys", snapshot.hiddenPresetKeys, cacheRevision: versions["hiddenPresetKeys", default: 0])
        try add("photoFiles", snapshot.photoFiles)
        try add("drawingFiles", snapshot.drawingFiles)
        try add("documentFiles", snapshot.documentFiles)
        try add("quickNoteAttachmentFiles", snapshot.quickNoteAttachmentFiles)
        trimCache()
        return try Self.assemble(fields: fields, encoder: encoder)
    }

    private mutating func trimCache() {
        var bytes = cachedByteCount
        for key in fragments.keys.sorted(by: { (fragments[$0]?.data.count ?? 0) > (fragments[$1]?.data.count ?? 0) }) where bytes > maximumCachedBytes {
            bytes -= fragments.removeValue(forKey: key)?.data.count ?? 0
        }
    }

    private static func assemble(fields: [String: Data], encoder: JSONEncoder) throws -> Data {
        var result = Data()
        result.reserveCapacity(fields.values.reduce(2) { $0 + $1.count + 64 })
        result.append(0x7B)
        for (index, key) in fields.keys.sorted().enumerated() {
            if index > 0 { result.append(0x2C) }
            result.append(try encoder.encode(key))
            result.append(0x3A)
            if let data = fields[key] { result.append(data) }
        }
        result.append(0x7D)
        return result
    }
}
