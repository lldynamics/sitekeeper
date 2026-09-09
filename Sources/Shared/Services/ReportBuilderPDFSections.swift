import Foundation

enum ReportBuilderPDFSections {
    static func appendSections(
        snapshot: BackupSnapshot,
        options: ExportContentOptions,
        lines: inout [String]
    ) {
        let currencyDisplayMode = options.currencyDisplayMode
        if options.includeMaterials {
            lines.append(String(localized: "材料清单"))
            lines += snapshot.materialItems.map {
                "- \($0.name)  \($0.quantity) \($0.unit)  单价\(ReportBuilder.money(ReportBuilder.number($0.unitPrice), currencyDisplayMode: currencyDisplayMode))  金额\(ReportBuilder.money(ReportBuilder.materialLineTotal($0), currencyDisplayMode: currencyDisplayMode))"
            }
            lines.append("")
        }
        if options.includeQuotes {
            let total = snapshot.quoteItems.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
            lines.append("\(String(localized: "报价明细"))  合计 \(ReportBuilder.money(total, currencyDisplayMode: currencyDisplayMode))")
            lines += snapshot.quoteItems.map {
                "- \($0.name)  \($0.quantity)\($0.unit)  \(ReportBuilder.money(ReportBuilder.quoteGrandTotal($0), currencyDisplayMode: currencyDisplayMode))"
            }
            lines.append("")
        }
        if options.includeLabor {
            lines.append(String(localized: "人工记录"))
            lines += snapshot.laborRecords.map {
                "- \($0.date)  \($0.workers)人 × \($0.hours)\($0.workloadUnit.displayName)  单价\(ReportBuilder.money(ReportBuilder.number($0.unitRate), currencyDisplayMode: currencyDisplayMode))/\($0.workloadUnit.displayName)  金额\(ReportBuilder.money(ReportBuilder.laborLineTotal($0), currencyDisplayMode: currencyDisplayMode))  \($0.note)"
            }
            lines.append("")
        }
        if options.includeDailyLogs {
            lines.append(String(localized: "施工日志"))
            lines += snapshot.dailyLogs.map { "- \($0.date) \($0.weather) \($0.workers)  \($0.content)" }
            lines.append("")
        }
        if options.includeTodos && !snapshot.siteTodos.isEmpty {
            lines.append(String(localized: "现场待办"))
            lines += snapshot.siteTodos.map {
                "- \($0.dueDate) [\($0.priority.displayName)] [\($0.issueType.displayName)] \($0.isDone ? String(localized: "完成") : $0.isOverdue ? String(localized: "延期") : String(localized: "待办"))  \($0.title) \($0.owner)"
            }
            lines.append("")
        }
        if options.includeProgress {
            lines.append(String(localized: "进度任务"))
            lines += snapshot.progressTasks.map {
                "- \($0.title)  \(Int($0.clampedCompletion * 100))%  \($0.startDate)-\($0.dueDate)"
            }
        }
        if options.includeProjectFinance {
            lines.append("")
            lines.append(String(localized: "项目财务流水"))
            lines += snapshot.projectFinancialRecords.sorted(by: { $0.date > $1.date }).map {
                let reminder = $0.hasDueReminder ? "  到期\($0.dueDate) \($0.normalizedReminderStatus.displayName)" : ""
                return "- \($0.date) [\($0.direction.displayName)] [\($0.category.displayName)] [\($0.normalizedStatus.displayName)]\(reminder) \(ReportBuilder.money(ReportBuilder.number($0.amount), currencyDisplayMode: currencyDisplayMode))  \($0.counterparty)  票据\($0.linkedDocumentIds.count)份"
            }
        }
        if options.includeProjectDocuments {
            let checklistRows = ReportBuilder.projectDocumentChecklistExportRows(snapshot: snapshot)
            let missingCount = checklistRows.filter { $0.item.isMissing }.count
            let actionCount = checklistRows.reduce(0) { $0 + $1.item.actionCount }
            let archivedDocumentCount = checklistRows.reduce(0) { $0 + $1.item.archivedCount }
            lines.append("")
            lines.append(String(localized: "施工资料清单"))
            lines.append(String(format: String(localized: "模板项 %lld 类 · 缺项 %lld · 待处理 %lld · 已归档 %lld"), Int64(checklistRows.count), Int64(missingCount), Int64(actionCount), Int64(archivedDocumentCount)))
            lines += checklistRows.map {
                let projectName = $0.projectName.isEmpty ? "" : "\($0.projectName)  "
                return "- [\($0.item.statusText)] \(projectName)\($0.item.category.displayName)  \($0.item.detailText)"
            }
            lines.append("")
            lines.append(String(localized: "项目票据与资料"))
            lines += snapshot.projectDocuments.sorted(by: { $0.createdAt > $1.createdAt }).map {
                let register = [$0.versionDisplayText, $0.submissionStatus.displayName, $0.responsiblePerson, $0.formedAt, $0.archiveNumber, $0.workSection]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                return "- \($0.createdAt) [\($0.category.displayName)] \($0.title)  \($0.pageCount)页  \(ReportBuilder.money(ReportBuilder.number($0.amount), currencyDisplayMode: currencyDisplayMode))  \(register)"
            }
        }
        if options.includeProjectContacts && !snapshot.projectContacts.isEmpty {
            lines.append("")
            lines.append(String(localized: "项目联系人"))
            lines += snapshot.projectContacts.map { "- \($0.name) [\($0.roleDisplayName)] \($0.phone) \($0.company)" }
        }
        if options.includeProjectDrawings && !snapshot.projectDrawings.isEmpty {
            lines.append("")
            lines.append(String(localized: "图纸索引"))
            lines += snapshot.projectDrawings.map { drawing in
                let linkParts = [
                    drawing.linkedTodoIDs.isEmpty ? "" : String(format: String(localized: "待办 %lld"), Int64(drawing.linkedTodoIDs.count)),
                    drawing.linkedLogIDs.isEmpty ? "" : String(format: String(localized: "日志 %lld"), Int64(drawing.linkedLogIDs.count)),
                    drawing.linkedDocumentIDs.isEmpty ? "" : String(format: String(localized: "资料 %lld"), Int64(drawing.linkedDocumentIDs.count))
                ]
                .filter { !$0.isEmpty }
                let register = [
                    drawing.drawingNumber.isEmpty ? "" : String(format: String(localized: "图号: %@"), drawing.drawingNumber),
                    drawing.discipline,
                    drawing.floorArea,
                    drawing.isCurrentVersion ? String(localized: "当前版") : String(localized: "历史版"),
                    drawing.issuedAt.isEmpty ? "" : String(format: String(localized: "出图: %@"), drawing.issuedAt),
                    drawing.receiver.isEmpty ? "" : String(format: String(localized: "接收: %@"), drawing.receiver),
                    drawing.fileAvailabilityStatus.displayName,
                    drawing.externalOpenFailureReason.isEmpty ? "" : String(format: String(localized: "外部打开失败：%@"), drawing.externalOpenFailureReason),
                    linkParts.isEmpty ? "" : String(format: String(localized: "关联: %@"), linkParts.joined(separator: " · "))
                ]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
                return "- \(drawing.name) \(drawing.fileType) v\(drawing.version) [\(drawing.issueStatus.displayName)]  \(register)"
            }
        }
        if options.includeWarehouseMovements && !snapshot.projectWarehouseMovements.isEmpty {
            lines.append("")
            lines.append(String(localized: "仓库流水"))
            lines += snapshot.projectWarehouseMovements.map {
                "- \($0.date) [\($0.normalizedMovementType.displayName)] \($0.materialName) × \($0.quantity)\($0.unit)  \($0.counterparty)"
            }
        }
        if options.includeQuickNotes && !snapshot.quickNotes.isEmpty {
            lines.append("")
            lines.append(String(localized: "随手记"))
            lines += snapshot.quickNotes.map { "- \($0.title)  \($0.updatedAt)  附件\($0.attachments.count)个" }
        }
        if options.includeOperationAuditLogs && !options.operationAuditEntries.isEmpty {
            lines.append("")
            lines.append(String(localized: "操作审计日志"))
            lines += options.operationAuditEntries.map(ReportBuilder.operationAuditPDFLine)
        }
    }
}
