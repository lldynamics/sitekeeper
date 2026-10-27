import Foundation
import Testing
@testable import sitekeeper

struct UnitDisplayTests {
    @Test func quantityWithUnitParsesGroupedInteger() {
        let text = UnitDisplay.quantityWithUnit(NumericInputSupport.quantity("1,234"), unit: "m", useMetric: false)
        #expect(text == "4048.56 ft")
    }

    @Test func quantityWithUnitParsesCommaDecimal() {
        let text = UnitDisplay.quantityWithUnit(NumericInputSupport.quantity("1,5"), unit: "m", useMetric: false)
        #expect(text == "4.92 ft")
    }

    @Test func quantityWithUnitKeepsOriginalForInvalidInput() {
        let text = UnitDisplay.quantityWithUnit(NumericInputSupport.quantity("abc"), unit: "m", useMetric: false)
        #expect(text == "abc ft")
    }

    @Test func quantityWithUnitBypassesConversionInMetricMode() {
        let text = UnitDisplay.quantityWithUnit(NumericInputSupport.quantity("1,234"), unit: "m", useMetric: true)
        #expect(text == "1234 m")
    }

    @Test func displayedUnitPriceUsesTheSameConversionFactorAsQuantity() {
        #expect(UnitDisplay.displayedUnitPrice(10, unit: "m", useMetric: true) == 10)
        #expect((UnitDisplay.displayedUnitPrice(10, unit: "m", useMetric: false).decimal - Decimal(string: "3.048")!).magnitude < Decimal(string: "0.001")!)
    }
}
