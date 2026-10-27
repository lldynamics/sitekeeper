import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct LaborDomainLogicTests {
    @Test func laborCostDistinguishesMissingWorkersFromExplicitZero() {
        let historicalMissingWorkers = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-09"),
            workers: NumericInputSupport.quantity(""),
            hours: NumericInputSupport.quantity("1"),
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let explicitZeroWorkers = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-09"),
            workers: NumericInputSupport.quantity("0"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )

        #expect(ReportBuilder.laborLineTotal(historicalMissingWorkers) == 300)
        #expect(ReportBuilder.laborLineTotal(explicitZeroWorkers) == 0)
    }

    @Test func legacyLaborUnitRequiresConfirmationAndRoundTrips() throws {
        let legacyJSON = """
        {
          "date": "2026-09-09",
          "workers": "2",
          "hours": "8",
          "unitRate": "50",
          "note": ""
        }
        """.data(using: .utf8)!

        let legacy = try JSONDecoder().decode(LaborRecord.self, from: legacyJSON)
        #expect(legacy.workloadUnit == .legacyUnspecified)
        #expect(legacy.hours.wireText == "8")
        #expect(ReportBuilder.laborLineTotal(legacy) == 800)
        #expect(LaborQuoteGenerator.makeQuoteItem(from: legacy, defaultRate: NumericInputSupport.money(""), taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0")) == nil)

        let restored = try JSONDecoder().decode(LaborRecord.self, from: JSONEncoder().encode(legacy))
        #expect(restored.workloadUnit == .legacyUnspecified)
        #expect(restored.hours == legacy.hours)
    }

    @Test func confirmedWorkdayLaborCreatesWorkdayQuotation() throws {
        let record = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-09"),
            workers: NumericInputSupport.quantity("2"),
            hours: NumericInputSupport.quantity("1.5"),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: NumericInputSupport.money(""),
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0")
        ))

        #expect(quote.quantity.wireText == "3")
        #expect(quote.unit == record.workloadUnit.quoteUnit)
        #expect(quote.unitPrice.wireText == "300")
    }

    @Test func fractionalWorkdayQuotationPreservesLaborAmountWhenUsingRecordedRate() throws {
        let record = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-10-13"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("0.125"),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: NumericInputSupport.money("   "),
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0")
        ))

        #expect(quote.quantity == record.totalWorkload)
        #expect(quote.unitPrice == NumericInputSupport.money("300"))
        #expect(ReportBuilder.quoteGrandTotal(quote) == NumericInputSupport.money("37.50"))
        #expect(ReportBuilder.quoteGrandTotal(quote) == ReportBuilder.laborLineTotal(record))
    }

    @Test(arguments: [
        ("1", "0.1234", "0.1234", "37.02"),
        ("7", "0.1234", "0.8638", "259.14"),
        ("3", "1.2345", "3.7035", "1111.05")
    ])
    func quotationPreservesFourDecimalWorkloadAndMultipliesWorkers(
        workers: String,
        days: String,
        expectedWorkload: String,
        expectedAmount: String
    ) throws {
        let record = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-10-13"),
            workers: NumericInputSupport.quantity(workers),
            hours: NumericInputSupport.quantity(days),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: NumericInputSupport.money(""),
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0")
        ))

        #expect(quote.quantity == NumericInputSupport.quantity(expectedWorkload))
        #expect(quote.quantity == record.totalWorkload)
        #expect(ReportBuilder.quoteGrandTotal(quote) == NumericInputSupport.money(expectedAmount))
        #expect(ReportBuilder.quoteGrandTotal(quote) == ReportBuilder.laborLineTotal(record))
    }

    @Test func fractionalWorkloadQuotationAppliesSpecifiedRateTaxAndDiscount() throws {
        let record = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-10-13"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("0.125"),
            workloadUnit: .hour,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: NumericInputSupport.money(" 400.00 "),
            taxRate: NumericInputSupport.quantity("13"),
            discountRate: NumericInputSupport.quantity("5")
        ))

        #expect(quote.quantity == record.totalWorkload)
        #expect(quote.unit == record.workloadUnit.quoteUnit)
        #expect(quote.unitPrice == NumericInputSupport.money("400"))
        #expect(ReportBuilder.quoteLineTotal(quote) == NumericInputSupport.money("50"))
        #expect(ReportBuilder.quoteTaxValue(quote) == NumericInputSupport.money("6.50"))
        #expect(ReportBuilder.quoteDiscountValue(quote) == NumericInputSupport.money("2.50"))
        #expect(ReportBuilder.quoteGrandTotal(quote) == NumericInputSupport.money("54"))
        #expect(ReportBuilder.laborLineTotal(record) == MoneyValue(Decimal(string: "37.50")!))
    }

    @Test func bulkUnitConfirmationChangesOnlySelectedLegacyRecordsWithoutConvertingValues() {
        let legacyHour = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-01"),
            workers: NumericInputSupport.quantity("2"),
            hours: NumericInputSupport.quantity("8"),
            workloadUnit: .legacyUnspecified,
            unitRate: NumericInputSupport.money("50"),
            note: ""
        )
        let legacyUnselected = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-02"),
            workers: NumericInputSupport.quantity("3"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .legacyUnspecified,
            unitRate: NumericInputSupport.money("300"),
            note: ""
        )
        let known = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-03"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("200"),
            note: ""
        )

        let updated = LaborUnitConfirmation.applying(
            .hour,
            to: [legacyHour, legacyUnselected, known],
            recordIDs: Set([legacyHour.id, known.id])
        )

        #expect(updated[0].workloadUnit == .hour)
        #expect(updated[0].workers.wireText == "2")
        #expect(updated[0].hours.wireText == "8")
        #expect(updated[0].unitRate.wireText == "50")
        #expect(updated[1].workloadUnit == .legacyUnspecified)
        #expect(updated[2].workloadUnit == .workday)
    }

    @Test func bulkUnitEligibilityKeepsTheFrozenSelectionAndDropsRowsAlreadyConfirmed() {
        var originallySelected = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-01"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("8"),
            workloadUnit: .legacyUnspecified,
            note: ""
        )
        let selectedStillLegacy = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-02"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .legacyUnspecified,
            note: ""
        )
        let addedAfterPreview = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-03"),
            workers: NumericInputSupport.quantity("1"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .legacyUnspecified,
            note: ""
        )
        let frozenIDs = Set([originallySelected.id, selectedStillLegacy.id])
        originallySelected.workloadUnit = .hour

        let eligibleIDs = LaborUnitConfirmation.eligibleRecordIDs(
            in: [originallySelected, selectedStillLegacy, addedAfterPreview],
            limitedTo: frozenIDs
        )

        #expect(eligibleIDs == Set([selectedStillLegacy.id]))
    }

    @Test func projectReportLaborSummaryKeepsUnitsSeparate() {
        let records = [
            LaborRecord(date: BusinessDateValue(legacyText: "2026-09-09"), workers: NumericInputSupport.quantity("2"), hours: NumericInputSupport.quantity("8"), workloadUnit: .hour, note: ""),
            LaborRecord(date: BusinessDateValue(legacyText: "2026-09-09"), workers: NumericInputSupport.quantity("3"), hours: NumericInputSupport.quantity("1"), workloadUnit: .workday, note: ""),
            LaborRecord(date: BusinessDateValue(legacyText: "2026-09-09"), workers: NumericInputSupport.quantity("2"), hours: NumericInputSupport.quantity("4"), workloadUnit: .legacyUnspecified, note: "")
        ]

        let summary = ReportBuilder.laborWorkloadSummary(records)

        #expect(summary.hours == QuantityValue(16))
        #expect(summary.workdays == QuantityValue(3))
        #expect(summary.unconfirmedValue == QuantityValue(8))
        #expect(summary.unconfirmedCount == 1)
        #expect(summary.displayText.contains(String(localized: "总工时")))
        #expect(summary.displayText.contains(String(localized: "总工天")))
        #expect(summary.displayText.contains(String(localized: "待确认")))
    }

    @Test func laborHTMLExportEscapesProjectWorkTypeAndTeam() throws {
        let project = Project(name: "A&B <总包>", location: "")
        let record = LaborRecord(
            date: BusinessDateValue(legacyText: "2026-09-09"),
            workers: NumericInputSupport.quantity("2"),
            hours: NumericInputSupport.quantity("1"),
            workloadUnit: .workday,
            unitRate: NumericInputSupport.money("300"),
            workType: "<script>工种</script>",
            teamName: "一班 & 二班",
            note: "",
            projectId: project.id
        )

        let data = LaborRecordExportBuilder.makeHTML(
            records: [record],
            projects: [project],
            exportTime: "2026-09-09 10:00"
        )
        let html = try #require(String(data: data, encoding: .utf8))

        #expect(html.contains("A&amp;B &lt;总包&gt;"))
        #expect(html.contains("&lt;script&gt;工种&lt;/script&gt;"))
        #expect(html.contains("一班 &amp; 二班"))
        #expect(!html.contains("<script>工种</script>"))
    }
}
