import Testing
@testable import sitekeeper

// Preserve CalculationCoreTests' unit-conversion contracts. The original iOS
// tests remain in place; this suite adds host coverage without the App host.
@MainActor
struct UnitConversionContractTests {
    @Test func unitConvertBasic() {
        #expect(EngineeringCalculations.unitConvert(value: 1, fromFactor: 1000, toFactor: 1) == 1000)
        #expect(EngineeringCalculations.unitConvert(value: 1000, fromFactor: 1, toFactor: 1000) == 1)
    }

    @Test func unitConvertZero() {
        #expect(EngineeringCalculations.unitConvert(value: 0, fromFactor: 100, toFactor: 10) == 0)
    }

    @Test func unitConvertInvalidFactor() {
        #expect(EngineeringCalculations.unitConvert(value: 100, fromFactor: 10, toFactor: 0) == 0)
    }

    @Test func unitConvertValidatedRejectsInvalidFactor() {
        let result = EngineeringCalculations.unitConvertValidated(value: 100, fromFactor: 10, toFactor: 0)
        switch result {
        case .failure(.mustBeGreaterThanZero(field: "目标单位系数")):
            break
        default:
            Issue.record("预期目标单位系数应返回 mustBeGreaterThanZero 错误")
        }
    }
}
