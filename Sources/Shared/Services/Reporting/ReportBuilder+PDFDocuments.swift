import Foundation
import UIKit

extension ReportBuilder {
    static func makeQuotationPDF(
        title: String,
        items: [QuoteItem],
        projects: [Project]
    ) -> Data {
        let validityDays = max(1, UserPreferencesStore.shared.int(UserPreferenceKeys.quoteValidityDays, default: 15))
        let validUntil = Formatters.date.string(
            from: Calendar.current.date(byAdding: .day, value: validityDays, to: Date()) ?? Date()
        )
        let projectAddress = resolvedSingleProjectAddress(items: items, projects: projects) ?? locNotFilled
        let companyName = UserPreferencesStore.shared.string(UserPreferenceKeys.companyName, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyPhone = UserPreferencesStore.shared.string(UserPreferenceKeys.companyPhone, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyAddress = UserPreferencesStore.shared.string(UserPreferenceKeys.companyAddress, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
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

        let subtotal = items.reduce(MoneyValue.zero) { $0 + quoteLineTotal($1) }
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

            let rows: [[any CustomStringConvertible]] = items.isEmpty ? [[
                loc("暂无明细"), "-", "-", "-", "-", "-", "-", "-"
            ]] : items.map { item in
                [
                    item.name,
                    item.unit,
                    item.quantity,
                    money(item.unitPrice),
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
            y = drawPDFText(locFormat("小计: %@", money(subtotal)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText(locFormat("税额: %@    折扣: -%@", money(tax), money(discount)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText(locFormat("合计: %@", money(total)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 14)) + 18

            _ = drawPDFText(locFormat("签字确认: %@____________________", meta.signerName), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
        }
    }

    static func makePhotoWallPDF(title: String, items: [ReportPhotoItem]) -> Data {
        renderPhotoWallPDF(title: title, items: items, thumbnailsByFileName: [:])
    }

    static func makePhotoWallPDFAsync(title: String, items: [ReportPhotoItem]) async -> Data {
        let thumbnailsByFileName = await preloadPhotoWallThumbnails(for: items)
        return renderPhotoWallPDF(title: title, items: items, thumbnailsByFileName: thumbnailsByFileName)
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
        paidAmountOverride: MoneyValue? = nil
    ) -> Data {
        let contract = project.contractAmount
        let quoteTotal = quotes.reduce(MoneyValue.zero) { $0 + quoteGrandTotal($1) }
        let materialCost = materials.reduce(MoneyValue.zero) { $0 + materialLineTotal($1) }
        let laborCost = labor.reduce(MoneyValue.zero) { $0 + laborLineTotal($1) }
        let financialSummary = ProjectFinancialMetrics.summary(financialRecords)
        let income = financialSummary.income
        let expense = financialSummary.expense
        let paid = paidAmountOverride ?? ProjectFinancialMetrics.paidAmount(project: project, records: financialRecords)
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let progress = tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)
        let photosCount = logs.reduce(0) { $0 + $1.photoAttachments.count }

        var lines: [String] = []
        lines.append(locFormat("%@ 项目归档报告", project.name))
        lines.append(locFormat("生成时间: %@", Formatters.displayNow()))
        lines.append("")
        lines.append(loc("一、项目概况"))
        lines.append(locFormat("地址: %@", project.location.isEmpty ? locNotFilled : project.location))
        lines.append(locFormat("客户: %@  电话: %@", project.customerName.isEmpty ? locNotFilled : project.customerName, project.customerPhone.isEmpty ? "-" : project.customerPhone))
        lines.append(locFormat("负责人: %@", project.managerName.isEmpty ? locNotFilled : project.managerName))
        lines.append(locFormat("状态: %@  工期: %@ 至 %@", project.status.displayName, project.startDate.isEmpty ? "-" : project.startDate.storageText, project.expectedEndDate.isEmpty ? "-" : project.expectedEndDate.storageText))
        lines.append("")
        lines.append(loc("二、经营汇总"))
        lines.append(locFormat("合同金额: %@  已收: %@  未收: %@", money(contract), money(paid), money(ProjectFinancialMetrics.unpaidAmount(contractAmount: contract, paidAmount: paid))))
        lines.append(locFormat("报价合计: %@  材料成本: %@  人工成本: %@", money(quoteTotal), money(materialCost), money(laborCost)))
        lines.append(locFormat("记账收入: %@  记账支出: %@  账面结余: %@", money(income), money(expense), money(income - expense)))
        lines.append(locFormat("毛利估算: %@", money(contract - materialCost - laborCost)))
        lines.append("")
        lines.append(loc("三、资料完整度"))
        lines.append(locFormat("施工日志: %lld 条  现场照片: %lld 张  进度平均: %lld%%", Int64(logs.count), Int64(photosCount), Int64(progress * 100)))
        lines.append(locFormat("材料: %lld 条  预结算: %lld 条  人工: %lld 条  仓库流水: %lld 条", Int64(materials.count), Int64(quotes.count), Int64(labor.count), Int64(warehouseMovements.count)))
        lines.append(locFormat("票据/资料: %lld 份  图纸: %lld 份  联系人: %lld 位  随手记: %lld 条", Int64(documents.count), Int64(drawings.count), Int64(contacts.count), Int64(quickNotes.count)))
        lines.append(locFormat("施工资料清单: 覆盖 %lld/%lld 类  缺项 %lld 类  待处理 %lld 份", Int64(documentChecklist.coveredCount), Int64(documentChecklist.requiredCount), Int64(documentChecklist.missingCount), Int64(documentChecklist.actionCount)))
        lines += projectArchivePendingLines(todos: todos, tasks: tasks, financialRecords: financialRecords, documents: documents)
        return pdfData(lines: lines)
    }

    private static func projectArchivePendingLines(
        todos: [SiteTodo],
        tasks: [ProgressTask],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument]
    ) -> [String] {
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
        var lines = ["", loc("四、归档前待处理")]
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
                "- \($0.dueDate)  \($0.normalizedDirection.displayName) \(money($0.amount))  \($0.counterparty)  \($0.normalizedReminderStatus.displayName)"
            }
        }
        if !openTodos.isEmpty {
            lines.append("")
            lines.append(loc("六、未完成待办"))
            lines += openTodos.sorted(by: { $0.dueDate < $1.dueDate }).prefix(12).map {
                "- \($0.dueDate)  \($0.title)  \($0.owner)"
            }
        }
        return lines
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
}
