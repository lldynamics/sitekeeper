import SwiftUI

extension LaborRecordView {
    // MARK: - 导出配置

    var laborExportSheet: some View {
        AppBusinessFormSheet(
            title: AppLocalization.string("导出人工记录"),
            primaryActionTitle: String(format: AppLocalization.string("导出 %@"), exportFormat.displayName),
            onCancel: { showExportConfig = false },
            onPrimaryAction: {
                switch exportFormat {
                case .csv: performCSVExport()
                case .html: performHTMLExport()
                }
                showExportConfig = false
            }
        ) {
            Section(AppLocalization.string("筛选范围")) {
                Picker(AppLocalization.string("项目"), selection: $exportProjectFilter) {
                    Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
                    ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                }
                Picker(AppLocalization.string("班组"), selection: $exportTeamFilter) {
                    Text(AppLocalization.string("全部班组")).tag("")
                    ForEach(savedTeams, id: \.self) { t in Text(t).tag(t) }
                }
                Picker(AppLocalization.string("工种"), selection: $exportWorkTypeFilter) {
                    Text(AppLocalization.string("全部工种")).tag("")
                    ForEach(savedWorkTypes, id: \.self) { t in Text(t).tag(t) }
                }
                DatePicker(AppLocalization.string("从"), selection: $exportStartDate, displayedComponents: .date)
                DatePicker(AppLocalization.string("至"), selection: $exportEndDate, displayedComponents: .date)
            }
            Section {
                Picker(AppLocalization.string("格式"), selection: $exportFormat) {
                    ForEach(LaborExportFormat.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
            }
        }
    }

    private func recordsForExport() -> [LaborRecord] {
        var records = store.laborRecords
        if let pid = exportProjectFilter { records = records.filter { $0.projectId == pid } }
        if !exportTeamFilter.isEmpty { records = records.filter { $0.teamName == exportTeamFilter } }
        if !exportWorkTypeFilter.isEmpty { records = records.filter { $0.workType == exportWorkTypeFilter } }
        let start = CalendarDay(date: exportStartDate)
        let end = CalendarDay(date: exportEndDate)
        records = records.filter { guard let day = $0.date.calendarDay() else { return false }
        return day >= start && day <= end }
        return records
    }

    private func performCSVExport() {
        let records = recordsForExport()
        var rows = [ReportBuilder.csv([
            AppLocalization.string("日期"),
            AppLocalization.string("项目"),
            AppLocalization.string("工种"),
            AppLocalization.string("班组"),
            AppLocalization.string("人数"),
            AppLocalization.string("数量"),
            AppLocalization.string("单位"),
            AppLocalization.string("工价"),
            AppLocalization.string("合计"),
            AppLocalization.string("已结算"),
            AppLocalization.string("备注")
        ])]
        rows += records.map { r in
            let project = store.projects.first { $0.id == r.projectId }?.name ?? ""
            return ReportBuilder.csv([
                r.date,
                project,
                r.workType,
                r.teamName,
                r.workers,
                r.hours,
                r.workloadUnit.displayName,
                r.unitRate,
                ReportBuilder.amountRaw(ReportBuilder.laborLineTotal(r)),
                r.isSettled ? AppLocalization.string("是") : AppLocalization.string("否"),
                r.note
            ])
        }
        let data = ReportBuilder.csvData(rows: rows)
        exportPayload = ExportPayload(data: data, contentType: .commaSeparatedText, defaultFilename: AppLocalization.string("人工记录.csv"))
        showExporter = true
    }

    private func performHTMLExport() {
        let records = recordsForExport()
        let data = LaborRecordExportBuilder.makeHTML(
            records: records,
            projects: store.projects
        )
        exportPayload = ExportPayload(data: data, contentType: .html, defaultFilename: AppLocalization.string("人工记录表.html"))
        showExporter = true
    }
}

enum LaborRecordExportBuilder {
    static func makeHTML(
        records: [LaborRecord],
        projects: [Project],
        exportTime: String = Formatters.displayNow()
    ) -> Data {
        let workloadSummary = LaborWorkloadUnit.allCases.compactMap { unit -> String? in
            let total = records
                .filter { $0.workloadUnit == unit }
                .reduce(QuantityValue.zero) { $0 + $1.totalWorkload }
            guard !total.isZero else { return nil }
            let unitName = unit.quoteUnit ?? unit.displayName
            return "\(total.decimal.formatted(.number.precision(.fractionLength(0...2))))\(unitName)"
        }.joined(separator: " · ")
        let totalCost = records.reduce(MoneyValue.zero) { $0 + ReportBuilder.laborLineTotal($1) }
        let unsettledCost = records.filter { !$0.isSettled }.reduce(MoneyValue.zero) { $0 + ReportBuilder.laborLineTotal($1) }
        let summaryParts = [
            "\(records.count)\(AppLocalization.string("条"))",
            workloadSummary,
            "\(AppLocalization.string("合计")) \(ReportBuilder.money(totalCost))",
            "\(AppLocalization.string("待结算")) \(ReportBuilder.money(unsettledCost))"
        ].filter { !$0.isEmpty }

        var html = """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>body{font-family:-apple-system,Helvetica;padding:20px;}
        h3{color:#333;}table{border-collapse:collapse;width:100%;margin:10px 0;}
        th{background:#f5f5f5;border:1px solid #ddd;padding:8px;text-align:left;font-size:13px;}
        td{border:1px solid #ddd;padding:7px;font-size:12px;}
        .settled{color:#2E8B3E;}.unsettled{color:#E5661A;}
        .summary{color:#666;font-size:13px;margin:8px 0;}
        .total{font-weight:bold;color:#E5661A;}</style></head><body>
        <h3>\(ReportBuilder.escapeHTML(AppLocalization.string("人工记录报表")))</h3>
        <p class="summary">\(ReportBuilder.escapeHTML(summaryParts.joined(separator: " · ")))</p>
        <table><tr><th>\(AppLocalization.string("日期"))</th><th>\(AppLocalization.string("项目"))</th><th>\(AppLocalization.string("工种"))</th><th>\(AppLocalization.string("班组"))</th><th>\(AppLocalization.string("人数"))</th><th>\(AppLocalization.string("数量"))</th><th>\(AppLocalization.string("单位"))</th><th>\(AppLocalization.string("工价"))</th><th>\(AppLocalization.string("合计"))</th><th>\(AppLocalization.string("状态"))</th></tr>
        """
        for r in records {
            let project = projects.first { $0.id == r.projectId }?.name ?? ""
            let statusClass = r.isSettled ? "settled" : "unsettled"
            let status = r.isSettled ? AppLocalization.string("已结算") : AppLocalization.string("待结算")
            let cells = [r.date, project, r.workType, r.teamName, r.workers, r.hours, r.workloadUnit.displayName, r.unitRate]
                .map { "<td>\(ReportBuilder.escapeHTML(String(describing: $0)))</td>" }
                .joined()
            html += "<tr>\(cells)<td class=\"total\">\(ReportBuilder.escapeHTML(ReportBuilder.money(ReportBuilder.laborLineTotal(r))))</td><td class=\"\(statusClass)\">\(ReportBuilder.escapeHTML(status))</td></tr>"
        }
        html += "<tr><td colspan=\"9\" style=\"text-align:right;font-weight:bold;\">\(ReportBuilder.escapeHTML(AppLocalization.string("合计")))</td><td class=\"total\">\(ReportBuilder.escapeHTML(ReportBuilder.money(totalCost)))</td></tr>"
        html += "</table><p class=\"summary\">\(ReportBuilder.escapeHTML(String(format: AppLocalization.string("导出时间: %@"), exportTime)))</p></body></html>"

        return html.data(using: .utf8) ?? Data()
    }
}
