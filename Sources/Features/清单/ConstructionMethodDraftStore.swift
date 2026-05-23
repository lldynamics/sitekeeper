import Foundation

struct ConstructionMethodEditDraft: Codable, Sendable {
    var title: String
    var trade: String
    var versionName: String
    var publishStatus: ConstructionMethod.PublishStatus
    var tutorialBody: String
    var tutorialAttachments: [QuickNoteAttachment]
    var procedureSteps: [String]
    var qualityChecklist: [String]
    var safetyChecklist: [String]
    var updatedAt: TimeInterval
}

struct ConstructionMethodEditFormSnapshot {
    var title: String
    var trade: String
    var versionName: String
    var publishStatus: ConstructionMethod.PublishStatus
    var tutorialBody: String
    var tutorialAttachments: [QuickNoteAttachment]
    var procedureSteps: [String]
    var qualityChecklist: [String]
    var safetyChecklist: [String]

    var hasDraftContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !procedureSteps.isEmpty
            || !qualityChecklist.isEmpty
            || !safetyChecklist.isEmpty
            || !tutorialAttachments.isEmpty
    }

    var autosaveFingerprint: String {
        [
            title,
            trade,
            versionName,
            publishStatus.rawValue,
            tutorialBody,
            procedureSteps.joined(separator: "\n"),
            qualityChecklist.joined(separator: "\n"),
            safetyChecklist.joined(separator: "\n"),
            tutorialAttachments.map(\.fileName).joined(separator: "|")
        ].joined(separator: "||")
    }

    var draft: ConstructionMethodEditDraft {
        ConstructionMethodEditDraft(
            title: title,
            trade: trade,
            versionName: versionName,
            publishStatus: publishStatus,
            tutorialBody: tutorialBody,
            tutorialAttachments: tutorialAttachments,
            procedureSteps: procedureSteps,
            qualityChecklist: qualityChecklist,
            safetyChecklist: safetyChecklist,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    func applying(to method: ConstructionMethod?) -> ConstructionMethod {
        var value = method ?? ConstructionMethod()
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.trade = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedVersion = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.versionName = normalizedVersion.isEmpty ? "V1" : normalizedVersion
        value.publishStatus = publishStatus
        value.tutorialBody = tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        value.tutorialTextSize = .normal
        value.tutorialAttachments = tutorialAttachments
        value.procedureSteps = normalizeList(procedureSteps)
        value.qualityChecklist = normalizeList(qualityChecklist)
        value.safetyChecklist = normalizeList(safetyChecklist)
        value.attachments = method?.attachments ?? []
        value.updatedAt = Formatters.now()
        return value
    }

    private func normalizeList(_ items: [String]) -> [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum ConstructionMethodEditDraftStore {
    private static let keyPrefix = UserPreferenceKeys.constructionMethodEditDraftPrefix

    private static func key(for methodID: UUID?, scopeID: UUID) -> String {
        keyPrefix + (methodID?.uuidString ?? "new.\(scopeID.uuidString)")
    }

    static func load(methodID: UUID?, scopeID: UUID) -> ConstructionMethodEditDraft? {
        guard let data = UserPreferencesStore.shared.data(key(for: methodID, scopeID: scopeID)) else { return nil }
        do {
            return try JSONDecoder().decode(ConstructionMethodEditDraft.self, from: data)
        } catch {
            StorageIssueLog.recordEvent(
                "construction_method.draft_decode_failed",
                category: .dataStore,
                details: [
                    "source": "ConstructionMethodEditDraftStore.load",
                    "scope_id": scopeID.uuidString,
                    "method_id": methodID?.uuidString ?? "new",
                    "stored_bytes": "\(data.count)"
                ],
                error: error
            )
            return nil
        }
    }

    static func save(_ draft: ConstructionMethodEditDraft, methodID: UUID?, scopeID: UUID) {
        do {
            let data = try JSONEncoder().encode(draft)
            UserPreferencesStore.shared.set(data, for: key(for: methodID, scopeID: scopeID))
        } catch {
            StorageIssueLog.recordEvent(
                "construction_method.draft_encode_failed",
                category: .dataStore,
                details: [
                    "source": "ConstructionMethodEditDraftStore.save",
                    "scope_id": scopeID.uuidString,
                    "method_id": methodID?.uuidString ?? "new"
                ],
                error: error
            )
        }
    }

    static func clear(methodID: UUID?, scopeID: UUID) {
        UserPreferencesStore.shared.removeObject(for: key(for: methodID, scopeID: scopeID))
    }
}
