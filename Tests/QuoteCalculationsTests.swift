import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct QuoteCalculationsTests {
    // 基础小计
    @Test func lineTotal() {
        let item = QuoteItem(name: "测试", unitPrice: "100", quantity: "5", unit: "个", notes: "", taxRate: "0", discountRate: "0", projectId: nil)
        let result = ReportBuilder.quoteLineTotal(item)
        #expect(result == 500)
    }

    // 税额计算
    @Test func taxCalculation() {
        let item = QuoteItem(name: "测试", unitPrice: "100", quantity: "1", unit: "个", notes: "", taxRate: "13", discountRate: "0", projectId: nil)
        let subtotal = ReportBuilder.quoteLineTotalValue(item)
        let tax = ReportBuilder.quoteTaxValue(item)
        #expect(abs(subtotal.doubleValue - 100) < 0.01)
        #expect(abs(tax.doubleValue - 13) < 0.01)
    }

    // 折扣计算
    @Test func discountCalculation() {
        let item = QuoteItem(name: "测试", unitPrice: "200", quantity: "2", unit: "个", notes: "", taxRate: "0", discountRate: "10", projectId: nil)
        let subtotal = ReportBuilder.quoteLineTotalValue(item)
        let discount = ReportBuilder.quoteDiscountValue(item)
        #expect(subtotal.doubleValue == 400)
        #expect(discount.doubleValue == 40)
    }

    // 含税含折扣合计
    @Test func grandTotal() {
        let item = QuoteItem(name: "测试", unitPrice: "1000", quantity: "1", unit: "个", notes: "", taxRate: "13", discountRate: "5", projectId: nil)
        let grand = ReportBuilder.quoteGrandTotal(item)
        #expect(grand == 1080)
    }

    @Test func quotePdfProducesData() {
        let item = QuoteItem(name: "测试", unitPrice: "100", quantity: "2", unit: "项", notes: "", taxRate: "0", discountRate: "0", projectId: nil)
        let data = ReportBuilder.makeQuotationPDF(title: "报价单", items: [item], projects: [])
        #expect(data.count > 100)
    }

    // 空值安全
    @Test func emptyValues() {
        let item = QuoteItem(name: "", unitPrice: "", quantity: "", unit: "", notes: "", taxRate: "abc", discountRate: "", projectId: nil)
        let price = MoneyValue(text: item.unitPrice)
        let qty = QuantityValue(text: item.quantity)
        #expect(price.doubleValue == 0)
        #expect(qty.doubleValue == 0)
    }

    @Test func decimalParserPreservesPrecisionToken() {
        let value = DataValueParser.decimalValue(from: "￥1,234.5678")
        #expect(NSDecimalNumber(decimal: value).stringValue == "1234.5678")
    }
}
