import Foundation

struct SiteTodoFormDraft: Codable, Equatable {
    var record: SiteTodo
    var baseRecord: Data?
    var beforePhotoID: UUID?
    var afterPhotoID: UUID?
    var afterPhotoSourceID: UUID? = nil

    init(record: SiteTodo, baseRecord: Data? = nil, beforePhotoID: UUID? = nil, afterPhotoID: UUID? = nil, afterPhotoSourceID: UUID? = nil) {
        self.record = record
        self.baseRecord = baseRecord
        self.beforePhotoID = beforePhotoID
        self.afterPhotoID = afterPhotoID
        self.afterPhotoSourceID = afterPhotoSourceID
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        BusinessDraftStore.fingerprint(lhs.record) == BusinessDraftStore.fingerprint(rhs.record)
            && lhs.baseRecord == rhs.baseRecord
            && lhs.beforePhotoID == rhs.beforePhotoID
            && lhs.afterPhotoID == rhs.afterPhotoID
            && lhs.afterPhotoSourceID == rhs.afterPhotoSourceID
    }

    var normalizedRecord: SiteTodo {
        var value = record
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.owner = value.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = value.note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueLocation = value.drawingIssueLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueLayerOrPage = value.drawingIssueLayerOrPage.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueMeasurement = value.drawingIssueMeasurement.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueCloseEvidence = value.drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        value.completedAt = value.isDone ? (value.completedAt ?? .now()) : nil
        return value
    }
}
