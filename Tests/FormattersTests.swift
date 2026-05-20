import Testing
@testable import sitekeeper

struct FormattersTests {
    @Test func nowReturnsNonEmpty() {
        let result = Formatters.now()
        #expect(!result.isEmpty)
    }

    @Test func nowFormatIsCorrect() {
        let result = Formatters.now()
        #expect(result.count == 16)
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
