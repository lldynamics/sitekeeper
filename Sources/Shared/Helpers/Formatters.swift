import Foundation

/// 全局格式化工具，消除各计算器视图中的 fmt() / now() 重复
enum Formatters {
    static let dateTime: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()

    static let date: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    /// 当前时间字符串
    static func now() -> String { dateTime.string(from: Date()) }

    /// 数字格式化（小数位可配）
    static func number(_ v: Double, minFraction: Int = 0, maxFraction: Int = 3) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = minFraction
        f.maximumFractionDigits = maxFraction
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// 两位小数金额
    static func money(_ v: Double) -> String { String(format: "%.2f", v) }
}
