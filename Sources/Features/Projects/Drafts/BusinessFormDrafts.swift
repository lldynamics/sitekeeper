import Foundation

struct DailyLogFormDraft: Codable, Equatable {
    struct Photo: Codable, Equatable {
        var id: UUID
        var note: String
        var tag: PhotoTag
    }
    var recordID: UUID
    var dateText: String
    var weather: String
    var content: String
    var workers: String
    var safety: String
    var materials: String
    var tomorrowPlan: String
    var qualityIssue: String
    var rectification: String
    var confirmer: String
    var linkedMethodIDs: Set<UUID>
    var projectId: UUID?
    var photos: [Photo]

    init(composer: DailyLogComposerState, recordID: UUID) {
        self.recordID = recordID
        dateText = composer.date.storageText
        weather = composer.weather
        content = composer.content
        workers = composer.workers
        safety = composer.safety
        materials = composer.materials
        tomorrowPlan = composer.tomorrowPlan
        qualityIssue = composer.qualityIssue
        rectification = composer.rectification
        confirmer = composer.confirmer
        linkedMethodIDs = composer.linkedMethodIDs
        projectId = composer.projectId
        photos = composer.photoDrafts.map { Photo(id: $0.id, note: $0.note, tag: $0.tag) }
    }

    func composer(store: BusinessDraftStore, key: BusinessDraftStore.Key) throws -> DailyLogComposerState {
        var value = DailyLogComposerState(initialProjectId: projectId, initialDate: Formatters.date.date(from: dateText) ?? Date(), initialContent: content)
        value.date = BusinessDateValue(legacyText: dateText)
        value.weather = weather
        value.workers = workers
        value.safety = safety
        value.materials = materials
        value.tomorrowPlan = tomorrowPlan
        value.qualityIssue = qualityIssue
        value.rectification = rectification
        value.confirmer = confirmer
        value.linkedMethodIDs = linkedMethodIDs
        value.photoDrafts = try photos.map { PhotoDraft(id: $0.id, data: try store.photo(id: $0.id, key: key), note: $0.note, tag: $0.tag) }
        return value
    }
}

struct FinancialFormDraft: Codable, Equatable {
    var baseRecord: Data? = nil
    var recordID: UUID
    @LegacyDraftDate var date: BusinessDateValue
    var direction: ProjectFinancialDirection
    var category: ProjectFinancialCategory
    var amount: String
    var counterparty: String
    var invoiceNumber: String
    var status: ProjectFinancialStatus
    var hasDueDate: Bool
    var dueDateText: String
    var reminderStatus: ProjectFinancialReminderStatus
    var note: String
    var scanAfterSave: Bool
}

/// Older local form drafts encoded Foundation Date as seconds since 2001.
/// That decoding rule is confined to this draft wire adapter; business records
/// continue to encode ISO8601/calendar-day strings in v2/v3 backups.
@propertyWrapper
struct LegacyDraftDate: Codable, Equatable {
    var wrappedValue: BusinessDateValue
    init(wrappedValue: BusinessDateValue) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            wrappedValue = BusinessDateValue(legacyText: text)
        } else {
            let seconds = try container.decode(Double.self)
            guard seconds.isFinite else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid draft date") }
            wrappedValue = .instant(Date(timeIntervalSinceReferenceDate: seconds))
        }
    }
    func encode(to encoder: Encoder) throws { try wrappedValue.encode(to: encoder) }
}
