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
        let item = MaterialItem(name: "水泥", quantity: input, unit: "吨", unitPrice: "10")
        let restored = try JSONDecoder().decode(MaterialItem.self, from: JSONEncoder().encode(item))

        #expect(restored.quantity == "1234.56")
        #expect(ReportBuilder.materialLineTotal(restored) == 12345.6)
    }

    @Test func legacyEuropeanTextDecodesWithoutChangingBusinessAmounts() throws {
        let material = try JSONDecoder().decode(MaterialItem.self, from: Data(
            #"{"name":"钢筋","quantity":"1.234,56","unit":"吨","unitPrice":"10"}"#.utf8
        ))
        let quote = QuoteItem(name: material.name, unitPrice: material.unitPrice, quantity: material.quantity,
                              unit: material.unit, notes: "", taxRate: "10", discountRate: "5")
        let restoredQuote = try JSONDecoder().decode(QuoteItem.self, from: JSONEncoder().encode(quote))

        #expect(ReportBuilder.materialLineTotal(material) == 12345.6)
        #expect(ReportBuilder.quoteGrandTotalValue(restoredQuote).decimal == Decimal(string: "12962.88"))
    }

    @Test func modelAssignmentAndWarehouseRoundTripPreserveFractionalQuantity() throws {
        var movement = ProjectWarehouseMovement(projectId: UUID(), materialName: "水泥", unit: "吨", quantity: "1")
        movement.quantity = "1.234,5678"
        let restored = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: JSONEncoder().encode(movement))
        let lines = WarehouseStockCalculator.stockLines(for: restored.projectId, movements: [restored])

        #expect(restored.quantity == "1234.5678")
        #expect(lines.first?.quantity == 1234.5678)
    }

    @Test func invalidAssignmentsKeepExistingValueAndEmptyClearsIt() {
        var item = MaterialItem(name: "水泥", quantity: "2", unit: "吨")
        for invalid in ["-1", "abc", "1abc2", "1.2.3"] {
            item.quantity = invalid
            #expect(item.quantity == "2")
        }
        item.quantity = " "
        #expect(item.quantity.isEmpty)
    }

    @Test func numericJSONDecodingKeepsDecimalPrecision() throws {
        let value = try JSONDecoder().decode(NonNegativeNumberText.self, from: Data("1234.567890123456789".utf8))
        #expect(value.wrappedValue == "1234.567890123456789")
        let restored = try JSONDecoder().decode(NonNegativeNumberText.self, from: JSONEncoder().encode(value))
        #expect(restored.wrappedValue == value.wrappedValue)
    }
}
