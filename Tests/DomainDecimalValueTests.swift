import Foundation
import Testing
@testable import sitekeeper

struct DomainDecimalValueTests {
    @Test func decimalMoneyFormattingPreservesCentsAndRoundsOnlyForDisplay() throws {
        let amount = try #require(Decimal(string: "9007199254740993.015"))
        #expect(Formatters.money(decimal: amount) == "9007199254740993.02")
        #expect(Formatters.money(decimal: -amount) == "-9007199254740993.02")
        #expect(Formatters.money(decimal: Decimal(string: "0.1")! + Decimal(string: "0.2")!) == "0.30")
        #expect(amount == Decimal(string: "9007199254740993.015"))
    }
    @Test func typedDomainUpdatesRoundTripWithoutBinaryFloatingPoint() throws {
        var project = Project(name: "Decimal", location: "")
        project.contractAmount = MoneyValue(try #require(Decimal(string: "9007199254740993.01")))
        project.paidAmount = MoneyValue(try #require(Decimal(string: "9007199254740993.00")))
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(restored.contractAmount.wireText == "9007199254740993.01")
        #expect(ProjectFinancialMetrics.unpaidAmount(project: restored, records: []).decimal == Decimal(string: "0.01"))
        #expect(ProjectFinancialMetrics.unpaidAmount(project: restored, records: []).optionalDecimal == Decimal(string: "0.01"))
        let records = [
            ProjectFinancialRecord(projectId: project.id, direction: .income, amount: NumericInputSupport.money("9007199254740993.01")),
            ProjectFinancialRecord(projectId: project.id, direction: .expense, amount: NumericInputSupport.money("9007199254740993.00"))
        ]
        let summary = ProjectFinancialMetrics.summary(records)
        #expect(summary.balance.decimal == Decimal(string: "0.01"))
        #expect(summary.balance.optionalDecimal == Decimal(string: "0.01"))
    }

    @Test func numericModelJSONAcceptsExactDecimalsAndPreservesMissingVersusZero() throws {
        let item = try JSONDecoder().decode(MaterialItem.self, from: Data(
            #"{"name":"材料","quantity":0,"unitPrice":9007199254740993.01}"#.utf8
        ))
        #expect(item.quantity.optionalDecimal == Decimal.zero)
        #expect(item.unitPrice.decimal == Decimal(string: "9007199254740993.01"))
        let empty = MaterialItem(name: "未填", quantity: NumericInputSupport.quantity(""), unit: "")
        #expect(empty.quantity.optionalDecimal == nil)
        let tooPrecise = String(repeating: "1", count: 39)
        let invalid = MaterialItem(name: "超精度", quantity: NumericInputSupport.quantity(tooPrecise), unit: "")
        #expect(invalid.quantity.wireText == tooPrecise)
        #expect(invalid.quantity.optionalDecimal == nil)
    }
}
