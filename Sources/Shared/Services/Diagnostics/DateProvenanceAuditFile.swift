import Foundation

/// Local audit of legacy date text, kept beside the store so ordinary saves do not rewrite it.
/// Backups still carry the entries inside their snapshot; `missingSince` stays on this device.
struct DateProvenanceAuditFile: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var provenance: LegacyDateProvenance
        /// First load at which the owning record was absent; cleared when it comes back.
        var missingSince: Date?
    }

    static let currentVersion = 1
    /// Matches the longest recycle-bin retention, so records that can still be restored keep
    /// their audit. Deletions inside a session stay untouched while their undo window is open.
    static let missingRecordRetention: TimeInterval = 30 * 24 * 60 * 60

    var version = currentVersion
    var entries: [Entry] = []

    static func fileURL(forStore storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("sitekeeper_date_provenance.json")
    }

    /// Merges file entries with entries still embedded in the store, then marks, revives or
    /// drops record-scoped entries by whether the owning record exists.
    static func reconciled(
        file: [Entry],
        inline: [LegacyDateProvenance],
        liveRecordIDs: [String: Set<UUID>],
        now: Date
    ) -> [Entry] {
        var seen = Set<LegacyDateProvenance>()
        let merged = file.filter { seen.insert($0.provenance).inserted }
            + inline.filter { seen.insert($0).inserted }.map { Entry(provenance: $0) }
        return merged.compactMap { entry in
            var entry = entry
            guard let owner = entry.provenance.recordOwner,
                  let liveIDs = liveRecordIDs[owner.collection],
                  !liveIDs.contains(owner.id) else {
                entry.missingSince = nil
                return entry
            }
            let missingSince = entry.missingSince ?? now
            guard now.timeIntervalSince(missingSince) < missingRecordRetention else { return nil }
            entry.missingSince = missingSince
            return entry
        }
    }
}

extension LegacyDateProvenance {
    /// Top-level collection and record ID from `collection/<UUID>/…`, or nil for
    /// snapshot-level text such as `snapshot/backupCreatedAt`.
    var recordOwner: (collection: String, id: UUID)? {
        let parts = path.split(separator: "/", maxSplits: 2)
        guard parts.count >= 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        return (String(parts[0]), id)
    }
}

extension BackupSnapshot {
    /// Record IDs for every collection whose dates `LegacyDateProvenance.capture` audits.
    var liveRecordIDs: [String: Set<UUID>] {
        [
            "materialItems": Set(materialItems.map(\.id)),
            "quoteItems": Set(quoteItems.map(\.id)),
            "laborRecords": Set(laborRecords.map(\.id)),
            "projects": Set(projects.map(\.id)),
            "dailyLogs": Set(dailyLogs.map(\.id)),
            "historyRecords": Set(historyRecords.map(\.id)),
            "progressTasks": Set(progressTasks.map(\.id)),
            "siteTodos": Set(siteTodos.map(\.id)),
            "projectDrawings": Set(projectDrawings.map(\.id)),
            "projectFinancialRecords": Set(projectFinancialRecords.map(\.id)),
            "projectDocuments": Set(projectDocuments.map(\.id)),
            "quickNotes": Set(quickNotes.map(\.id)),
            "projectWarehouseMovements": Set(projectWarehouseMovements.map(\.id)),
            "materialPriceEntries": Set(materialPriceEntries.map(\.id)),
            "materialSheetDrafts": Set(materialSheetDrafts.map(\.id)),
            "supplierProfiles": Set(supplierProfiles.map(\.id)),
            "constructionMethods": Set(constructionMethods.map(\.id))
        ]
    }
}
