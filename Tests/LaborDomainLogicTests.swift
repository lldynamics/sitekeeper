import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct LaborDomainLogicTests {
    @Test func laborCostDistinguishesMissingWorkersFromExplicitZero() {
        let historicalMissingWorkers = LaborRecord(
            date: "2026-09-09",
            workers: "",
            hours: "1",
            unitRate: "300",
            note: ""
        )
        let explicitZeroWorkers = LaborRecord(
            date: "2026-09-09",
            workers: "0",
            hours: "1",
            workloadUnit: .workday,
            unitRate: "300",
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
        #expect(legacy.hours == "8")
        #expect(ReportBuilder.laborLineTotal(legacy) == 800)
        #expect(LaborQuoteGenerator.makeQuoteItem(from: legacy, defaultRate: "", taxRate: "0", discountRate: "0") == nil)

        let restored = try JSONDecoder().decode(LaborRecord.self, from: JSONEncoder().encode(legacy))
        #expect(restored.workloadUnit == .legacyUnspecified)
        #expect(restored.hours == legacy.hours)
    }

    @Test func confirmedWorkdayLaborCreatesWorkdayQuotation() throws {
        let record = LaborRecord(
            date: "2026-09-09",
            workers: "2",
            hours: "1.5",
            workloadUnit: .workday,
            unitRate: "300",
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: "",
            taxRate: "0",
            discountRate: "0"
        ))

        #expect(quote.quantity == "3")
        #expect(quote.unit == record.workloadUnit.quoteUnit)
        #expect(quote.unitPrice == "300")
    }

    @Test func fractionalWorkdayQuotationPreservesLaborAmountWhenUsingRecordedRate() throws {
        let record = LaborRecord(
            date: "2026-10-13",
            workers: "1",
            hours: "0.125",
            workloadUnit: .workday,
            unitRate: "300",
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: "   ",
            taxRate: "0",
            discountRate: "0"
        ))

        #expect(quote.quantityValue == record.totalWorkloadValue)
        #expect(quote.unitPriceValue == MoneyValue(text: "300"))
        #expect(ReportBuilder.quoteGrandTotalValue(quote) == MoneyValue(text: "37.50"))
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
            date: "2026-10-13",
            workers: workers,
            hours: days,
            workloadUnit: .workday,
            unitRate: "300",
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: "",
            taxRate: "0",
            discountRate: "0"
        ))

        #expect(quote.quantityValue == QuantityValue(text: expectedWorkload))
        #expect(quote.quantityValue == record.totalWorkloadValue)
        #expect(ReportBuilder.quoteGrandTotalValue(quote) == MoneyValue(text: expectedAmount))
        #expect(ReportBuilder.quoteGrandTotal(quote) == ReportBuilder.laborLineTotal(record))
    }

    @Test func fractionalWorkloadQuotationAppliesSpecifiedRateTaxAndDiscount() throws {
        let record = LaborRecord(
            date: "2026-10-13",
            workers: "1",
            hours: "0.125",
            workloadUnit: .hour,
            unitRate: "300",
            note: ""
        )
        let quote = try #require(LaborQuoteGenerator.makeQuoteItem(
            from: record,
            defaultRate: " 400.00 ",
            taxRate: "13",
            discountRate: "5"
        ))

        #expect(quote.quantityValue == record.totalWorkloadValue)
        #expect(quote.unit == record.workloadUnit.quoteUnit)
        #expect(quote.unitPriceValue == MoneyValue(text: "400"))
        #expect(ReportBuilder.quoteLineTotalValue(quote) == MoneyValue(text: "50"))
        #expect(ReportBuilder.quoteTaxValue(quote) == MoneyValue(text: "6.50"))
        #expect(ReportBuilder.quoteDiscountValue(quote) == MoneyValue(text: "2.50"))
        #expect(ReportBuilder.quoteGrandTotalValue(quote) == MoneyValue(text: "54"))
        #expect(ReportBuilder.laborLineTotal(record) == 37.50)
    }

    @Test func bulkUnitConfirmationChangesOnlySelectedLegacyRecordsWithoutConvertingValues() {
        let legacyHour = LaborRecord(
            date: "2026-09-01",
            workers: "2",
            hours: "8",
            workloadUnit: .legacyUnspecified,
            unitRate: "50",
            note: ""
        )
        let legacyUnselected = LaborRecord(
            date: "2026-09-02",
            workers: "3",
            hours: "1",
            workloadUnit: .legacyUnspecified,
            unitRate: "300",
            note: ""
        )
        let known = LaborRecord(
            date: "2026-09-03",
            workers: "1",
            hours: "1",
            workloadUnit: .workday,
            unitRate: "200",
            note: ""
        )

        let updated = LaborUnitConfirmation.applying(
            .hour,
            to: [legacyHour, legacyUnselected, known],
            recordIDs: Set([legacyHour.id, known.id])
        )

        #expect(updated[0].workloadUnit == .hour)
        #expect(updated[0].workers == "2")
        #expect(updated[0].hours == "8")
        #expect(updated[0].unitRate == "50")
        #expect(updated[1].workloadUnit == .legacyUnspecified)
        #expect(updated[2].workloadUnit == .workday)
    }

    @Test func bulkUnitEligibilityKeepsTheFrozenSelectionAndDropsRowsAlreadyConfirmed() {
        var originallySelected = LaborRecord(
            date: "2026-09-01",
            workers: "1",
            hours: "8",
            workloadUnit: .legacyUnspecified,
            note: ""
        )
        let selectedStillLegacy = LaborRecord(
            date: "2026-09-02",
            workers: "1",
            hours: "1",
            workloadUnit: .legacyUnspecified,
            note: ""
        )
        let addedAfterPreview = LaborRecord(
            date: "2026-09-03",
            workers: "1",
            hours: "1",
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
            LaborRecord(date: "2026-09-09", workers: "2", hours: "8", workloadUnit: .hour, note: ""),
            LaborRecord(date: "2026-09-09", workers: "3", hours: "1", workloadUnit: .workday, note: ""),
            LaborRecord(date: "2026-09-09", workers: "2", hours: "4", workloadUnit: .legacyUnspecified, note: "")
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
            date: "2026-09-09",
            workers: "2",
            hours: "1",
            workloadUnit: .workday,
            unitRate: "300",
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
