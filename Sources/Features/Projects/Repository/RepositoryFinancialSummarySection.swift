import SwiftUI

struct RepositoryFinancialSummarySection: View {
    let summary: RepositoryFinancialSummary

    var body: some View {
        Section(AppLocalization.string("筛选范围金额汇总")) {
            Text(String(format: AppLocalization.string("共 %lld 条，正式记录 %lld 条"), Int64(summary.count), Int64(summary.activeCount)))
                .accessibilityIdentifier("repository-finance-summary-count")
            if let income = summary.income, let expense = summary.expense, let balance = summary.balance {
                amount(AppLocalization.string("正式收入"), value: income, id: "income")
                amount(AppLocalization.string("正式支出"), value: expense, id: "expense")
                amount(AppLocalization.string("收支差额"), value: balance, id: "balance")
            } else if summary.hasPrecisionError {
                Text(AppLocalization.string("金额超出精确计算范围，暂不显示合计。记录已保留。"))
                    .foregroundStyle(.red)
            } else {
                Text(String(format: AppLocalization.string("%lld 条正式记录金额缺失或无效，修正后才能显示合计。"), Int64(summary.invalidAmountCount)))
                    .foregroundStyle(.red)
            }
            Text(AppLocalization.string("汇总覆盖当前筛选的全部记录，不限于本页。草稿和归档不计入金额；收支差额不代表现金余额。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func amount(_ title: String, value: Decimal, id: String) -> some View {
        LabeledContent(title) {
            Text(RepositoryMoney.display(value)).monospacedDigit()
                .accessibilityIdentifier("repository-finance-summary-\(id)")
        }
    }
}
