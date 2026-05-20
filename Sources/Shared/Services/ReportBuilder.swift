import Foundation
import UIKit

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

    private enum ProjectPackageSchema {
        static let version = "1"
        static let type = "project_delivery_package"
        static let readmeFileName = "README.txt"
        static let deliveryDirectory = "00-delivery"
        static let documentDirectory = "01-documents"
        static let drawingDirectory = "02-drawings"
        static let photoDirectory = "03-site-photos"
        static let quickNoteDirectory = "04-quick-notes"
        static let contactDirectory = "05-contacts"
        static let checklistFileName = "delivery_checklist.txt"
        static let documentChecklistFileName = "document_checklist.tsv"
        static let currentDrawingRegisterFileName = "current_drawings.tsv"
        static let drawingMissingCheckFileName = "drawing_missing_check.tsv"
        static let openDrawingIssuesFileName = "open_drawing_issues.tsv"
        static let quickNotesFileName = "quick_notes.tsv"
        static let contactsFileName = "contacts.tsv"

        static func pdfFileName(folder: String) -> String {
            "\(folder)_project_delivery_package.pdf"
        }
    }

    private enum ProjectDeliveryPackageHealthCheck: String, CaseIterable {
        case receipts
        case drawings
        case todos
        case backup
        case originals

        var displayName: String {
            switch self {
            case .receipts:
                return ReportBuilder.loc("缺票据")
            case .drawings:
                return ReportBuilder.loc("缺图纸")
            case .todos:
                return ReportBuilder.loc("未完成待办")
            case .backup:
                return ReportBuilder.loc("未备份")
            case .originals:
                return ReportBuilder.loc("资料缺原件")
            }
        }
    }

    private struct ProjectDeliveryPackageBackupState {
        let latestBackupDate: Date?
        let reminderDays: Int
        let referenceDate: Date

        static func current(referenceDate: Date = Date()) -> ProjectDeliveryPackageBackupState {
            let reminderDaysRaw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
            let reminderDays = max(1, reminderDaysRaw == 0 ? 7 : reminderDaysRaw)
            let localBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.localBackupLastSuccessAt)
            let cloudBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
            let localBackupDate = localBackupRaw > 0 ? Date(timeIntervalSince1970: localBackupRaw) : nil
            let cloudBackupDate = cloudBackupRaw > 0 ? Date(timeIntervalSince1970: cloudBackupRaw) : nil
            let latestBackupDate: Date? = {
                switch (localBackupDate, cloudBackupDate) {
                case let (lhs?, rhs?):
                    return max(lhs, rhs)
                case let (lhs?, nil):
                    return lhs
                case let (nil, rhs?):
                    return rhs
                case (nil, nil):
                    return nil
                }
            }()

            return ProjectDeliveryPackageBackupState(
                latestBackupDate: latestBackupDate,
                reminderDays: reminderDays,
                referenceDate: referenceDate
            )
        }

        var isFresh: Bool {
            guard latestBackupDate != nil else { return false }
            return daysSinceLatestBackup < reminderDays
        }

        var daysSinceLatestBackup: Int {
            guard let latestBackupDate else { return Int.max }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: latestBackupDate)
            let end = calendar.startOfDay(for: referenceDate)
            return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
        }

        var detail: String {
            guard let latestBackupDate else {
                return ReportBuilder.loc("尚未记录成功备份")
            }
            if daysSinceLatestBackup == 0 {
                return ReportBuilder.locFormat("今天已备份，提醒阈值 %lld 天", Int64(reminderDays))
            }
            return ReportBuilder.locFormat(
                "最近备份 %@，已过 %lld 天",
                Formatters.dateTime.string(from: latestBackupDate),
                Int64(daysSinceLatestBackup)
            )
        }

        var latestBackupExportValue: String {
            latestBackupDate.map { Formatters.dateTime.string(from: $0) } ?? ""
        }
    }

    private struct ProjectDeliveryPackageHealthReport {
        let missingReceiptCount: Int
        let drawingCount: Int
        let openTodoCount: Int
        let backupState: ProjectDeliveryPackageBackupState
        let missingOriginalEntries: [String]

        var failedChecks: [ProjectDeliveryPackageHealthCheck] {
            ProjectDeliveryPackageHealthCheck.allCases.filter { !isPassed($0) }
        }

        var score: Int {
            max(0, 100 - failedChecks.count * 20)
        }

        var isDeliverable: Bool {
            failedChecks.isEmpty
        }

        var machineVerdict: String {
            isDeliverable ? "deliverable" : "not_deliverable"
        }

        var verdictDisplayName: String {
            isDeliverable ? ReportBuilder.loc("可交付") : ReportBuilder.loc("不可交付")
        }

        var failedCheckKeys: String {
            failedChecks.map(\.rawValue).joined(separator: ",")
        }

        var failedCheckDisplayText: String {
            guard !failedChecks.isEmpty else { return ReportBuilder.loc("全部通过") }
            return failedChecks.map(\.displayName).joined(separator: ReportBuilder.loc("、"))
        }

        func isPassed(_ check: ProjectDeliveryPackageHealthCheck) -> Bool {
            switch check {
            case .receipts:
                return missingReceiptCount == 0
            case .drawings:
                return drawingCount > 0
            case .todos:
                return openTodoCount == 0
            case .backup:
                return backupState.isFresh
            case .originals:
                return missingOriginalEntries.isEmpty
            }
        }
    }

    private struct ProjectDrawingOpenIssueRow {
        let drawing: ProjectDrawing
        let openTodos: [SiteTodo]

        var summary: String {
            let note = drawing.issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
            let titles = openTodos.map(\.title).filter { !$0.isEmpty }
            return titles.isEmpty ? ReportBuilder.loc("关联待办未关闭") : titles.joined(separator: ReportBuilder.loc("、"))
        }
    }

    static func projectPackageArchiveFileName(projectName: String) -> String {
        "\(safeZipName(projectName, fallback: "untitled_project"))_project_delivery_package.zip"
    }

    /// 常用状态值
    static var locYes: String { loc("是") }
    static var locNo: String { loc("否") }
    static var locDone: String { loc("完成") }
    static var locOverdue: String { loc("延期") }
    static var locPending: String { loc("待办") }
    static var locNotFilled: String { loc("未填写") }

    static func makeQuotationPDF(
        title: String,
        items: [QuoteItem],
        projects: [Project]
    ) -> Data {
        let validityDays = max(1, UserPreferences.int(UserPreferenceKeys.quoteValidityDays, default: 15))
        let validUntil = Formatters.date.string(
            from: Calendar.current.date(byAdding: .day, value: validityDays, to: Date()) ?? Date()
        )
        let projectAddress = resolvedSingleProjectAddress(items: items, projects: projects) ?? locNotFilled
        let companyName = UserPreferences.string(UserPreferenceKeys.companyName, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyPhone = UserPreferences.string(UserPreferenceKeys.companyPhone, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyAddress = UserPreferences.string(UserPreferenceKeys.companyAddress, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = QuotationDocumentMeta(
            companyName: companyName.isEmpty ? locNotFilled : companyName,
            companyPhone: companyPhone.isEmpty ? locNotFilled : companyPhone,
            companyAddress: companyAddress.isEmpty ? locNotFilled : companyAddress,
            customerName: locNotFilled,
            projectAddress: projectAddress,
            validUntil: validUntil,
            signerName: loc("项目负责人")
        )
        return makeQuotationPDF(title: title, items: items, projects: projects, meta: meta)
    }

    static func makeQuotationPDF(
        title: String,
        items: [QuoteItem],
        projects: [Project],
        meta: QuotationDocumentMeta
    ) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 36
        let maxWidth = page.width - margin * 2

        let subtotal = items.reduce(MoneyValue.zero) { $0 + quoteLineTotalValue($1) }
        let tax = items.reduce(MoneyValue.zero) { $0 + quoteTaxValue($1) }
        let discount = items.reduce(MoneyValue.zero) { $0 + quoteDiscountValue($1) }
        let total = subtotal + tax - discount
        let projectName = resolvedProjectName(items: items, projects: projects)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 36

            y = drawPDFText(title, at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20), alignment: .center) + 4
            y = drawPDFText(meta.companyName, at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11), alignment: .center)
            y = drawPDFText(String(format: loc("电话: %@    地址: %@"), meta.companyPhone, meta.companyAddress), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 10), alignment: .center) + 12

            y = drawPDFText(String(format: loc("客户名称: %@"), meta.customerName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText(String(format: loc("项目名称: %@"), projectName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText(String(format: loc("项目地址: %@"), meta.projectAddress), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText(String(format: loc("报价日期: %@    有效期至: %@"), Formatters.date.string(from: Date()), meta.validUntil), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11)) + 10

            let columns: [(title: String, width: CGFloat)] = [
                (loc("项目"), 124), (loc("单位"), 38), (loc("数量"), 44), (loc("单价"), 62),
                (loc("税率"), 42), (loc("折扣"), 42), (loc("金额"), 76), (loc("备注"), 95)
            ]
            let rowHeight: CGFloat = 24
            y = drawPDFTableHeader(columns: columns, startX: margin, y: y, height: rowHeight)

            let rows = items.isEmpty ? [[
                loc("暂无明细"), "-", "-", "-", "-", "-", "-", "-"
            ]] : items.map { item in
                [
                    item.name,
                    item.unit,
                    item.quantity,
                    money(item.unitPriceValue.doubleValue),
                    "\(item.taxRate)%",
                    "\(item.discountRate)%",
                    money(quoteGrandTotal(item)),
                    item.notes
                ]
            }

            for row in rows {
                if y > page.height - 180 {
                    context.beginPage()
                    y = 36
                    y = drawPDFTableHeader(columns: columns, startX: margin, y: y, height: rowHeight)
                }
                y = drawPDFTableRow(values: row, columns: columns, startX: margin, y: y, height: rowHeight)
            }

            y += 12
            y = drawPDFText(locFormat("小计: %@", money(subtotal.doubleValue)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText(locFormat("税额: %@    折扣: -%@", money(tax.doubleValue), money(discount.doubleValue)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText(locFormat("合计: %@", money(total.doubleValue)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 14)) + 18

            _ = drawPDFText(locFormat("签字确认: %@____________________", meta.signerName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
        }
    }

    static func makeQuotationExcelHTML(
        title: String,
        items: [QuoteItem],
        projects: [Project],
        meta: QuotationDocumentMeta
    ) -> Data {
        let subtotal = items.reduce(MoneyValue.zero) { $0 + quoteLineTotalValue($1) }
        let tax = items.reduce(MoneyValue.zero) { $0 + quoteTaxValue($1) }
        let discount = items.reduce(MoneyValue.zero) { $0 + quoteDiscountValue($1) }
        let total = subtotal + tax - discount
        let projectName = resolvedProjectName(items: items, projects: projects)

        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
        body{font-family:-apple-system,Helvetica,Arial,sans-serif;padding:20px;color:#1f2937;}
        h2{margin:0 0 8px;}
        .meta{color:#4b5563;font-size:12px;line-height:1.7;margin:2px 0;}
        table{border-collapse:collapse;width:100%;margin-top:12px;}
        th,td{border:1px solid #d1d5db;padding:6px 8px;font-size:12px;vertical-align:top;}
        th{background:#f3f4f6;font-weight:600;}
        td.num{text-align:right;white-space:nowrap;}
        .summary{margin-top:12px;font-size:13px;}
        .summary strong{font-size:15px;}
        </style>
        </head>
        <body>
        """

        html += "<h2>\(escapeHTML(title))</h2>"
        html += "<p class=\"meta\">\(escapeHTML(meta.companyName)) · \(escapeHTML(meta.companyPhone)) · \(escapeHTML(meta.companyAddress))</p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("客户名称: %@", meta.customerName)))</p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("项目名称: %@", projectName)))</p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("项目地址: %@", meta.projectAddress)))</p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("报价日期: %@，有效期至: %@", Formatters.date.string(from: Date()), meta.validUntil)))</p>"

        html += """
        <table>
        <tr>
            <th>\(escapeHTML(loc("项目")))</th><th>\(escapeHTML(loc("单位")))</th><th>\(escapeHTML(loc("数量")))</th><th>\(escapeHTML(loc("单价")))</th><th>\(escapeHTML(loc("税率")))</th><th>\(escapeHTML(loc("折扣")))</th><th>\(escapeHTML(loc("金额")))</th><th>\(escapeHTML(loc("版本")))</th><th>\(escapeHTML(loc("状态")))</th><th>\(escapeHTML(loc("备注")))</th>
        </tr>
        """

        if items.isEmpty {
            html += "<tr><td colspan=\"10\">\(escapeHTML(loc("暂无明细")))</td></tr>"
        } else {
            for item in items {
                html += "<tr>"
                html += "<td>\(escapeHTML(item.name))</td>"
                html += "<td>\(escapeHTML(item.unit))</td>"
                html += "<td class=\"num\">\(escapeHTML(item.quantity))</td>"
                html += "<td class=\"num\">\(escapeHTML(money(item.unitPriceValue.doubleValue)))</td>"
                html += "<td class=\"num\">\(escapeHTML(item.taxRate))%</td>"
                html += "<td class=\"num\">\(escapeHTML(item.discountRate))%</td>"
                html += "<td class=\"num\">\(escapeHTML(money(quoteGrandTotal(item))))</td>"
                html += "<td>\(escapeHTML(item.versionName))</td>"
                html += "<td>\(escapeHTML(item.status.displayName))</td>"
                html += "<td>\(escapeHTML(item.notes))</td>"
                html += "</tr>"
            }
        }

        html += "</table>"
        html += "<p class=\"summary\">\(escapeHTML(locFormat("小计: %@", money(subtotal.doubleValue))))</p>"
        html += "<p class=\"summary\">\(escapeHTML(locFormat("税额: %@，折扣: -%@", money(tax.doubleValue), money(discount.doubleValue))))</p>"
        html += "<p class=\"summary\"><strong>\(escapeHTML(locFormat("合计: %@", money(total.doubleValue))))</strong></p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("签字确认: %@", meta.signerName)))</p>"
        html += "<p class=\"meta\">\(escapeHTML(locFormat("导出时间: %@", Formatters.now())))</p>"
        html += "</body></html>"

        return Data(html.utf8)
    }

    static func makePhotoWallPDF(title: String, items: [ReportPhotoItem]) -> Data {
        renderPhotoWallPDF(title: title, items: items, thumbnailsByFileName: [:])
    }

    static func makePhotoWallPDFAsync(title: String, items: [ReportPhotoItem]) async -> Data {
        let thumbnailsByFileName = await preloadPhotoWallThumbnails(for: items)
        return renderPhotoWallPDF(title: title, items: items, thumbnailsByFileName: thumbnailsByFileName)
    }

    private static func renderPhotoWallPDF(
        title: String,
        items: [ReportPhotoItem],
        thumbnailsByFileName: [String: UIImage]
    ) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            drawPhotoWallPages(
                title: title,
                items: items,
                context: context,
                page: page,
                margin: 36,
                thumbnailsByFileName: thumbnailsByFileName
            )
        }
    }

    static func makeProjectArchiveReportPDF(
        project: Project,
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        logs: [DailyLog],
        tasks: [ProgressTask],
        todos: [SiteTodo],
        drawings: [ProjectDrawing] = [],
        contacts: [ProjectContact] = [],
        financialRecords: [ProjectFinancialRecord] = [],
        documents: [ProjectDocument] = [],
        warehouseMovements: [ProjectWarehouseMovement] = [],
        quickNotes: [QuickNote] = [],
        paidAmountOverride: Double? = nil
    ) -> Data {
        let contract = number(project.contractAmount)
        let quoteTotal = quotes.reduce(0) { $0 + quoteGrandTotal($1) }
        let materialCost = materials.reduce(0) { $0 + materialLineTotal($1) }
        let laborCost = labor.reduce(0) { $0 + laborLineTotal($1) }
        let income = ProjectFinancialMetrics.income(financialRecords)
        let expense = ProjectFinancialMetrics.expense(financialRecords)
        let paid = paidAmountOverride ?? ProjectFinancialMetrics.collectionAmount(financialRecords)
        let openTodos = todos.filter { !$0.isDone }
        let overdueTodos = todos.filter(\.isOverdue)
        let overdueTasks = tasks.filter { task in
            guard task.clampedCompletion < 1,
                  let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
        let dueReminders = financialRecords.filter(\.isDueReminderOpen)
        let missingReceipts = financialRecords.filter { record in
            guard record.countsInBusinessMetrics, record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = documents.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let progress = tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
        let photosCount = logs.reduce(0) { $0 + $1.photoAttachments.count }

        var lines: [String] = []
        lines.append(locFormat("%@ 项目归档报告", project.name))
        lines.append(locFormat("生成时间: %@", Formatters.now()))
        lines.append("")
        lines.append(loc("一、项目概况"))
        lines.append(locFormat("地址: %@", project.location.isEmpty ? locNotFilled : project.location))
        lines.append(locFormat("客户: %@  电话: %@", project.customerName.isEmpty ? locNotFilled : project.customerName, project.customerPhone.isEmpty ? "-" : project.customerPhone))
        lines.append(locFormat("负责人: %@", project.managerName.isEmpty ? locNotFilled : project.managerName))
        lines.append(locFormat("状态: %@  工期: %@ 至 %@", project.status.displayName, project.startDate.isEmpty ? "-" : project.startDate, project.expectedEndDate.isEmpty ? "-" : project.expectedEndDate))
        lines.append("")
        lines.append(loc("二、经营汇总"))
        lines.append(locFormat("合同金额: %@  已收: %@  未收: %@", money(contract), money(paid), money(max(contract - paid, 0))))
        lines.append(locFormat("报价合计: %@  材料成本: %@  人工成本: %@", money(quoteTotal), money(materialCost), money(laborCost)))
        lines.append(locFormat("记账收入: %@  记账支出: %@  账面结余: %@", money(income), money(expense), money(income - expense)))
        lines.append(locFormat("毛利估算: %@", money(contract - materialCost - laborCost)))
        lines.append("")
        lines.append(loc("三、资料完整度"))
        lines.append(locFormat("施工日志: %lld 条  现场照片: %lld 张  进度平均: %lld%%", Int64(logs.count), Int64(photosCount), Int64(progress * 100)))
        lines.append(locFormat("材料: %lld 条  预结算: %lld 条  人工: %lld 条  仓库流水: %lld 条", Int64(materials.count), Int64(quotes.count), Int64(labor.count), Int64(warehouseMovements.count)))
        lines.append(locFormat("票据/资料: %lld 份  图纸: %lld 份  联系人: %lld 位  随手记: %lld 条", Int64(documents.count), Int64(drawings.count), Int64(contacts.count), Int64(quickNotes.count)))
        lines.append(locFormat("施工资料清单: 覆盖 %lld/%lld 类  缺项 %lld 类  待处理 %lld 份", Int64(documentChecklist.coveredCount), Int64(documentChecklist.requiredCount), Int64(documentChecklist.missingCount), Int64(documentChecklist.actionCount)))
        lines.append("")
        lines.append(loc("四、归档前待处理"))
        if openTodos.isEmpty && overdueTasks.isEmpty && dueReminders.isEmpty && missingReceipts.isEmpty {
            lines.append(loc("无未完成待办、逾期进度、到期提醒或缺票账目。"))
        } else {
            lines.append(locFormat("未完成待办: %lld 项，其中逾期 %lld 项", Int64(openTodos.count), Int64(overdueTodos.count)))
            lines.append(locFormat("逾期进度: %lld 项", Int64(overdueTasks.count)))
            lines.append(locFormat("应收/应付提醒: %lld 笔", Int64(dueReminders.count)))
            lines.append(locFormat("缺票账目: %lld 笔", Int64(missingReceipts.count)))
        }
        if !dueReminders.isEmpty {
            lines.append("")
            lines.append(loc("五、应收/应付提醒"))
            lines += dueReminders.sorted(by: { $0.dueDate < $1.dueDate }).prefix(12).map {
                "- \($0.dueDate)  \($0.normalizedDirection.displayName) \(money(number($0.amount)))  \($0.counterparty)  \($0.normalizedReminderStatus.displayName)"
            }
        }
        if !openTodos.isEmpty {
            lines.append("")
            lines.append(loc("六、未完成待办"))
            lines += openTodos.sorted(by: { $0.dueDate < $1.dueDate }).prefix(12).map {
                "- \($0.dueDate)  \($0.title)  \($0.owner)"
            }
        }
        return pdfData(lines: lines)
    }

    static func makeProjectPackagePDF(
        project: Project,
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        logs: [DailyLog],
        tasks: [ProgressTask],
        todos: [SiteTodo],
        drawings: [ProjectDrawing] = [],
        contacts: [ProjectContact] = [],
        financialRecords: [ProjectFinancialRecord] = [],
        documents: [ProjectDocument] = [],
        quickNotes: [QuickNote] = [],
        paidAmountOverride: Double? = nil
    ) -> Data {
        let quoteTotal = quotes.reduce(0) { $0 + quoteGrandTotal($1) }
        let contract = project.contractAmountValue.doubleValue
        let paid = paidAmountOverride ?? project.paidAmountValue.doubleValue
        let materialCost = materials.reduce(0) { $0 + materialLineTotal($1) }
        let laborCost = labor.reduce(0) { $0 + laborLineTotal($1) }
        let totalLaborHours = labor.reduce(0) { $0 + laborHours($1) }
        let progress = tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
        let deliveryHealth = projectDeliveryHealthReport(
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes
        )
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )

        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 36
        let maxWidth = page.width - margin * 2

        let photoItems: [ReportPhotoItem] = logs.flatMap { log in
            let projectName = project.name
            return log.photoAttachments.map { photo in
                ReportPhotoItem(
                    date: log.date,
                    projectName: projectName,
                    tag: photo.tag.displayName,
                    note: photo.note,
                    fileName: photo.fileName
                )
            }
        }

        return renderer.pdfData { context in
            // 1. 封面
            context.beginPage()
            var y: CGFloat = 90
            y = drawPDFText(locFormat("%@ 项目交付包", project.name), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 24), alignment: .center) + 12
            _ = drawPDFText(locFormat("生成时间: %@", Formatters.now()), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12), alignment: .center)
            y = 220
            y = drawPDFText(locFormat("交付健康: %lld/100  %@", Int64(deliveryHealth.score), deliveryHealth.verdictDisplayName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 13))
            if !deliveryHealth.isDeliverable {
                y = drawPDFText(locFormat("待处理: %@", deliveryHealth.failedCheckDisplayText), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            }
            y += 6
            y = drawPDFText(locFormat("项目地址: %@", project.location.isEmpty ? locNotFilled : project.location), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText(locFormat("客户: %@  电话: %@", project.customerName.isEmpty ? locNotFilled : project.customerName, project.customerPhone.isEmpty ? "-" : project.customerPhone), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText(locFormat("负责人: %@", project.managerName.isEmpty ? locNotFilled : project.managerName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText(locFormat("工期: %@ 至 %@", project.startDate.isEmpty ? locNotFilled : project.startDate, project.expectedEndDate.isEmpty ? locNotFilled : project.expectedEndDate), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText(locFormat("合同金额: %@  已收: %@  未收: %@", money(contract), money(paid), money(max(contract - paid, 0))), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText(locFormat("报价合计: %@  材料成本: %@  人工成本: %@", money(quoteTotal), money(materialCost), money(laborCost)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            _ = drawPDFText(locFormat("毛利估算: %@  工时: %@  进度: %lld%%", money(contract - materialCost - laborCost), fmt(totalLaborHours), Int64(progress * 100)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))

            // 2. 目录
            context.beginPage()
            var tocY: CGFloat = 90
            tocY = drawPDFText(loc("目录"), at: CGPoint(x: margin, y: tocY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20))
            let tocItems = [
                loc("1. 项目封面"),
                loc("2. 目录"),
                loc("3. 报价表"),
                loc("4. 日志表"),
                loc("5. 项目财务流水"),
                loc("6. 施工资料清单"),
                loc("7. 票据索引"),
                loc("8. 联系人与随手记"),
                loc("9. 照片页"),
                loc("10. 签字页")
            ]
            for item in tocItems {
                tocY = drawPDFText(item, at: CGPoint(x: margin, y: tocY + 6), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            }
            tocY = drawPDFText(locFormat("附: 材料 %lld 条 · 人工 %lld 条 · 待办 %lld 条 · 图纸 %lld 份", Int64(materials.count), Int64(labor.count), Int64(todos.count), Int64(drawings.count)), at: CGPoint(x: margin, y: tocY + 16), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            _ = drawPDFText(locFormat("交付健康: %lld/100  %@", Int64(deliveryHealth.score), deliveryHealth.verdictDisplayName), at: CGPoint(x: margin, y: tocY + 6), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))

            // 3. 报价表
            let quoteColumns: [(title: String, width: CGFloat)] = [
                (loc("项目"), 140), (loc("版本"), 44), (loc("状态"), 48), (loc("数量"), 44), (loc("单价"), 62), (loc("金额"), 74), (loc("确认日期"), 74), (loc("备注"), 73)
            ]
            var quoteRows = quotes.map { item in
                [
                    item.name,
                    item.versionName,
                    item.status.displayName,
                    "\(item.quantity)\(item.unit)",
                    money(number(item.unitPrice)),
                    money(quoteGrandTotal(item)),
                    item.customerConfirmedDate.isEmpty ? "-" : item.customerConfirmedDate,
                    item.notes
                ]
            }
            if quoteRows.isEmpty {
                quoteRows = [[loc("暂无报价"), "-", "-", "-", "-", "-", "-", "-"]]
            }
            var quoteIndex = 0
            while quoteIndex < quoteRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText(loc("报价表"), at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: quoteColumns, startX: margin, y: tableY + 6, height: 24)
                while quoteIndex < quoteRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: quoteRows[quoteIndex], columns: quoteColumns, startX: margin, y: tableY, height: 24)
                    quoteIndex += 1
                }
                if quoteIndex == quoteRows.count {
                    _ = drawPDFText(locFormat("报价合计: %@", money(quoteTotal)), at: CGPoint(x: margin, y: tableY + 12), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 12))
                }
            }

            // 4. 日志表
            let logColumns: [(title: String, width: CGFloat)] = [
                (loc("日期"), 72), (loc("天气"), 44), (loc("人数"), 44), (loc("施工内容"), 248), (loc("照片数"), 44), (loc("确认人"), 74)
            ]
            var logRows = logs.sorted(by: { $0.date > $1.date }).map { log in
                [
                    log.date,
                    log.weather,
                    log.workers,
                    log.content,
                    "\(log.photoAttachments.count)",
                    log.confirmer.isEmpty ? "-" : log.confirmer
                ]
            }
            if logRows.isEmpty {
                logRows = [[loc("暂无日志"), "-", "-", "-", "-", "-"]]
            }
            var logIndex = 0
            while logIndex < logRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText(loc("日志表"), at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: logColumns, startX: margin, y: tableY + 6, height: 24)
                while logIndex < logRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: logRows[logIndex], columns: logColumns, startX: margin, y: tableY, height: 24)
                    logIndex += 1
                }
            }

            // 5. 项目财务流水
            let financeColumns: [(title: String, width: CGFloat)] = [
                (loc("日期"), 76), (loc("收支"), 40), (loc("分类"), 52), (loc("状态"), 48), (loc("金额"), 68), (loc("对方"), 96), (loc("票号"), 82), (loc("票据"), 40), (loc("备注"), 83)
            ]
            var financeRows = financialRecords.sorted(by: { $0.date > $1.date }).map { row in
                [
                    row.date,
                    row.direction.displayName,
                    row.category.displayName,
                    row.normalizedStatus.displayName,
                    money(number(row.amount)),
                    row.counterparty,
                    row.invoiceNumber,
                    "\(row.linkedDocumentIds.count)",
                    row.note
                ]
            }
            if financeRows.isEmpty {
                financeRows = [[loc("暂无财务记录"), "-", "-", "-", "-", "-", "-", "-", "-"]]
            }
            var financeIndex = 0
            while financeIndex < financeRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText(loc("项目财务流水"), at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: financeColumns, startX: margin, y: tableY + 6, height: 24)
                while financeIndex < financeRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: financeRows[financeIndex], columns: financeColumns, startX: margin, y: tableY, height: 24)
                    financeIndex += 1
                }
            }

            // 6. 施工资料清单
            context.beginPage()
            var checklistY: CGFloat = 48
            checklistY = drawPDFText(loc("施工资料清单"), at: CGPoint(x: margin, y: checklistY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
            checklistY = drawPDFText(
                locFormat(
                    "覆盖 %lld/%lld 类 · 缺项 %lld · 待处理 %lld · 已归档 %lld",
                    Int64(documentChecklist.coveredCount),
                    Int64(documentChecklist.requiredCount),
                    Int64(documentChecklist.missingCount),
                    Int64(documentChecklist.actionCount),
                    Int64(documentChecklist.archivedDocumentCount)
                ),
                at: CGPoint(x: margin, y: checklistY + 4),
                maxWidth: maxWidth,
                font: UIFont.systemFont(ofSize: 11)
            )
            let checklistColumns: [(title: String, width: CGFloat)] = [
                (loc("类别"), 92), (loc("状态"), 58), (loc("资料数"), 48), (loc("待处理"), 52), (loc("退回"), 44), (loc("已归档"), 52), (loc("说明"), 168)
            ]
            checklistY = drawPDFTableHeader(columns: checklistColumns, startX: margin, y: checklistY + 8, height: 24)
            for item in documentChecklist.items {
                checklistY = drawPDFTableRow(
                    values: [
                        item.category.displayName,
                        item.statusText,
                        "\(item.documentCount)",
                        "\(item.actionCount)",
                        "\(item.returnedCount)",
                        "\(item.archivedCount)",
                        item.detailText
                    ],
                    columns: checklistColumns,
                    startX: margin,
                    y: checklistY,
                    height: 24
                )
            }

            // 7. 票据索引与附件页
            let docColumns: [(title: String, width: CGFloat)] = [
                (loc("名称"), 142), (loc("类型"), 78), (loc("状态"), 62), (loc("责任人"), 62), (loc("形成日期"), 82), (loc("归档编号"), 88)
            ]
            var docRows = documents.sorted(by: { $0.createdAt > $1.createdAt }).map { doc in
                [
                    doc.title,
                    doc.category.displayName,
                    doc.submissionStatus.displayName,
                    doc.responsiblePerson,
                    doc.formedAt.isEmpty ? doc.createdAt : doc.formedAt,
                    doc.archiveNumber
                ]
            }
            if docRows.isEmpty {
                docRows = [[loc("暂无票据资料"), "-", "-", "-", "-", "-"]]
            }
            var docIndex = 0
            while docIndex < docRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText(loc("票据索引"), at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: docColumns, startX: margin, y: tableY + 6, height: 24)
                while docIndex < docRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: docRows[docIndex], columns: docColumns, startX: margin, y: tableY, height: 24)
                    docIndex += 1
                }
            }

            if !documents.isEmpty {
                context.beginPage()
                var y: CGFloat = 48
                y = drawPDFText(loc("票据附件页"), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                _ = drawPDFText(locFormat("本交付包包含 %lld 份票据/资料索引，原始文件已随 ZIP 打包，可在“%@”目录查看。", Int64(documents.count), ProjectPackageSchema.documentDirectory), at: CGPoint(x: margin, y: y + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            }

            // 7. 联系人与随手记
            context.beginPage()
            var contactY: CGFloat = 48
            contactY = drawPDFText(loc("联系人"), at: CGPoint(x: margin, y: contactY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
            if contacts.isEmpty {
                contactY = drawPDFText(loc("暂无联系人"), at: CGPoint(x: margin, y: contactY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            } else {
                for contact in contacts.prefix(18) {
                    let line = "\(contact.name)  \(contact.roleDisplayName)  \(contact.company)  \(contact.phone)"
                    contactY = drawPDFText(line, at: CGPoint(x: margin, y: contactY + 6), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
                }
            }
            contactY = drawPDFText(loc("随手记"), at: CGPoint(x: margin, y: contactY + 20), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
            if quickNotes.isEmpty {
                _ = drawPDFText(loc("暂无随手记"), at: CGPoint(x: margin, y: contactY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            } else {
                var noteY = contactY
                for note in quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).prefix(14) {
                    if noteY > page.height - 88 {
                        context.beginPage()
                        noteY = 48
                    }
                    let content = QuickNoteText.displayContent(for: note)
                    let attachmentText = QuickNoteText.attachmentSummary(note.attachments)
                    let line = "\(note.createdAt)  \(content)\(attachmentText.isEmpty ? "" : locFormat("  附件: %@", attachmentText))"
                    noteY = drawPDFText(line, at: CGPoint(x: margin, y: noteY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
                }
            }

            // 8. 照片页
            drawPhotoWallPages(
                title: locFormat("%@-照片页", project.name),
                items: photoItems,
                context: context,
                page: page,
                margin: margin
            )

            // 9. 签字页
            context.beginPage()
            var signY: CGFloat = 120
            signY = drawPDFText(loc("签字确认页"), at: CGPoint(x: margin, y: signY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20), alignment: .center) + 28
            signY = drawPDFText(locFormat("项目名称: %@", project.name), at: CGPoint(x: margin, y: signY), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText(loc("客户确认: ____________________"), at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText(loc("项目负责人: ____________________"), at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText(loc("监理/验收: ____________________"), at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            _ = drawPDFText(loc("日期: ____________________"), at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
        }
    }

    static func makeProjectPackageZIP(
        project: Project,
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        logs: [DailyLog],
        tasks: [ProgressTask],
        todos: [SiteTodo],
        drawings: [ProjectDrawing] = [],
        contacts: [ProjectContact] = [],
        financialRecords: [ProjectFinancialRecord] = [],
        documents: [ProjectDocument] = [],
        quickNotes: [QuickNote] = [],
        paidAmountOverride: Double? = nil,
        progress: ((ProjectPackageExportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> URL {
        let totalSteps = estimatedProjectPackageStepCount(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes,
            contacts: contacts
        )
        var completedSteps = 0
        func failIfCancelled() throws {
            if shouldCancel?() == true || Task.isCancelled {
                throw ProjectPackageArchiveError.cancelled
            }
        }
        func reportProgress(_ item: String) {
            completedSteps += 1
            progress?(ProjectPackageExportProgress(completedSteps: completedSteps, totalSteps: totalSteps, currentItem: item))
        }

        try failIfCancelled()
        let packagePDF = makeProjectPackagePDF(
            project: project,
            materials: materials,
            quotes: quotes,
            labor: labor,
            logs: logs,
            tasks: tasks,
            todos: todos,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            quickNotes: quickNotes,
            paidAmountOverride: paidAmountOverride
        )

        let packageURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "project-package")
        var zip = try StreamingZipArchiveWriter(fileURL: packageURL)
        var writerFinished = false
        defer {
            if !writerFinished {
                do {
                    try zip.close()
                } catch {
                    StorageIssueLog.record(locFormat("项目交付包 ZIP 关闭失败：%@，%@", packageURL.lastPathComponent, error.localizedDescription))
                }
                do {
                    _ = try FileOps.removeIfExists(
                        at: packageURL,
                        context: .init(
                            event: "project_package.cleanup_temporary_zip",
                            category: .zipArchive,
                            source: "ReportBuilder.exportProjectPackage"
                        )
                    )
                } catch {
                    StorageIssueLog.record(locFormat("项目交付包临时文件清理失败：%@，%@", packageURL.lastPathComponent, error.localizedDescription))
                }
            }
        }

        let folder = safeZipName(project.name, fallback: "untitled_project")
        let deliveryDirectory = ProjectPackageSchema.deliveryDirectory
        let documentDirectory = ProjectPackageSchema.documentDirectory
        let drawingDirectory = ProjectPackageSchema.drawingDirectory
        let photoDirectory = ProjectPackageSchema.photoDirectory
        let quickNoteDirectory = ProjectPackageSchema.quickNoteDirectory
        let contactDirectory = ProjectPackageSchema.contactDirectory
        let pdfName = ProjectPackageSchema.pdfFileName(folder: folder)
        let checklistFileName = ProjectPackageSchema.checklistFileName
        let deliveryHealth = projectDeliveryHealthReport(
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes
        )
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let currentDrawings = currentProjectPackageDrawings(drawings)
        let missingDrawingOriginalEntries = projectPackageMissingDrawingEntries(drawings)
        let openDrawingIssues = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos)
        var stagedRawBytes = 0
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: packagePDF,
            path: "\(folder)/\(deliveryDirectory)/\(pdfName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入交付包 PDF"))

        let readme = [
            tsv(["schema_version", ProjectPackageSchema.version]),
            tsv(["package_type", ProjectPackageSchema.type]),
            tsv(["project_name", project.name]),
            tsv(["exported_at", Formatters.now()]),
            tsv(["delivery_health_score", "\(deliveryHealth.score)"]),
            tsv(["delivery_health_verdict", deliveryHealth.machineVerdict]),
            tsv(["delivery_health_verdict_display", deliveryHealth.verdictDisplayName]),
            tsv(["delivery_health_failed_checks", deliveryHealth.failedCheckKeys]),
            tsv(["delivery_health_failed_checks_display", deliveryHealth.failedCheckDisplayText]),
            tsv(["delivery_health_missing_receipts", "\(deliveryHealth.missingReceiptCount)"]),
            tsv(["delivery_health_drawing_count", "\(deliveryHealth.drawingCount)"]),
            tsv(["delivery_health_open_todos", "\(deliveryHealth.openTodoCount)"]),
            tsv(["delivery_health_backup_fresh", deliveryHealth.backupState.isFresh ? "true" : "false"]),
            tsv(["delivery_health_latest_backup_at", deliveryHealth.backupState.latestBackupExportValue]),
            tsv(["delivery_health_missing_originals", "\(deliveryHealth.missingOriginalEntries.count)"]),
            tsv(["drawing_register_current_count", "\(currentDrawings.count)"]),
            tsv(["drawing_original_count", "\(drawings.count)"]),
            tsv(["drawing_missing_original_count", "\(missingDrawingOriginalEntries.count)"]),
            tsv(["drawing_open_issue_count", "\(openDrawingIssues.count)"]),
            tsv(["document_checklist_required_categories", "\(documentChecklist.requiredCount)"]),
            tsv(["document_checklist_covered_categories", "\(documentChecklist.coveredCount)"]),
            tsv(["document_checklist_missing_categories", "\(documentChecklist.missingCount)"]),
            tsv(["document_checklist_action_count", "\(documentChecklist.actionCount)"]),
            tsv(["document_checklist_returned_count", "\(documentChecklist.returnedDocumentCount)"]),
            tsv(["document_checklist_archived_count", "\(documentChecklist.archivedDocumentCount)"]),
            "",
            "[contents]",
            tsv(["path", "kind_raw", "kind_display"]),
            tsv(["\(deliveryDirectory)/\(pdfName)", "project_delivery_pdf", loc("项目交付包 PDF")]),
            tsv(["\(deliveryDirectory)/\(checklistFileName)", "delivery_checklist", loc("交付检查清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)", "document_checklist", loc("施工资料清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)", "current_drawing_register", loc("当前版图纸清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)", "drawing_missing_check", loc("缺失图纸检查")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)", "open_drawing_issues", loc("未关闭图纸问题")]),
            tsv(["\(documentDirectory)/", "source_documents", loc("票据/资料原始文件")]),
            tsv(["\(drawingDirectory)/", "source_drawings", loc("图纸原始文件")]),
            tsv(["\(photoDirectory)/", "source_site_photos", loc("日志和整改照片文件")]),
            tsv(["\(quickNoteDirectory)/", "quick_notes", loc("随手记清单和原始附件")]),
            tsv(["\(contactDirectory)/", "contacts", loc("联系人清单")])
        ].joined(separator: "\n")
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(readme.utf8),
            path: "\(folder)/\(ProjectPackageSchema.readmeFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入说明文件"))

        let checklist = projectDeliveryChecklistText(
            project: project,
            logs: logs,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            todos: todos,
            quickNotes: quickNotes
        )
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(checklist.utf8),
            path: "\(folder)/\(deliveryDirectory)/\(checklistFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入交付检查清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectDocumentChecklistTSVText(documentChecklist).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入施工资料清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectCurrentDrawingRegisterTSVText(drawings).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入当前版图纸清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectDrawingMissingCheckTSVText(drawings).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入缺失图纸检查"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectOpenDrawingIssuesTSVText(drawings: drawings, todos: todos).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入未关闭图纸问题"))

        for document in documents {
            try failIfCancelled()
            let fileBytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            let sourceURL = ProjectDocumentStorage.fileURL(for: document.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                StorageIssueLog.record(locFormat("项目交付包缺少票据原件：%@", document.fileName))
                reportProgress(locFormat("检查票据 %@", document.title))
                continue
            }
            let title = safeZipName(document.title)
            let fileName = document.fileName.lowercased().hasSuffix(".pdf") ? document.fileName : "\(document.fileName).pdf"
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/\(documentDirectory)/\(title)-\(fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(locFormat("打包票据 %@", document.title))
        }

        for drawing in drawings {
            try failIfCancelled()
            let fileBytes = DrawingStorage.fileSize(for: drawing.fileName)
            let sourceURL = DrawingStorage.fileURL(for: drawing.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                StorageIssueLog.record(locFormat("项目交付包缺少图纸原件：%@", drawing.fileName))
                reportProgress(locFormat("检查图纸 %@", drawing.name))
                continue
            }
            let name = safeZipName(drawing.name)
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/\(drawingDirectory)/\(name)-\(drawing.fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(locFormat("打包图纸 %@", drawing.name))
        }

        for log in logs {
            for photo in log.photoAttachments {
                try failIfCancelled()
                let fileBytes = PhotoStorage.fileSize(for: photo.fileName)
                let sourceURL = PhotoStorage.fileURL(for: photo.fileName)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    StorageIssueLog.record(locFormat("项目交付包缺少现场照片原件：%@", photo.fileName))
                    reportProgress(locFormat("检查照片 %@ %@", log.date, photo.tag.displayName))
                    continue
                }
                let tag = safeZipName(photo.tag.displayName)
                try addStoredFileToProjectPackageZip(
                    zip: &zip,
                    sourceFileURL: sourceURL,
                    fileBytes: fileBytes,
                    path: "\(folder)/\(photoDirectory)/\(log.date)-\(tag)-\(photo.fileName)",
                    stagedRawBytes: &stagedRawBytes
                )
                reportProgress(locFormat("打包照片 %@ %@", log.date, photo.tag.displayName))
            }
        }

        if !quickNotes.isEmpty {
            let header = tsv(["created_at", "content", "attachment_summary_raw", "attachment_summary_display"])
            let lines = quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).map { note in
                let content = QuickNoteText.displayContent(for: note)
                let attachmentSummary = quickNoteAttachmentSummaryColumns(note.attachments)
                return tsv([note.createdAt, content, attachmentSummary.raw, attachmentSummary.display])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + lines).joined(separator: "\n").utf8),
                path: "\(folder)/\(quickNoteDirectory)/\(ProjectPackageSchema.quickNotesFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(loc("写入随手记清单"))
            for note in quickNotes {
                for attachment in note.attachments {
                    try failIfCancelled()
                    let fileBytes = QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
                    let sourceURL = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        StorageIssueLog.record(locFormat("项目交付包缺少随手记附件原件：%@", attachment.fileName))
                        reportProgress(locFormat("检查随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
                        continue
                    }
                    let title = safeZipName(note.title, fallback: "quick_note")
                    let kind = attachment.attachmentKind.rawValue
                    let created = safeZipName(note.createdAt)
                    try addStoredFileToProjectPackageZip(
                        zip: &zip,
                        sourceFileURL: sourceURL,
                        fileBytes: fileBytes,
                        path: "\(folder)/\(quickNoteDirectory)/\(kind)/\(created)-\(title)-\(attachment.fileName)",
                        stagedRawBytes: &stagedRawBytes
                    )
                    reportProgress(locFormat("打包随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
                }
            }
        }

        if !contacts.isEmpty {
            let header = tsv(["name", "role_key", "role_display", "company", "phone", "note"])
            let rows = contacts.sorted { $0.name < $1.name }.map {
                tsv([$0.name, $0.normalizedRole.exportKey, $0.roleDisplayName, $0.company, $0.phone, $0.note])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + rows).joined(separator: "\n").utf8),
                path: "\(folder)/\(contactDirectory)/\(ProjectPackageSchema.contactsFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(loc("写入联系人清单"))
        }

        let finishedURL = try zip.finish()
        writerFinished = true
        return finishedURL
    }

    private static func projectDeliveryChecklistText(
        project: Project,
        logs: [DailyLog],
        drawings: [ProjectDrawing],
        contacts: [ProjectContact],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        todos: [SiteTodo],
        quickNotes: [QuickNote]
    ) -> String {
        let logExpectation = projectDeliveryLogExpectation(project: project, logs: logs)
        let drawingsWithoutCurrent = projectDrawingGroupsWithoutCurrentVersion(drawings)
        let currentDrawings = currentProjectPackageDrawings(drawings)
        let missingDrawingOriginalEntries = projectPackageMissingDrawingEntries(drawings)
        let openDrawingIssues = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos)
        let missingReceipts = projectFinancialRecordsMissingReceipts(
            financialRecords: financialRecords,
            documents: documents
        )
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let unsettledRecords = financialRecords.filter { record in
            record.normalizedStatus == .active
                && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let unsettledAmount = unsettledRecords
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
        let deliveryHealth = projectDeliveryHealthReport(
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes
        )
        let advisoryWarningCount = [
            !logExpectation.missingDates.isEmpty,
            !drawingsWithoutCurrent.isEmpty,
            !openDrawingIssues.isEmpty,
            contacts.isEmpty,
            !unsettledRecords.isEmpty,
            documentChecklist.hasAttention
        ].filter { $0 }.count

        var lines: [String] = [
            loc("交付前检查清单"),
            locFormat("项目: %@", project.name),
            locFormat("生成时间: %@", Formatters.now()),
            locFormat("检查结论: %@", deliveryHealth.verdictDisplayName),
            locFormat("交付健康分: %lld/100", Int64(deliveryHealth.score)),
            locFormat("未通过项: %@", deliveryHealth.failedCheckDisplayText),
            advisoryWarningCount == 0 ? loc("建议检查: 无") : locFormat("建议检查: %lld 项", Int64(advisoryWarningCount)),
            "",
            loc("核心交付健康"),
            locFormat("   - 缺票据: %lld 笔", Int64(deliveryHealth.missingReceiptCount)),
            locFormat("   - 图纸: %lld 份", Int64(deliveryHealth.drawingCount)),
            locFormat("   - 未完成待办: %lld 项", Int64(deliveryHealth.openTodoCount)),
            locFormat("   - 备份状态: %@", deliveryHealth.backupState.detail),
            locFormat("   - 缺失原件: %lld 项", Int64(deliveryHealth.missingOriginalEntries.count)),
            "",
            loc("1. 施工日志"),
            locFormat("   - 已记录: %lld 条", Int64(logs.count))
        ]
        if !deliveryHealth.missingOriginalEntries.isEmpty {
            lines.append(locFormat("   - 缺失原件示例: %@", deliveryHealth.missingOriginalEntries.prefix(10).joined(separator: loc("、"))))
        }

        if logExpectation.expectedCount > 0 {
            lines.append(locFormat("   - 应覆盖施工日: %lld 天", Int64(logExpectation.expectedCount)))
            if logExpectation.missingDates.isEmpty {
                lines.append(loc("   - 结果: 已覆盖"))
            } else {
                lines.append(locFormat("   - 结果: 缺 %lld 天", Int64(logExpectation.missingDates.count)))
                lines.append(locFormat("   - 缺失日期: %@", logExpectation.missingDates.prefix(20).joined(separator: loc("、"))))
            }
        } else if logs.isEmpty {
            lines.append(loc("   - 结果: 未设置开工日期，且未记录施工日志"))
        } else {
            lines.append(loc("   - 结果: 未设置完整工期，按现有日志交付"))
        }

        lines += [
            "",
            loc("2. 图纸当前版"),
            locFormat("   - 图纸数量: %lld 份", Int64(drawings.count)),
            locFormat("   - 当前版图纸: %lld 份", Int64(currentDrawings.count)),
            locFormat("   - 图纸原件: %lld 份", Int64(drawings.count)),
            locFormat("   - 缺失图纸原件: %lld 项", Int64(missingDrawingOriginalEntries.count))
        ]
        if drawings.isEmpty {
            lines.append(loc("   - 结果: 未上传图纸"))
        } else if drawingsWithoutCurrent.isEmpty {
            lines.append(loc("   - 结果: 所有图纸组均有当前版"))
        } else {
            lines.append(locFormat("   - 结果: %lld 组图纸未标记当前版", Int64(drawingsWithoutCurrent.count)))
            lines.append(locFormat("   - 图纸组: %@", drawingsWithoutCurrent.prefix(20).joined(separator: loc("、"))))
        }
        if !missingDrawingOriginalEntries.isEmpty {
            lines.append(locFormat("   - 缺失图纸: %@", missingDrawingOriginalEntries.prefix(20).joined(separator: loc("、"))))
        }

        lines += [
            "",
            loc("3. 缺票检查"),
            locFormat("   - 需票据账目: %lld 笔", Int64(financialRecords.filter(\.requiresAttachment).count)),
            missingReceipts.isEmpty ? loc("   - 结果: 全部已关联票据/资料") : locFormat("   - 结果: 还有 %lld 笔缺票", Int64(missingReceipts.count))
        ]

        lines += [
            "",
            loc("4. 施工资料清单"),
            locFormat("   - 覆盖: %lld/%lld 类", Int64(documentChecklist.coveredCount), Int64(documentChecklist.requiredCount)),
            locFormat("   - 缺项: %lld 类", Int64(documentChecklist.missingCount)),
            locFormat("   - 待处理: %lld 份", Int64(documentChecklist.actionCount)),
            locFormat("   - 退回修改: %lld 份", Int64(documentChecklist.returnedDocumentCount)),
            locFormat("   - 已归档: %lld 份", Int64(documentChecklist.archivedDocumentCount))
        ]
        lines += documentChecklist.items.map {
            "   - \($0.category.displayName): \($0.statusText) · \($0.detailText)"
        }

        lines += [
            "",
            loc("5. 未关闭图纸问题"),
            locFormat("   - 未关闭问题: %lld 项", Int64(openDrawingIssues.count)),
            openDrawingIssues.isEmpty ? loc("   - 结果: 无未关闭图纸问题") : loc("   - 结果: 仍有图纸问题未关闭")
        ]
        lines += openDrawingIssues.prefix(20).map { issue in
            "   - \(drawingDisplayName(issue.drawing)) \(issue.drawing.version): \(issue.summary)"
        }

        lines += [
            "",
            loc("6. 联系人"),
            locFormat("   - 联系人数量: %lld 位", Int64(contacts.count)),
            contacts.isEmpty ? loc("   - 结果: 缺少项目联系人") : loc("   - 结果: 已维护联系人")
        ]

        lines += [
            "",
            loc("7. 未结清账目"),
            locFormat("   - 未结清笔数: %lld 笔", Int64(unsettledRecords.count)),
            locFormat("   - 未结清金额: %@", money(unsettledAmount)),
            unsettledRecords.isEmpty ? loc("   - 结果: 无未结清账目") : loc("   - 结果: 仍有未结清账目，建议交付前确认")
        ]

        lines += [
            "",
            loc("说明: 该清单由交付包导出时自动生成，供完工交付前核对使用。")
        ]
        return lines.joined(separator: "\n")
    }

    private static func projectDeliveryHealthReport(
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> ProjectDeliveryPackageHealthReport {
        ProjectDeliveryPackageHealthReport(
            missingReceiptCount: projectFinancialRecordsMissingReceipts(
                financialRecords: financialRecords,
                documents: documents
            ).count,
            drawingCount: drawings.count,
            openTodoCount: todos.filter { !$0.isDone }.count,
            backupState: .current(),
            missingOriginalEntries: projectPackageMissingOriginalEntries(
                documents: documents,
                drawings: drawings,
                logs: logs,
                quickNotes: quickNotes
            )
        )
    }

    private static func projectFinancialRecordsMissingReceipts(
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument]
    ) -> [ProjectFinancialRecord] {
        financialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = documents.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }
    }

    private static func projectPackageMissingOriginalEntries(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> [String] {
        var entries: [String] = []
        entries += documents.compactMap { document in
            ProjectDocumentStorage.exists(fileName: document.fileName) ? nil : locFormat("资料 %@", document.title)
        }
        entries += drawings.compactMap { drawing in
            DrawingStorage.exists(fileName: drawing.fileName) ? nil : locFormat("图纸 %@", drawing.name)
        }
        for log in logs {
            for photo in log.photoAttachments where !PhotoStorage.exists(fileName: photo.fileName) {
                entries.append(locFormat("照片 %@ %@", log.date, photo.tag.displayName))
            }
        }
        for note in quickNotes {
            for attachment in note.attachments where !QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
                entries.append(locFormat("随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
            }
        }
        return entries
    }

    private static func projectDeliveryLogExpectation(project: Project, logs: [DailyLog]) -> (expectedCount: Int, missingDates: [String]) {
        guard let start = Formatters.date.date(from: project.startDate) else {
            return (0, [])
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let configuredEnd = Formatters.date.date(from: project.expectedEndDate) ?? today
        let effectiveEnd = min(calendar.startOfDay(for: configuredEnd), today)
        var cursor = calendar.startOfDay(for: start)
        guard cursor <= effectiveEnd else {
            return (0, [])
        }

        let loggedDates = Set(logs.compactMap { normalizedReportDateKey($0.date) })
        var expectedDates: [String] = []
        while cursor <= effectiveEnd {
            expectedDates.append(Formatters.date.string(from: cursor))
            guard expectedDates.count < 370 else { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return (expectedDates.count, expectedDates.filter { !loggedDates.contains($0) })
    }

    private static func normalizedReportDateKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = Formatters.parseDateOrDateTime(trimmed) {
            return Formatters.date.string(from: date)
        }
        return trimmed
    }

    private static func projectDrawingGroupsWithoutCurrentVersion(_ drawings: [ProjectDrawing]) -> [String] {
        guard !drawings.isEmpty else { return [] }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let key = normalizedProjectDrawingFamilyKey(drawing.name)
            return key.isEmpty ? drawing.fileName : key
        }
        return grouped.values.compactMap { group in
            guard !group.contains(where: \.isCurrentVersion) else { return nil }
            let sorted = group.sorted { lhs, rhs in
                if lhs.importedAt == rhs.importedAt {
                    return lhs.fileName < rhs.fileName
                }
                return lhs.importedAt > rhs.importedAt
            }
            guard let drawing = sorted.first else { return nil }
            let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? drawing.fileName : name
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func currentProjectPackageDrawings(_ drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        projectPackageSortedDrawings(drawings.filter(\.isCurrentVersion))
    }

    private static func projectPackageSortedDrawings(_ drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        drawings.sorted { lhs, rhs in
            let lhsKey = [
                lhs.discipline,
                lhs.floorArea,
                lhs.drawingNumber,
                drawingDisplayName(lhs),
                lhs.version,
                lhs.fileName
            ].joined(separator: "\u{1F}")
            let rhsKey = [
                rhs.discipline,
                rhs.floorArea,
                rhs.drawingNumber,
                drawingDisplayName(rhs),
                rhs.version,
                rhs.fileName
            ].joined(separator: "\u{1F}")
            return lhsKey.localizedStandardCompare(rhsKey) == .orderedAscending
        }
    }

    private static func projectPackageMissingDrawingEntries(_ drawings: [ProjectDrawing]) -> [String] {
        projectPackageSortedDrawings(drawings).compactMap { drawing in
            DrawingStorage.exists(fileName: drawing.fileName) ? nil : drawingDisplayName(drawing)
        }
    }

    private static func projectPackageOpenDrawingIssueRows(
        drawings: [ProjectDrawing],
        todos: [SiteTodo]
    ) -> [ProjectDrawingOpenIssueRow] {
        let todosByID = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        return projectPackageSortedDrawings(drawings).compactMap { drawing in
            let openTodos = drawing.linkedTodoIDs.compactMap { todosByID[$0] }.filter { !$0.isDone }
            let hasOpenDrawingStatus = drawing.issueStatus == .open
                || drawing.issueStatus == .inProgress
                || (drawing.issueStatus != .closed && !drawing.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            guard hasOpenDrawingStatus || !openTodos.isEmpty else { return nil }
            return ProjectDrawingOpenIssueRow(drawing: drawing, openTodos: openTodos)
        }
    }

    private static func drawingDisplayName(_ drawing: ProjectDrawing) -> String {
        let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? drawing.fileName : name
    }

    private static func drawingIssueStatusKey(_ status: DrawingIssueStatus) -> String {
        switch status {
        case .none: "none"
        case .open: "open"
        case .inProgress: "in_progress"
        case .closed: "closed"
        }
    }

    private static func normalizedProjectDrawingFamilyKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[\\s_\\-]+", with: "", options: .regularExpression)
    }

    private static func addGeneratedFileToProjectPackageZip(
        zip: inout StreamingZipArchiveWriter,
        data: Data,
        path: String,
        stagedRawBytes: inout Int
    ) throws {
        do {
            try zip.addFile(path: path, data: data)
        } catch {
            StorageIssueLog.record(locFormat("项目交付包写入生成文件失败：%@，%@", path, error.localizedDescription))
            throw error
        }
        stagedRawBytes += data.count
    }

    private static func addStoredFileToProjectPackageZip(
        zip: inout StreamingZipArchiveWriter,
        sourceFileURL: URL,
        fileBytes: Int,
        path: String,
        stagedRawBytes: inout Int
    ) throws {
        let resolvedFileBytes = max(fileBytes, QuickNoteAttachmentStorage.fileSize(at: sourceFileURL))
        do {
            try zip.addFile(path: path, sourceFileURL: sourceFileURL)
        } catch {
            StorageIssueLog.record(locFormat("项目交付包写入原件失败：%@ -> %@，%@", sourceFileURL.lastPathComponent, path, error.localizedDescription))
            throw error
        }
        stagedRawBytes += resolvedFileBytes
    }

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
        let discountRate = item.discountRateValue.ratioFromPercent
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
        let workers = record.workersValue
        let hours = record.hoursValue
        if workers.decimal > 0 {
            return (workers * hours).doubleValue
        }
        return hours.doubleValue
    }

    static func laborLineTotal(_ record: LaborRecord) -> Double {
        let hoursValue = MoneyValue(NSDecimalNumber(value: laborHours(record)).decimalValue)
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

    private static func safeZipName(_ raw: String, fallback: String = "untitled") -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        let compact = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? fallback : compact
    }

    private static func tsv(_ values: [String]) -> String {
        values.map(tsvField).joined(separator: "\t")
    }

    private static func tsvField(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func quickNoteAttachmentSummaryColumns(
        _ attachments: [QuickNoteAttachment]
    ) -> (raw: String, display: String) {
        let grouped = Dictionary(grouping: attachments, by: \.attachmentKind)
        let raw = QuickNoteAttachmentKind
            .allCases
            .compactMap { kind -> String? in
                let count = grouped[kind]?.count ?? 0
                guard count > 0 else { return nil }
                return "\(kind.rawValue):\(count)"
            }
            .joined(separator: ",")
        return (raw, QuickNoteText.attachmentSummary(attachments))
    }

    private static func projectDocumentChecklistTSVText(_ checklist: DocumentArchiveChecklistSnapshot) -> String {
        let header = tsv([
            "category_key",
            "category_display",
            "status_raw",
            "status_display",
            "document_count",
            "action_count",
            "returned_count",
            "archived_count"
        ])
        let rows = checklist.items.map { item in
            tsv([
                item.category.exportKey,
                item.category.displayName,
                item.statusExportKey,
                item.statusText,
                "\(item.documentCount)",
                "\(item.actionCount)",
                "\(item.returnedCount)",
                "\(item.archivedCount)"
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func projectCurrentDrawingRegisterTSVText(_ drawings: [ProjectDrawing]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "issued_at",
            "receiver",
            "file_type",
            "file_name",
            "file_exists",
            "issue_status_raw",
            "issue_status_display",
            "linked_todo_count",
            "linked_log_count",
            "linked_document_count",
            "imported_at",
            "note"
        ])
        let rows = currentProjectPackageDrawings(drawings).map { drawing in
            tsv([
                drawing.id.uuidString,
                drawing.drawingNumber,
                drawingDisplayName(drawing),
                drawing.discipline,
                drawing.floorArea,
                drawing.version,
                drawing.issuedAt,
                drawing.receiver,
                drawing.fileType,
                drawing.fileName,
                DrawingStorage.exists(fileName: drawing.fileName) ? "true" : "false",
                drawingIssueStatusKey(drawing.issueStatus),
                drawing.issueStatus.displayName,
                "\(drawing.linkedTodoIDs.count)",
                "\(drawing.linkedLogIDs.count)",
                "\(drawing.linkedDocumentIDs.count)",
                drawing.importedAt,
                drawing.note
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func projectDrawingMissingCheckTSVText(_ drawings: [ProjectDrawing]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "is_current",
            "file_type",
            "file_name",
            "file_exists",
            "status_raw",
            "status_display",
            "imported_at"
        ])
        let rows = projectPackageSortedDrawings(drawings).map { drawing in
            let exists = DrawingStorage.exists(fileName: drawing.fileName)
            return tsv([
                drawing.id.uuidString,
                drawing.drawingNumber,
                drawingDisplayName(drawing),
                drawing.discipline,
                drawing.floorArea,
                drawing.version,
                drawing.isCurrentVersion ? "true" : "false",
                drawing.fileType,
                drawing.fileName,
                exists ? "true" : "false",
                exists ? "present" : "missing",
                exists ? loc("原件存在") : loc("原件缺失"),
                drawing.importedAt
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func projectOpenDrawingIssuesTSVText(drawings: [ProjectDrawing], todos: [SiteTodo]) -> String {
        let header = tsv([
            "drawing_id",
            "drawing_number",
            "name",
            "discipline",
            "floor_area",
            "version",
            "issue_status_raw",
            "issue_status_display",
            "issue_note",
            "open_todo_count",
            "open_todo_titles",
            "owners",
            "due_dates",
            "linked_todo_ids",
            "file_name"
        ])
        let rows = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos).map { issue in
            tsv([
                issue.drawing.id.uuidString,
                issue.drawing.drawingNumber,
                drawingDisplayName(issue.drawing),
                issue.drawing.discipline,
                issue.drawing.floorArea,
                issue.drawing.version,
                drawingIssueStatusKey(issue.drawing.issueStatus),
                issue.drawing.issueStatus == .none ? loc("关联待办未关闭") : issue.drawing.issueStatus.displayName,
                issue.drawing.issueNote,
                "\(issue.openTodos.count)",
                issue.openTodos.map(\.title).joined(separator: "；"),
                issue.openTodos.map(\.owner).filter { !$0.isEmpty }.joined(separator: "；"),
                issue.openTodos.map(\.dueDate).filter { !$0.isEmpty }.joined(separator: "；"),
                issue.openTodos.map { $0.id.uuidString }.joined(separator: ";"),
                issue.drawing.fileName
            ])
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func estimatedProjectPackageStepCount(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        contacts: [ProjectContact]
    ) -> Int {
        var total = 7 // PDF + README + delivery checklist + document checklist + drawing TSV files
        total += documents.count
        total += drawings.count
        total += logs.reduce(0) { $0 + $1.photoAttachments.count }
        if !quickNotes.isEmpty {
            total += 1 // quick note summary
            total += quickNotes.reduce(0) { $0 + $1.attachments.count }
        }
        if !contacts.isEmpty {
            total += 1
        }
        return max(total, 1)
    }

    private static func drawPhotoWallPages(
        title: String,
        items: [ReportPhotoItem],
        context: UIGraphicsPDFRendererContext,
        page: CGRect,
        margin: CGFloat,
        thumbnailsByFileName: [String: UIImage] = [:]
    ) {
        let colCount = 2
        let rowCount = 3
        let cardGap: CGFloat = 12
        let cardWidth = (page.width - margin * 2 - cardGap) / CGFloat(colCount)
        let cardHeight: CGFloat = 220
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.projectName < rhs.projectName }
            return lhs.date > rhs.date
        }

        var index = 0
        while index < max(sortedItems.count, 1) {
            context.beginPage()
            let maxWidth = page.width - margin * 2
            _ = drawPDFText(title, at: CGPoint(x: margin, y: 32), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 18), alignment: .center)
            _ = drawPDFText(locFormat("生成时间: %@", Formatters.now()), at: CGPoint(x: margin, y: 58), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 10), alignment: .center)
            if sortedItems.isEmpty {
                _ = drawPDFText(loc("暂无照片"), at: CGPoint(x: margin, y: 120), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13), alignment: .center)
                break
            }

            for row in 0..<rowCount {
                for col in 0..<colCount {
                    guard index < sortedItems.count else { continue }
                    let item = sortedItems[index]
                    let x = margin + CGFloat(col) * (cardWidth + cardGap)
                    let y = 90 + CGFloat(row) * (cardHeight + 14)
                    let cardRect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
                    UIBezierPath(roundedRect: cardRect, cornerRadius: 8).stroke()
                    let imageRect = CGRect(x: x + 8, y: y + 8, width: cardWidth - 16, height: 146)
                    if let image = thumbnailsByFileName[item.fileName] ?? PhotoStorage.thumbnail(for: item.fileName) {
                        image.draw(in: imageRect)
                    } else {
                        UIColor.secondarySystemFill.setFill()
                        UIBezierPath(rect: imageRect).fill()
                    }
                    let titleText = "\(item.date) · \(item.projectName)"
                    _ = drawPDFText(titleText, at: CGPoint(x: x + 8, y: y + 160), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText(locFormat("标签: %@", item.tag), at: CGPoint(x: x + 8, y: y + 176), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText(item.note.isEmpty ? loc("备注: -") : locFormat("备注: %@", item.note), at: CGPoint(x: x + 8, y: y + 192), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    index += 1
                }
            }
        }
    }

    private static func preloadPhotoWallThumbnails(for items: [ReportPhotoItem]) async -> [String: UIImage] {
        let fileNames = Array(Set(items.map(\.fileName).filter { !$0.isEmpty }))
        guard !fileNames.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, UIImage?).self) { group in
            for fileName in fileNames {
                group.addTask {
                    (fileName, await PhotoStorage.thumbnailAsync(for: fileName))
                }
            }

            var imagesByFileName: [String: UIImage] = [:]
            for await (fileName, image) in group {
                if let image {
                    imagesByFileName[fileName] = image
                }
            }
            return imagesByFileName
        }
    }

    private static func firstNumber(_ text: String) -> Double {
        number(text)
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

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func resolvedProjectName(items: [QuoteItem], projects: [Project]) -> String {
        let names = Set(items.compactMap { item in
            item.projectId.flatMap { pid in projects.first(where: { $0.id == pid })?.name }
        })
        if names.isEmpty { return loc("未指定") }
        if names.count == 1 { return names.first ?? loc("未指定") }
        return loc("多个项目")
    }

    private static func resolvedSingleProjectAddress(items: [QuoteItem], projects: [Project]) -> String? {
        let ids = Set(items.compactMap(\.projectId))
        guard ids.count == 1, let id = ids.first else { return nil }
        return projects.first(where: { $0.id == id })?.location
    }

    private static func drawPDFText(
        _ text: String,
        at origin: CGPoint,
        maxWidth: CGFloat,
        font: UIFont,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph])
        let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let height = ceil(rect.height)
        attr.draw(with: CGRect(x: origin.x, y: origin.y, width: maxWidth, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return origin.y + max(18, height + 4)
    }

    private static func drawPDFTableHeader(
        columns: [(title: String, width: CGFloat)],
        startX: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        var x = startX
        for column in columns {
            let rect = CGRect(x: x, y: y, width: column.width, height: height)
            UIBezierPath(rect: rect).stroke()
            let attr = NSAttributedString(
                string: column.title,
                attributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.black]
            )
            let textRect = CGRect(x: rect.minX + 4, y: rect.minY + 6, width: rect.width - 8, height: rect.height - 8)
            attr.draw(in: textRect)
            x += column.width
        }
        return y + height
    }

    private static func drawPDFTableRow(
        values: [String],
        columns: [(title: String, width: CGFloat)],
        startX: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        var x = startX
        for (index, column) in columns.enumerated() {
            let rect = CGRect(x: x, y: y, width: column.width, height: height)
            UIBezierPath(rect: rect).stroke()
            let value = values.indices.contains(index) ? values[index] : ""
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attr = NSAttributedString(
                string: value,
                attributes: [.font: UIFont.systemFont(ofSize: 10), .paragraphStyle: paragraph, .foregroundColor: UIColor.black]
            )
            attr.draw(in: CGRect(x: rect.minX + 4, y: rect.minY + 6, width: rect.width - 8, height: rect.height - 8))
            x += column.width
        }
        return y + height
    }

    static func pdfData(lines: [String]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 36
            let margin: CGFloat = 36
            let maxWidth = page.width - margin * 2
            for line in lines {
                if y > page.height - 54 {
                    context.beginPage()
                    y = 36
                }
                let isHeading = isReportLineHeading(line)
                let font = line.isEmpty
                    ? UIFont.systemFont(ofSize: 6)
                    : UIFont.systemFont(ofSize: isHeading ? 15 : 11, weight: isHeading ? .semibold : .regular)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attr = NSAttributedString(string: line, attributes: [.font: font, .paragraphStyle: paragraph])
                let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                attr.draw(with: CGRect(x: margin, y: y, width: maxWidth, height: ceil(rect.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += max(16, ceil(rect.height) + 6)
            }
        }
    }

    private static func isReportLineHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-"), !trimmed.hasPrefix("   -") else { return false }
        if trimmed.count > 36 { return false }
        if trimmed.contains(":") { return false }
        if trimmed.rangeOfCharacter(from: .decimalDigits) == nil { return true }
        return trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") || trimmed.hasPrefix("3.") || trimmed.hasPrefix("4.") || trimmed.hasPrefix("5.")
    }
}
