import Foundation
import Testing
@testable import sitekeeper

struct FormattersTests {
    @Test(arguments: [
        ("Asia/Shanghai", "2026-10-13T01:30:00+08:00", "2026-10-13", "2026-10-13 01:30"),
        ("America/Los_Angeles", "2026-10-12T23:30:00-07:00", "2026-10-12", "2026-10-12 23:30"),
        ("America/Los_Angeles", "2026-03-08T03:30:00-07:00", "2026-03-08", "2026-03-08 03:30")
    ])
    func businessDatesKeepTheSelectedLocalDay(
        zoneID: String, instantText: String, dayText: String, dateTimeText: String
    ) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        let instant = try #require(ISO8601DateFormatter().date(from: instantText))
        let dayFormatter = Formatters.dateFormatter(timeZone: zone)
        let timeFormatter = Formatters.dateTimeFormatter(timeZone: zone)
        #expect(dayFormatter.string(from: instant) == dayText)
        #expect(timeFormatter.string(from: instant) == dateTimeText)
        #expect(Formatters.parseDateOrDateTime(Formatters.timestamp(instant), timeZone: zone) == instant)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let storedDay = try #require(Formatters.parseDateOrDateTime(dayText, timeZone: zone))
        #expect(storedDay == calendar.startOfDay(for: instant))
        #expect(instant >= storedDay)
        #expect(instant < calendar.date(byAdding: .day, value: 1, to: storedDay)!)
    }

    @Test func defaultBusinessFormattersFollowCurrentTimeZone() {
        #expect(Formatters.date.timeZone == TimeZone.current)
        #expect(Formatters.dateTime.timeZone == TimeZone.current)
        #expect(Formatters.date.calendar.identifier == .gregorian)
    }

    @Test func changingBusinessTimeZoneDoesNotReuseThePreviousZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-12T17:30:00Z"))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(Formatters.dateFormatter(timeZone: shanghai).string(from: instant) == "2026-10-13")
        #expect(Formatters.dateFormatter(timeZone: losAngeles).string(from: instant) == "2026-10-12")
        #expect(Formatters.dateFormatter(timeZone: shanghai).string(from: instant) == "2026-10-13")
    }

    @Test func legacyBusinessTextAndExplicitTimestampsRemainReadable() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let legacyText = "2026-10-12 17:30"
        let legacyDate = try #require(Formatters.parseDateOrDateTime(legacyText, timeZone: zone))
        #expect(Formatters.dateTimeFormatter(timeZone: zone).string(from: legacyDate) == "2026-10-13 01:30")
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-12T17:30:00Z"))
        #expect(Formatters.parseDateOrDateTime("2026-10-13T01:30:00+08:00", timeZone: zone) == expected)
        #expect(Formatters.parseDateOrDateTime("2026-10-12T17:30:00.000Z", timeZone: zone) == expected)
        let fallback = try #require(Formatters.parseDateOrDateTime("2026/10/13 01:30:00", timeZone: zone))
        #expect(Formatters.dateTimeFormatter(timeZone: zone).string(from: fallback) == "2026-10-13 09:30")
    }

    @Test func nowReturnsNonEmpty() {
        let result = Formatters.now()
        #expect(!result.isEmpty)
    }

    @Test func nowFormatIsCorrect() {
        let result = Formatters.now()
        #expect(result.count == 20)
        #expect(result.hasSuffix("Z"))
        #expect(result.contains("-"))
        #expect(result.contains(":"))
        #expect(result.contains(" "))
    }

    @Test func numberInteger() {
        #expect(Formatters.number(42, minFraction: 0, maxFraction: 0) == "42")
        #expect(Formatters.number(1000, minFraction: 0, maxFraction: 0) == "1,000")
    }

    @Test func numberFractional() {
        let r = Formatters.number(3.14159, minFraction: 2, maxFraction: 2)
        #expect(r == "3.14")
    }

    @Test func numberZero() {
        #expect(Formatters.number(0, minFraction: 2, maxFraction: 2) == "0.00")
    }

    @Test func moneyFormat() {
        #expect(Formatters.money(12.5) == "12.50")
        #expect(Formatters.money(0) == "0.00")
        #expect(Formatters.money(1234.567) == "1234.57")
    }

    @Test func moneyNegative() {
        #expect(Formatters.money(-5.1) == "-5.10")
    }

    @Test func projectDateInputNormalizesEditableProjectDates() {
        #expect(ProjectDateInput.normalizedStorageText(" 2026-05-17 ") == "2026-05-17")
        #expect(ProjectDateInput.normalizedStorageText("2026-05-17 08:30") == "2026-05-17")
        #expect(ProjectDateInput.normalizedStorageText("   ") == "")
        #expect(ProjectDateInput.normalizedStorageText("待现场确认") == "待现场确认")
    }
}
