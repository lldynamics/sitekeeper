import Testing
@testable import sitekeeper

@MainActor
struct UnitConverterTests {
    // 长度：1 米 = 3.28084 英尺
    @Test func meterToFeet() {
        let result = EngineeringCalculations.unitConvert(value: 1, fromFactor: 1, toFactor: 0.3048)
        #expect(abs(result - 3.28084) < 0.001)
    }

    // 长度：1 英尺 = 0.3048 米
    @Test func feetToMeter() {
        let result = EngineeringCalculations.unitConvert(value: 1, fromFactor: 0.3048, toFactor: 1)
        #expect(abs(result - 0.3048) < 0.001)
    }

    // 面积：1 亩 ≈ 666.667 平方米
    @Test func muToSquareMeter() {
        let result = EngineeringCalculations.unitConvert(value: 1, fromFactor: 666.667, toFactor: 1)
        #expect(abs(result - 666.667) < 0.01)
    }

    // 重量：1 吨 = 1000 千克
    @Test func tonToKg() {
        let result = EngineeringCalculations.unitConvert(value: 1, fromFactor: 1000, toFactor: 1)
        #expect(abs(result - 1000) < 0.001)
    }

    // 零值边界
    @Test func zeroValue() {
        let result = EngineeringCalculations.unitConvert(value: 0, fromFactor: 1, toFactor: 0.3048)
        #expect(result == 0)
    }
}
