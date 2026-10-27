import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct NumericStorageConsistencyTests {
    @Test(arguments: ["1.234,56", "1,234.56", "1234.56", "1，234．56", " 1 234.56 "])
    func materialValidationStorageAndCalculationAgree(_ input: String) throws {
        let validation = InputValidator.validate(input, kind: .quantity, requirement: .requiredNonNegative)
        #expect(validation.isValid)
        #expect(validation.decimalValue == Decimal(string: "1234.56"))
        let item = MaterialItem(name: "水泥", quantity: NumericInputSupport.quantity(input), unit: "吨", unitPrice: NumericInputSupport.money("10"))
        let restored = try JSONDecoder().decode(MaterialItem.self, from: JSONEncoder().encode(item))

        #expect(restored.quantity.wireText == "1234.56")
        #expect(ReportBuilder.materialLineTotal(restored).decimal == Decimal(string: "12345.6"))
    }

    @Test func legacyEuropeanTextDecodesWithoutChangingBusinessAmounts() throws {
        let material = try JSONDecoder().decode(MaterialItem.self, from: Data(
            #"{"name":"钢筋","quantity":"1.234,56","unit":"吨","unitPrice":"10"}"#.utf8
        ))
        let quote = QuoteItem(name: material.name, unitPrice: material.unitPrice, quantity: material.quantity,
                              unit: material.unit, notes: "", taxRate: NumericInputSupport.quantity("10"), discountRate: NumericInputSupport.quantity("5"))
        let restoredQuote = try JSONDecoder().decode(QuoteItem.self, from: JSONEncoder().encode(quote))

        #expect(ReportBuilder.materialLineTotal(material).decimal == Decimal(string: "12345.6"))
        #expect(ReportBuilder.quoteGrandTotal(restoredQuote).decimal == Decimal(string: "12962.88"))
    }

    @Test func modelAssignmentAndWarehouseRoundTripPreserveFractionalQuantity() throws {
        var movement = ProjectWarehouseMovement(projectId: UUID(), materialName: "水泥", unit: "吨", quantity: NumericInputSupport.quantity("1"))
        movement.quantity = NumericInputSupport.quantity("1.234,5678")
        let restored = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: JSONEncoder().encode(movement))
        let lines = WarehouseStockCalculator.stockLines(for: restored.projectId, movements: [restored])

        #expect(restored.quantity.wireText == "1234.5678")
        #expect(lines.first?.quantity.optionalDecimal == Decimal(string: "1234.5678"))
    }

    @Test func invalidAssignmentsRemainVisibleInsteadOfSilentlySavingThePreviousValue() {
        var item = MaterialItem(name: "水泥", quantity: NumericInputSupport.quantity("2"), unit: "吨")
        for invalid in ["-1", "abc", "1abc2", "1.2.3"] {
            item.quantity = NumericInputSupport.quantity(invalid)
            #expect(item.quantity.wireText == invalid)
            #expect(item.quantity.optionalDecimal == nil)
        }
        item.quantity = NumericInputSupport.quantity(" ")
        #expect(item.quantity.isEmpty)
    }

    @Test func numericJSONDecodingKeepsDecimalPrecision() throws {
        let value = try JSONDecoder().decode(MoneyValue.self, from: Data("1234.567890123456789".utf8))
        #expect(value.wireText == "1234.567890123456789")
        let restored = try JSONDecoder().decode(MoneyValue.self, from: JSONEncoder().encode(value))
        #expect(restored.wireText == value.wireText)
    }
}
