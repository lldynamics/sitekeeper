import Foundation
import Testing
@testable import sitekeeper

struct NumericInputSupportTests {
    @Test func sanitizeRemovesNonNumericCharacters() {
        let value = NumericInputSupport.sanitize(" ￥1，234.50元 ", kind: .amount)
        #expect(value == "1,234.50")
    }

    @Test func requiredPositiveValidationRejectsZero() {
        let zero = NumericInputSupport.validate("0", kind: .amount, requirement: .requiredPositive)
        #expect(!zero.isValid)
        #expect(zero.error == .notPositive)
    }

    @Test func firstNumberStringExtractsFromTemplateLine() {
        let price = NumericInputSupport.firstNumberString(in: "人工费 ¥ 120.50 /工时", kind: .laborRate)
        #expect(price == "120.5")
    }

    @Test func splitNumberAndUnitParsesQuantityAndUnit() {
        let parsed = NumericInputSupport.splitNumberAndUnit(in: "12.5米", kind: .quantity)
        #expect(parsed.number == "12.5")
        #expect(parsed.unit == "米")
    }

    @Test func parseMaterialTemplateLineKeepsSignGroupingAndChineseUnit() {
        let parsed = NumericInputSupport.parseMaterialTemplateLine("钢筋 × -1,200.50 吨")
        #expect(parsed.name == "钢筋")
        #expect(parsed.quantity == "-1200.5")
        #expect(parsed.unit == "吨")
    }

    @Test func parseQuotationTemplateLineHandlesCurrencyAndPerUnit() {
        let parsed = NumericInputSupport.parseQuotationTemplateLine("墙面找平 单价 ￥1,280.75 元/㎡")
        #expect(parsed.name == "墙面找平")
        #expect(parsed.price == "1280.75")
        #expect(parsed.unit == "㎡")
    }

    @Test func normalizedStorageTextConvertsGroupedNumber() {
        let value = NumericInputSupport.normalizedStorageText("1,234.5", kind: .amount)
        #expect(value == "1234.5")
    }
}
