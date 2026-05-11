import SwiftUI

struct ProjectBusinessView: View {
    @Environment(DataStore.self) private var store

    var body: some View {
        List {
            Section("总览") {
                metricGrid(summary: overallSummary)
                businessInsightGrid(summary: overallSummary)
            }

            ForEach(store.projects) { project in
                let summary = summary(for: project.id)
                Section(project.name) {
                    metricGrid(summary: summary)
                    businessInsightGrid(summary: summary)
                    if summary.unpricedQuoteCount > 0 || summary.pendingMaterialCount > 0 {
                        HStack {
                            Label("待补价格/数量", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Text("\(summary.unpricedQuoteCount + summary.pendingMaterialCount) 项")
                                .font(.body.weight(.medium))
                        }
                    }
                    NavigationLink("查看项目详情") {
                        ProjectDetailView(projectId: project.id)
                    }
                }
            }
        }
        .navigationTitle("经营看板")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overallSummary: BusinessSummary {
        let paidByRecords = store.projects.reduce(0) { $0 + collectedAmount(for: $1.id) }
        let materialAutoCost = store.materialItems.reduce(0) { $0 + ReportBuilder.materialLineTotal($1) }
        let laborAutoCost = store.laborRecords.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
        let contractAmount = store.projects.reduce(0) { $0 + $1.contractAmountValue.doubleValue }
        let paidAmount = paidByRecords > 0 ? paidByRecords : store.projects.reduce(0) { $0 + $1.paidAmountValue.doubleValue }
        let materialCost = materialAutoCost > 0 ? materialAutoCost : store.projects.reduce(0) { $0 + $1.materialCostValue.doubleValue }
        let laborCostAmount = laborAutoCost > 0 ? laborAutoCost : store.projects.reduce(0) { $0 + $1.laborCostValue.doubleValue }
        let receivableAmount = max(contractAmount - paidAmount, 0)
        return BusinessSummary(
            quoteTotal: store.quoteItems.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) },
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: receivableAmount,
            receivableAgeDays: oldestReceivableAgeDays(),
            recentCollection: latestCollection(projectId: nil),
            materialCost: materialCost,
            laborCostAmount: laborCostAmount,
            materialItems: store.materialItems.count,
            laborHours: store.laborRecords.reduce(0) { $0 + laborHours($1) },
            logDays: Set(store.dailyLogs.map(\.date)).count,
            progress: averageProgress(store.progressTasks),
            circuitPlanCount: store.lightingCircuitPlans.count,
            pendingMaterialCount: store.materialItems.filter { $0.quantityValue.doubleValue == 0 }.count,
            unpricedQuoteCount: store.quoteItems.filter { $0.unitPriceValue.doubleValue == 0 }.count
        )
    }

    private func summary(for projectId: UUID) -> BusinessSummary {
        let quotes = store.quoteItems.filter { $0.projectId == projectId }
        let materials = store.materialItems.filter { $0.projectId == projectId }
        let labor = store.laborRecords.filter { $0.projectId == projectId }
        let logs = store.dailyLogs.filter { $0.projectId == projectId }
        let tasks = store.progressTasks.filter { $0.projectId == projectId }
        let project = store.projects.first { $0.id == projectId }
        let paidByRecords = collectedAmount(for: projectId)
        let materialAutoCost = materials.reduce(0) { $0 + ReportBuilder.materialLineTotal($1) }
        let laborAutoCost = labor.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
        let contractAmount = project?.contractAmountValue.doubleValue ?? 0
        let paidAmount = paidByRecords > 0 ? paidByRecords : (project?.paidAmountValue.doubleValue ?? 0)
        let materialCost = materialAutoCost > 0 ? materialAutoCost : (project?.materialCostValue.doubleValue ?? 0)
        let laborCostAmount = laborAutoCost > 0 ? laborAutoCost : (project?.laborCostValue.doubleValue ?? 0)
        let receivableAmount = max(contractAmount - paidAmount, 0)
        return BusinessSummary(
            quoteTotal: quotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) },
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: receivableAmount,
            receivableAgeDays: project.flatMap { receivableAgeDays(for: $0, receivableAmount: receivableAmount) },
            recentCollection: latestCollection(projectId: projectId),
            materialCost: materialCost,
            laborCostAmount: laborCostAmount,
            materialItems: materials.count,
            laborHours: labor.reduce(0) { $0 + laborHours($1) },
            logDays: Set(logs.map(\.date)).count,
            progress: averageProgress(tasks),
            circuitPlanCount: store.lightingCircuitPlans.filter { $0.projectId == projectId }.count,
            pendingMaterialCount: materials.filter { $0.quantityValue.doubleValue == 0 }.count,
            unpricedQuoteCount: quotes.filter { $0.unitPriceValue.doubleValue == 0 }.count
        )
    }

    private func collectedAmount(for projectId: UUID) -> Double {
        let financial = store.projectFinancialRecords.filter { $0.projectId == projectId }
        let amountFromFinancial = ProjectFinancialMetrics.collectionAmount(financial)
        if amountFromFinancial > 0 {
            return amountFromFinancial
        }
        let payments = store.paymentRecords.filter { $0.projectId == projectId }
        return payments.reduce(0) { $0 + $1.amountValue.doubleValue }
    }

    private func oldestReceivableAgeDays() -> Int? {
        let values = store.projects.compactMap { project -> Int? in
            let paid = collectedAmount(for: project.id)
            let paidAmount = paid > 0 ? paid : project.paidAmountValue.doubleValue
            let receivable = max(project.contractAmountValue.doubleValue - paidAmount, 0)
            return receivableAgeDays(for: project, receivableAmount: receivable)
        }
        return values.max()
    }

    private func receivableAgeDays(for project: Project, receivableAmount: Double) -> Int? {
        guard receivableAmount > 0 else { return nil }
        guard let endDate = Formatters.date.date(from: project.expectedEndDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDate = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: today).day ?? 0
        return max(days, 0)
    }

    private func latestCollection(projectId: UUID?) -> CollectionSnapshot? {
        var snapshots: [CollectionSnapshot] = []
        let records = store.projectFinancialRecords.filter { projectId == nil || $0.projectId == projectId }
        if let latest = ProjectFinancialMetrics.latestCollection(records: records, projectName: projectName(_:)) {
            snapshots.append(latest)
        }
        for payment in store.paymentRecords {
            guard projectId == nil || payment.projectId == projectId else { continue }
            snapshots.append(
                CollectionSnapshot(
                    date: payment.date,
                    amount: payment.amountValue.doubleValue,
                    projectName: projectName(payment.projectId)
                )
            )
        }
        return snapshots.max { sortDate($0.date) < sortDate($1.date) }
    }

    private func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return store.projects.first { $0.id == id }?.name
    }

    private func sortDate(_ text: String) -> Date {
        Formatters.parseDateOrDateTime(text) ?? .distantPast
    }

    private func metricGrid(summary: BusinessSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                metric("报价", ReportBuilder.money(summary.quoteTotal), .orange)
                metric("合同", ReportBuilder.money(summary.contractAmount), .blue)
            }
            GridRow {
                metric("已收", ReportBuilder.money(summary.paidAmount), .green)
                metric("未收", ReportBuilder.money(max(summary.contractAmount - summary.paidAmount, 0)), .red)
            }
            GridRow {
                metric("材料成本", ReportBuilder.money(summary.materialCost), .blue)
                metric("人工成本", ReportBuilder.money(summary.laborCostAmount), .purple)
            }
            GridRow {
                metric("毛利估算", ReportBuilder.money(summary.contractAmount - summary.materialCost - summary.laborCostAmount), .teal)
                metric("待补", "\(summary.pendingMaterialCount + summary.unpricedQuoteCount)", .red)
            }
        }
        .padding(.vertical, 4)
    }

    private func businessInsightGrid(summary: BusinessSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                metric("应收账龄", receivableAgeText(summary), receivableAgeColor(summary))
                metric("最近回款", recentCollectionText(summary), recentCollectionColor(summary))
            }
            GridRow {
                metric("成本异常", costAnomalyText(summary), costAnomalyColor(summary))
                metric("利润风险", profitRiskText(summary), profitRiskColor(summary))
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func receivableAgeText(_ summary: BusinessSummary) -> String {
        guard summary.receivableAmount > 0 else { return "无应收" }
        guard let days = summary.receivableAgeDays else { return "未填完工日" }
        if days == 0 { return "未到期 · \(ReportBuilder.money(summary.receivableAmount))" }
        return "\(days)天 · \(ReportBuilder.money(summary.receivableAmount))"
    }

    private func receivableAgeColor(_ summary: BusinessSummary) -> Color {
        guard summary.receivableAmount > 0 else { return .green }
        guard let days = summary.receivableAgeDays else { return .orange }
        if days >= 60 { return .red }
        if days >= 30 { return .orange }
        if days > 0 { return .blue }
        return .secondary
    }

    private func recentCollectionText(_ summary: BusinessSummary) -> String {
        guard let collection = summary.recentCollection else { return "暂无回款" }
        let base = "\(collection.date) · \(ReportBuilder.money(collection.amount))"
        if let projectName = collection.projectName {
            return "\(base) · \(projectName)"
        }
        return base
    }

    private func recentCollectionColor(_ summary: BusinessSummary) -> Color {
        summary.recentCollection == nil ? .secondary : .green
    }

    private func costAnomalyText(_ summary: BusinessSummary) -> String {
        let totalCost = summary.materialCost + summary.laborCostAmount
        let pendingCount = summary.pendingMaterialCount + summary.unpricedQuoteCount
        guard summary.contractAmount > 0 else { return "缺合同金额" }
        guard totalCost > 0 else {
            return pendingCount > 0 ? "待补 \(pendingCount) 项" : "未录成本"
        }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 {
            return "超合同 \(ReportBuilder.money(totalCost - summary.contractAmount))"
        }
        if ratio >= 0.85 {
            return "成本占比 \(percent(ratio))"
        }
        if pendingCount > 0 {
            return "待补 \(pendingCount) 项"
        }
        return "正常 \(percent(ratio))"
    }

    private func costAnomalyColor(_ summary: BusinessSummary) -> Color {
        let totalCost = summary.materialCost + summary.laborCostAmount
        guard summary.contractAmount > 0 else { return .orange }
        guard totalCost > 0 else { return summary.pendingMaterialCount + summary.unpricedQuoteCount > 0 ? .orange : .secondary }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 { return .red }
        if ratio >= 0.85 { return .orange }
        if summary.pendingMaterialCount + summary.unpricedQuoteCount > 0 { return .orange }
        return .green
    }

    private func profitRiskText(_ summary: BusinessSummary) -> String {
        guard summary.contractAmount > 0 else { return "缺合同金额" }
        let profit = summary.contractAmount - summary.materialCost - summary.laborCostAmount
        let margin = profit / summary.contractAmount
        if profit < 0 {
            return "亏损 \(ReportBuilder.money(abs(profit)))"
        }
        if margin < 0.10 {
            return "低毛利 \(percent(margin))"
        }
        if margin < 0.20 {
            return "关注 \(percent(margin))"
        }
        return "健康 \(percent(margin))"
    }

    private func profitRiskColor(_ summary: BusinessSummary) -> Color {
        guard summary.contractAmount > 0 else { return .orange }
        let profit = summary.contractAmount - summary.materialCost - summary.laborCostAmount
        let margin = profit / summary.contractAmount
        if profit < 0 { return .red }
        if margin < 0.10 { return .red }
        if margin < 0.20 { return .orange }
        return .green
    }

    private func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }

    private func laborHours(_ record: LaborRecord) -> Double {
        ReportBuilder.laborHours(record)
    }

    private func averageProgress(_ tasks: [ProgressTask]) -> Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
    }
}

private struct BusinessSummary {
    var quoteTotal: Double
    var contractAmount: Double
    var paidAmount: Double
    var receivableAmount: Double
    var receivableAgeDays: Int?
    var recentCollection: CollectionSnapshot?
    var materialCost: Double
    var laborCostAmount: Double
    var materialItems: Int
    var laborHours: Double
    var logDays: Int
    var progress: Double
    var circuitPlanCount: Int
    var pendingMaterialCount: Int
    var unpricedQuoteCount: Int
}
