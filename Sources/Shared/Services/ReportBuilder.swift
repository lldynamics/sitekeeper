import Foundation
import UIKit

struct LaborWorkloadSummary: Equatable {
    let hours: QuantityValue
    let workdays: QuantityValue
    let unconfirmedValue: QuantityValue
    let unconfirmedCount: Int

    var displayText: String {
        var parts: [String] = []
        if !hours.isZero {
            parts.append("\(String(localized: "总工时")) \(formatted(hours))")
        }
        if !workdays.isZero {
            parts.append("\(String(localized: "总工天")) \(formatted(workdays))")
        }
        if unconfirmedCount > 0 {
            parts.append(String(
                format: String(localized: "待确认 %lld 条（原值合计 %@）"),
                Int64(unconfirmedCount),
                formatted(unconfirmedValue)
            ))
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private func formatted(_ value: QuantityValue) -> String {
        value.doubleValue.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum ReportBuilder {

    // MARK: - 本地化助手

    /// 本地化 CSV/PDF/HTML 输出字符串，跟随 App 内语言设置
    static func loc(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    static func locFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: loc(key), arguments: arguments)
    }

    /// 本地化字符串数组
    static func loc(_ keys: [String]) -> [String] {
        keys.map { loc($0) }
    }

    /// CSV 段标题
    static func csvSection(_ key: String) -> String {
        "[\(loc(key))]"
    }

    /// 机器可读导出段名保持稳定英文 key，避免语言切换影响后续解析。
    static func csvMachineSection(_ key: String) -> String {
        "[\(key)]"
    }

    /// 常用状态值
    static var locYes: String { loc("是") }
    static var locNo: String { loc("否") }
    static var locDone: String { loc("完成") }
    static var locOverdue: String { loc("延期") }
    static var locPending: String { loc("待办") }
    static var locNotFilled: String { loc("未填写") }

    static func quoteLineTotalValue(_ item: QuoteItem) -> MoneyValue {
        let quantity = item.quantityValue
        let unitPrice = item.unitPriceValue
        return quantity * unitPrice
    }

    static func quoteTaxValue(_ item: QuoteItem) -> MoneyValue {
        let line = quoteLineTotalValue(item)
        let taxRate = item.taxRateValue.ratioFromPercent
        return line * taxRate
    }

    static func quoteDiscountValue(_ item: QuoteItem) -> MoneyValue {
        let line = quoteLineTotalValue(item)
        let discountRate = min(max(item.discountRateValue.ratioFromPercent, .zero), 1)
        return line * discountRate
    }

    static func quoteLineTotal(_ item: QuoteItem) -> Double {
        quoteLineTotalValue(item).doubleValue
    }

    static func materialLineTotal(_ item: MaterialItem) -> Double {
        let quantity = item.quantityValue
        let unitPrice = item.unitPriceValue
        return (quantity * unitPrice).doubleValue
    }

    static func laborHours(_ record: LaborRecord) -> Double {
        record.totalWorkloadValue.doubleValue
    }

    static func laborWorkloadSummary(_ records: [LaborRecord]) -> LaborWorkloadSummary {
        var hours = QuantityValue.zero
        var workdays = QuantityValue.zero
        var unconfirmedValue = QuantityValue.zero
        var unconfirmedCount = 0
        for record in records {
            switch record.workloadUnit {
            case .legacyUnspecified:
                unconfirmedValue = unconfirmedValue + record.totalWorkloadValue
                unconfirmedCount += 1
            case .hour:
                hours = hours + record.totalWorkloadValue
            case .workday:
                workdays = workdays + record.totalWorkloadValue
            }
        }
        return LaborWorkloadSummary(
            hours: hours,
            workdays: workdays,
            unconfirmedValue: unconfirmedValue,
            unconfirmedCount: unconfirmedCount
        )
    }

    static func laborLineTotal(_ record: LaborRecord) -> Double {
        let hoursValue = MoneyValue(record.totalWorkloadValue.decimal)
        let rate = record.unitRateValue.decimal
        return (hoursValue * rate).doubleValue
    }

    static func number(_ text: String) -> Double {
        DataValueParser.double(from: text)
    }

    static func quoteGrandTotal(_ item: QuoteItem) -> Double {
        let line = quoteLineTotalValue(item)
        let tax = quoteTaxValue(item)
        let discount = quoteDiscountValue(item)
        return (line + tax - discount).doubleValue
    }

    static func amountRaw(_ value: Double) -> String {
        Formatters.money(value)
    }

    static func amountDisplay(
        _ value: Double,
        currencyDisplayMode: ExportCurrencyDisplayMode = .defaultMode
    ) -> String {
        currencyDisplayMode.format(value)
    }

    static func money(_ value: Double) -> String {
        amountDisplay(value)
    }

    static func money(
        _ value: Double,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        amountDisplay(value, currencyDisplayMode: currencyDisplayMode)
    }

    static func amountDisplay(
        rawText: String,
        currencyDisplayMode: ExportCurrencyDisplayMode
    ) -> String {
        guard let decimal = DataValueParser.decimalValueIfPresent(from: rawText) else {
            return rawText
        }
        return amountDisplay(
            NSDecimalNumber(decimal: decimal).doubleValue,
            currencyDisplayMode: currencyDisplayMode
        )
    }

    static func csv(_ values: [String]) -> String {
        values.map { value in
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }.joined(separator: ",")
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
