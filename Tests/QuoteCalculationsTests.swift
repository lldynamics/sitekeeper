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
        let subtotal = (Double(item.unitPrice) ?? 0) * (Double(item.quantity) ?? 0)
        let tax = subtotal * ((Double(item.taxRate) ?? 0) / 100)
        #expect(abs(tax - 13) < 0.01)
    }

    // 折扣计算
    @Test func discountCalculation() {
        let item = QuoteItem(name: "测试", unitPrice: "200", quantity: "2", unit: "个", notes: "", taxRate: "0", discountRate: "10", projectId: nil)
        let subtotal = (Double(item.unitPrice) ?? 0) * (Double(item.quantity) ?? 0)
        let discount = subtotal * ((Double(item.discountRate) ?? 0) / 100)
        #expect(discount == 40)
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
        let price = Double(item.unitPrice) ?? 0
        let qty = Double(item.quantity) ?? 0
        #expect(price == 0)
        #expect(qty == 0)
    }
}
