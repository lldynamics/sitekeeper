import Foundation

struct ConstructionMethodEditDraft: Codable {
    var title: String
    var trade: String
    var versionName: String
    var publishStatus: ConstructionMethod.PublishStatus
    var tutorialBody: String
    var tutorialAttachments: [QuickNoteAttachment]
    var procedureSteps: [String]
    var qualityChecklist: [String]
    var safetyChecklist: [String]
    var attachments: [QuickNoteAttachment]
    var updatedAt: TimeInterval
}

enum ConstructionMethodEditDraftStore {
    private static let keyPrefix = "constructionMethod.editDraft."

    private static func key(for methodID: UUID?, scopeID: UUID) -> String {
        keyPrefix + (methodID?.uuidString ?? "new.\(scopeID.uuidString)")
    }

    static func load(methodID: UUID?, scopeID: UUID) -> ConstructionMethodEditDraft? {
        guard let data = UserDefaults.standard.data(forKey: key(for: methodID, scopeID: scopeID)),
              let value = try? JSONDecoder().decode(ConstructionMethodEditDraft.self, from: data) else { return nil }
        return value
    }

    static func save(_ draft: ConstructionMethodEditDraft, methodID: UUID?, scopeID: UUID) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key(for: methodID, scopeID: scopeID))
    }

    static func clear(methodID: UUID?, scopeID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: methodID, scopeID: scopeID))
    }
}
