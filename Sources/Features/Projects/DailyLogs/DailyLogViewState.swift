import SwiftUI
import PhotosUI

struct DailyLogComposerState {
    var date: BusinessDateValue = .today()
    var weather: String = ""
    var content: String = ""
    var workers: String = ""
    var safety: String = ""
    var materials: String = ""
    var tomorrowPlan: String = ""
    var qualityIssue: String = ""
    var rectification: String = ""
    var confirmer: String = ""
    var linkedMethodIDs: Set<UUID> = []
    var selectedPhotos: [PhotosPickerItem] = []
    var photoDrafts: [PhotoDraft] = []
    var appliedSeedSourceIDs: Set<UUID> = []
    var showLogCamera = false
    var cameraPhotoTag: PhotoTag = .general
    var projectId: UUID?

    init(
        initialProjectId: UUID? = nil,
        initialDate: Date = Date(),
        initialContent: String = "",
        initialPhotoDrafts: [PhotoDraft] = []
    ) {
        date = .day(CalendarDay(date: initialDate))
        content = initialContent
        photoDrafts = initialPhotoDrafts
        appliedSeedSourceIDs = Set(initialPhotoDrafts.compactMap(\.sourcePhotoID))
        projectId = initialProjectId
    }
}

struct DailyLogPhotoImportSession {
    struct Token: Equatable, Sendable {
        let sessionID: UUID
        let importID: UUID
    }

    private(set) var sessionID = UUID()
    private(set) var activeImportID: UUID?

    var isImporting: Bool {
        activeImportID != nil
    }

    mutating func beginImport() -> Token {
        let importID = UUID()
        activeImportID = importID
        return Token(sessionID: sessionID, importID: importID)
    }

    func accepts(_ token: Token) -> Bool {
        token.sessionID == sessionID && token.importID == activeImportID
    }

    mutating func finishImport(_ token: Token) {
        guard accepts(token) else { return }
        activeImportID = nil
    }

    mutating func reset() {
        sessionID = UUID()
        activeImportID = nil
    }
}

struct DailyLogCalendarIndex {
    private let logsByDate: [CalendarDay: [DailyLog]]

    init(logs: [DailyLog]) {
        var grouped: [CalendarDay: [DailyLog]] = [:]
        for log in logs {
            guard let day = log.date.calendarDay() else { continue }
            grouped[day, default: []].append(log)
        }
        logsByDate = grouped
    }

    func logs(on date: Date) -> [DailyLog] {
        logsByDate[CalendarDay(date: date)] ?? []
    }
}

struct DailyLogEditorState: Codable, Equatable {
    var baseRecord: Data?
    var dateText: String?
    var logId: UUID?
    var date = BusinessDateValue.today()
    var weather = ""
    var content = ""
    var workers = ""
    var safety = ""
    var materials = ""
    var tomorrowPlan = ""
    var qualityIssue = ""
    var rectification = ""
    var confirmer = ""
    var linkedMethodIDs: Set<UUID> = []
    var projectId: UUID?
}

enum DailyLogDateFormatters {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yyyyMM")
        return formatter
    }()

    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    static let accessibilityDayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMMEEEEd")
        return formatter
    }()
}
