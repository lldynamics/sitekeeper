import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct QuoteCalculationsTests {
    // 基础小计
    @Test func lineTotal() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("100"), quantity: NumericInputSupport.quantity("5"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: nil)
        let result = ReportBuilder.quoteLineTotal(item)
        #expect(result == 500)
    }

    // 税额计算
    @Test func taxCalculation() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("100"), quantity: NumericInputSupport.quantity("1"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("13"), discountRate: NumericInputSupport.quantity("0"), projectId: nil)
        let subtotal = ReportBuilder.quoteLineTotal(item)
        let tax = ReportBuilder.quoteTaxValue(item)
        #expect(subtotal.decimal == 100)
        #expect(tax.decimal == 13)
    }

    // 折扣计算
    @Test func discountCalculation() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("200"), quantity: NumericInputSupport.quantity("2"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("10"), projectId: nil)
        let subtotal = ReportBuilder.quoteLineTotal(item)
        let discount = ReportBuilder.quoteDiscountValue(item)
        #expect(subtotal.decimal == 400)
        #expect(discount.decimal == 40)
    }

    @Test func discountIsClampedToPreventNegativeQuoteTotal() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("100"), quantity: NumericInputSupport.quantity("1"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("150"), projectId: nil)

        #expect(ReportBuilder.quoteDiscountValue(item).decimal == 100)
        #expect(ReportBuilder.quoteGrandTotal(item) == 0)
    }

    // 含税含折扣合计
    @Test func grandTotal() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("1000"), quantity: NumericInputSupport.quantity("1"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("13"), discountRate: NumericInputSupport.quantity("5"), projectId: nil)
        let grand = ReportBuilder.quoteGrandTotal(item)
        #expect(grand == 1080)
    }

    @Test func quotePdfProducesData() {
        let item = QuoteItem(name: "测试", unitPrice: NumericInputSupport.money("100"), quantity: NumericInputSupport.quantity("2"), unit: "项", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: nil)
        let data = ReportBuilder.makeQuotationPDF(title: "报价单", items: [item], projects: [])
        #expect(data.count > 100)
    }

    // 空值安全
    @Test func emptyValues() {
        let item = QuoteItem(name: "", unitPrice: NumericInputSupport.money(""), quantity: NumericInputSupport.quantity(""), unit: "", notes: "", taxRate: NumericInputSupport.quantity("abc"), discountRate: NumericInputSupport.quantity(""), projectId: nil)
        let price = item.unitPrice
        let qty = item.quantity
        #expect(price.decimal == 0)
        #expect(qty.decimal == 0)
    }

    @Test func decimalParserPreservesPrecisionToken() {
        let value = DataValueParser.decimalValue(from: "￥1,234.5678")
        #expect(NSDecimalNumber(decimal: value).stringValue == "1234.5678")
    }

    @Test func decimalParserKeepsGroupingAndDecimalSeparatorsDistinct() {
        let cases = [
            ("1,234", "1234"),
            ("12,345.67", "12345.67"),
            ("1,234,567.89", "1234567.89"),
            ("1,5", "1.5"),
            ("1.234,56", "1234.56")
        ]

        for (input, expected) in cases {
            let value = DataValueParser.decimalValue(from: input)
            #expect(NSDecimalNumber(decimal: value).stringValue == expected)
        }
    }

    @Test func nonNegativeNumberValidatorAcceptsGroupedNumbersOnlyWhenFullyNumeric() {
        #expect(InputValidator.nonNegativeNumber("1,234"))
        #expect(InputValidator.nonNegativeNumber("12,345.67"))
        #expect(InputValidator.nonNegativeNumber("1,5"))
        #expect(!InputValidator.nonNegativeNumber("-0.01"))
        #expect(!InputValidator.nonNegativeNumber("￥1,234"))
        #expect(!InputValidator.nonNegativeNumber("abc"))
    }
}
