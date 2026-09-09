import Foundation
import UIKit

extension ReportBuilder {
    // A single renderer transaction keeps page state and UIGraphicsPDFRenderer lifetime coherent.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
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
        let paid = paidAmountOverride ?? ProjectFinancialMetrics.paidAmount(project: project, records: financialRecords)
        let recordedMaterialCost = materials.reduce(0) { $0 + materialLineTotal($1) }
        let recordedLaborCost = labor.reduce(0) { $0 + laborLineTotal($1) }
        let materialCost = recordedMaterialCost > 0 ? recordedMaterialCost : project.materialCostValue.doubleValue
        let laborCost = recordedLaborCost > 0 ? recordedLaborCost : project.laborCostValue.doubleValue
        let laborWorkload = laborWorkloadSummary(labor)
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
            _ = drawPDFText(locFormat("毛利估算: %@  人工量: %@  进度: %lld%%", money(contract - materialCost - laborCost), laborWorkload.displayText, Int64(progress * 100)), at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))

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
}
