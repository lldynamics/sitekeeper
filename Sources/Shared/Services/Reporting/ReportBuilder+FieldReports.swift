import Foundation
import PDFKit

extension ReportBuilder {
    static func fieldReportLines(_ report: ProjectFieldReport, title: String, selectedPhotoIDs: Set<String> = []) -> [String] {
        var lines = [title, report.projectName, locFormat("报表期间：%@", report.period.displayText),
                     locFormat("生成时间: %@", Formatters.displayNow()), "", loc("期间施工记录")]
        if report.logs.isEmpty { lines.append(loc("本期间没有施工日志。")) }
        for log in report.logs {
            lines.append(log.date.calendarDay(in: report.period.timeZone)?.storageText ?? log.date.storageText)
            appendFieldText(log.content, label: loc("施工内容"), to: &lines)
            appendFieldText(log.safety, label: loc("安全事项"), to: &lines)
            appendFieldText(log.qualityIssue, label: loc("质量问题"), to: &lines)
            appendFieldText(log.rectification, label: loc("整改情况"), to: &lines)
            appendFieldText(log.tomorrowPlan, label: loc("明日计划（日志原文）"), to: &lines)
            lines.append("")
        }
        lines.append(loc("期间明确完成的待办"))
        if report.completedTodos.isEmpty { lines.append(loc("本期间没有带明确完成日期的已完成待办。")) }
        lines += report.completedTodos.map { "- \($0.completedAt?.calendarDay(in: report.period.timeZone)?.storageText ?? "")  \($0.title)" }
        lines += ["", loc("当前未完成事项"), loc("以下为生成时的当前状态，不代表期间历史状态。")]
        if report.currentOpenTodos.isEmpty { lines.append(loc("当前没有未完成待办。")) }
        lines += report.currentOpenTodos.map { "- \($0.title)  \(loc("计划日期"))：\(fieldReportDate($0.dueDate))" }
        lines += ["", loc("当前进度快照"), loc("进度没有历史快照，无法计算本期间新增或还原期末进度。")]
        if report.currentProgress.isEmpty { lines.append(loc("当前没有进度任务。")) }
        lines += report.currentProgress.map {
            let completion = $0.completion.isFinite ? "\(Int($0.clampedCompletion * 100))%" : loc("进度待确认")
            return "- \($0.title)  \(completion)"
        }
        if report.excludedUndatedLogCount > 0 || report.excludedUndatedCompletionCount > 0 {
            lines += ["", locFormat("未纳入期间：日期不明日志 %lld 条、完成日期不明待办 %lld 项。",
                                    Int64(report.excludedUndatedLogCount), Int64(report.excludedUndatedCompletionCount))]
        }
        let photoCount = report.photos.filter { selectedPhotoIDs.contains($0.id) }.count
        lines += ["", locFormat("已选照片 %lld 张。照片通过独立照片 PDF 预览和分享，不嵌入本正文 PDF。", Int64(photoCount))]
        return lines
    }

    static func makeFieldReportPDF(_ report: ProjectFieldReport, title: String, selectedPhotoIDs: Set<String> = []) -> Data {
        pdfData(lines: paginatedFieldLines(fieldReportLines(report, title: title, selectedPhotoIDs: selectedPhotoIDs)))
    }

    static func customerStatementLines(_ statement: ProjectCustomerStatement) -> [String] {
        let source = statement.paidSource == .recordedCollections
            ? loc("已收来源：本项目正式收款记录累计。")
            : loc("已收来源：历史手填已收；没有原始收款日期，不计入本期收款。")
        var lines = [loc("客户精简对账单"), statement.projectName,
                     locFormat("报表期间：%@", statement.period.displayText),
                     locFormat("生成时间: %@", Formatters.displayNow()), "",
                     loc("当前合同与累计金额"),
                     loc("累计值为生成时的当前累计，不是所选期间期末余额。"),
                     locFormat("合同金额：%@", fieldReportMoney(statement.contractAmount)),
                     locFormat("当前累计已收：%@", fieldReportMoney(statement.currentCumulativePaid)), source,
                     locFormat("当前合同未收：%@", fieldReportMoney(statement.currentOutstanding)), "",
                     loc("本期正式收款"), locFormat("本期收款合计：%@", fieldReportMoney(statement.periodReceived))]
        if statement.periodReceipts.isEmpty { lines.append(loc("本期间没有正式收款记录。")) }
        lines += statement.periodReceipts.map {
            "- \($0.date.calendarDay(in: statement.period.timeZone)?.storageText ?? "")  \(fieldReportMoney($0.amount))"
        }
        if statement.undatedReceiptCount > 0 {
            lines.append(locFormat("另有 %lld 笔日期不明的正式收款参与当前累计，未计入本期。", Int64(statement.undatedReceiptCount)))
        }
        if !statement.plannedReceipts.isEmpty {
            lines += ["", loc("当前应收分期计划"), loc("计划金额仅为约定，不代表已收款，也不额外计入合同未收。")]
            lines += statement.plannedReceipts.map {
                "- \($0.title)  \(fieldReportDate($0.dueDate))  \(fieldReportMoney($0.amount))"
            }
        }
        lines += ["", loc("请核对项目、期间及金额后，手动分享给客户。")]
        return lines
    }

    static func makeCustomerStatementPDF(_ statement: ProjectCustomerStatement) -> Data {
        pdfData(lines: paginatedFieldLines(customerStatementLines(statement)))
    }

    /// Photos deliberately stay in a separate document. A cover explicitly lists
    /// missing files; the existing photo renderer supplies placeholders for them.
    static func makeFieldReportPhotosPDF(_ report: ProjectFieldReport, selectedPhotoIDs: Set<String>) async -> Data {
        let selected = report.photos.filter { selectedPhotoIDs.contains($0.id) }
        let missing = selected.filter { !PhotoStorage.exists(fileName: $0.photo.fileName) }
        let title = loc("施工报表照片附件")
        var cover = [title, report.projectName, locFormat("报表期间：%@", report.period.displayText),
                     locFormat("已选照片 %lld 张，其中缺失文件 %lld 张。", Int64(selected.count), Int64(missing.count)),
                     loc("本文件是独立照片附件。缺失或无法读取的照片显示为空白占位，不能作为已附照片凭证。")]
        cover += missing.map { "- \(fieldReportDate($0.date))  \(loc("照片文件缺失"))" }
        let coverData = pdfData(lines: paginatedFieldLines(cover))
        let photoData = await makePhotoWallPDFAsync(title: title, items: selected.map {
            ReportPhotoItem(date: $0.date, projectName: report.projectName, tag: $0.photo.tag.displayName,
                            note: $0.photo.note, fileName: $0.photo.fileName)
        })
        guard let document = PDFDocument(data: coverData), let photos = PDFDocument(data: photoData) else { return coverData }
        for index in 0..<photos.pageCount {
            if let page = photos.page(at: index) { document.insert(page, at: document.pageCount) }
        }
        return document.dataRepresentation() ?? coverData
    }

    static func fieldReportMoney(_ value: MoneyValue) -> String {
        value.isEmpty ? loc("未填写") : money(value)
    }

    static func fieldReportDate(_ value: BusinessDateValue) -> String {
        value.isEmpty ? loc("日期未填写") : value.storageText
    }

    private static func appendFieldText(_ text: String, label: String, to lines: inout [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lines.append("\(label)：\(text)")
    }

    /// The shared renderer paginates between lines. Break long input into short
    /// pieces so a single multi-paragraph construction entry cannot run off-page.
    private static func paginatedFieldLines(_ lines: [String]) -> [String] {
        lines.flatMap { line in
            line.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
                guard !paragraph.isEmpty else { return [""] }
                var result: [String] = []
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: 44, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    result.append(String(paragraph[start..<end]))
                    start = end
                }
                return result
            }
        }
    }
}
