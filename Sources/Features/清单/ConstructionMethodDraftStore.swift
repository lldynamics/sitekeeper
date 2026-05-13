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
        guard let data = UserDefaults.standard.data(forKey: key(for: methodID, scopeID: scopeID)) else { return nil }
        do {
            return try JSONDecoder().decode(ConstructionMethodEditDraft.self, from: data)
        } catch {
            StorageIssueLog.record("施工工艺草稿解析失败：\(error.localizedDescription)")
            return nil
        }
    }

    static func save(_ draft: ConstructionMethodEditDraft, methodID: UUID?, scopeID: UUID) {
        do {
            let data = try JSONEncoder().encode(draft)
            UserDefaults.standard.set(data, forKey: key(for: methodID, scopeID: scopeID))
        } catch {
            StorageIssueLog.record("施工工艺草稿编码失败：\(error.localizedDescription)")
        }
    }

    static func clear(methodID: UUID?, scopeID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: methodID, scopeID: scopeID))
    }
}
