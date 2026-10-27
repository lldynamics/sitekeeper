import Foundation
import Testing
@testable import sitekeeper

struct BusinessDateValueTests {
    @Test(arguments: ["Asia/Shanghai", "America/Los_Angeles", "Pacific/Kiritimati"])
    func civilDaysKeepTheirDayAndInstantsKeepTheirTime(_ zoneID: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        let project = Project(name: "Day", location: "", startDate: BusinessDateValue(legacyText: "2024-02-29"))
        let day = try #require(project.startDate.date(in: zone))
        #expect(Formatters.dateFormatter(timeZone: zone).string(from: day) == "2024-02-29")
        let record = ProjectFinancialRecord(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-13T01:30:00+08:00"))
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-12T17:30:00Z"))
        #expect(record.date.date(in: zone) == instant)
    }

    @Test func legacyAndUnknownDatesRoundTripWithoutInventingInformation() throws {
        let project = Project(name: "Legacy", location: "", startDate: BusinessDateValue(legacyText: "2024/5/1"), expectedEndDate: BusinessDateValue(legacyText: "待确认"))
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(restored.startDate.storageText == "2024/5/1")
        #expect(restored.expectedEndDate.storageText == "待确认")
        #expect(restored.expectedEndDate == .unresolved("待确认"))
        #expect(restored.expectedEndDate.date() == nil)
        #expect(BusinessDateValue(legacyText: "2024-02-30") == .unresolved("2024-02-30"))
        #expect(CalendarDay("2023-02-29") == nil)
    }

    @Test func nativeDateWritesUseISO8601AndTypedDayWritesStayDateOnly() throws {
        var record = ProjectFinancialRecord(projectId: UUID(), date: BusinessDateValue(legacyText: "2026-10-12 17:30"))
        let original = record.date
        let instant = try #require(record.date.date())
        let unchanged = try JSONDecoder().decode(ProjectFinancialRecord.self, from: JSONEncoder().encode(record))
        #expect(unchanged.date == original)
        record.date = .instant(instant)
        #expect(record.date.storageText == "2026-10-12T17:30:00.000Z")
        record.dueDate = .day(try #require(CalendarDay("2026-11-1")))
        #expect(record.dueDate.storageText == "2026-11-01")
        let restored = try JSONDecoder().decode(ProjectFinancialRecord.self, from: JSONEncoder().encode(record))
        #expect(restored.date == record.date)
        #expect(restored.dueDate == record.dueDate)
    }
}
