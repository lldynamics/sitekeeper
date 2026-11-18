import Foundation

extension ReportBuilder {
    static func makeHTMLReport(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var body = "<html><head><meta charset=\"utf-8\"></head><body>"
        let currencyDisplayMode = options.currencyDisplayMode
        func table(_ title: String, headers: [String], rows: [[any CustomStringConvertible]]) {
            body += "<h2>\(escapeHTML(title))</h2><table border=\"1\" cellspacing=\"0\" cellpadding=\"4\"><tr>"
            body += headers.map { "<th>\(escapeHTML($0.description))</th>" }.joined()
            body += "</tr>"
            for row in rows {
                body += "<tr>" + row.map { "<td>\(escapeHTML($0.description))</td>" }.joined() + "</tr>"
            }
            body += "</table>"
        }
        if options.includeMaterials {
            table(loc("材料清单"), headers: [loc("名称"), loc("数量"), loc("单位"), loc("单价"), loc("规格"), loc("品牌"), loc("供应商"), loc("采购状态"), loc("进场日期"), loc("金额")], rows: snapshot.materialItems.map {
                [$0.name, $0.quantity, $0.unit, $0.unitPrice, $0.specification, $0.brand, $0.supplier, $0.purchaseStatus.displayName, $0.arrivalDate, money(materialLineTotal($0), currencyDisplayMode: currencyDisplayMode)]
            })
        }
        if options.includeQuotes {
            table(loc("报价明细"), headers: [loc("名称"), loc("单价"), loc("数量"), loc("单位"), loc("版本"), loc("状态"), loc("确认日期"), loc("合同金额"), loc("金额"), loc("备注")], rows: snapshot.quoteItems.map {
                [$0.name, $0.unitPrice, $0.quantity, $0.unit, $0.versionName, $0.status.displayName, $0.customerConfirmedDate, amountDisplay(value: $0.contractAmount, currencyDisplayMode: currencyDisplayMode), money(quoteLineTotal($0), currencyDisplayMode: currencyDisplayMode), $0.notes]
            })
        }
        if options.includeLabor {
            table(loc("人工记录"), headers: [loc("日期"), loc("人数"), loc("工作量"), loc("单位"), loc("单价"), loc("工种"), loc("班组"), loc("结算"), loc("金额"), loc("备注")], rows: snapshot.laborRecords.map {
                [$0.date, $0.workers, $0.hours, $0.workloadUnit.displayName, $0.unitRate, $0.workType, $0.teamName, $0.isSettled ? locYes : locNo, money(laborLineTotal($0), currencyDisplayMode: currencyDisplayMode), $0.note]
            })
        }
        if options.includeDailyLogs {
            table(loc("施工日志"), headers: [loc("日期"), loc("天气"), loc("人数"), loc("内容"), loc("安全事项"), loc("材料进场"), loc("明日计划"), loc("质量问题"), loc("整改记录"), loc("确认人"), loc("照片数")], rows: snapshot.dailyLogs.map {
                [$0.date, $0.weather, $0.workers, $0.content, $0.safety, $0.materials, $0.tomorrowPlan, $0.qualityIssue, $0.rectification, $0.confirmer, "\($0.photoAttachments.count)"]
            })
        }
        if options.includeProgress {
            table(loc("进度任务"), headers: [loc("任务"), loc("开始"), loc("截止"), loc("完成率"), loc("备注")], rows: snapshot.progressTasks.map {
                [$0.title, $0.startDate, $0.dueDate, "\(Int($0.clampedCompletion * 100))%", $0.note]
            })
        }
        if options.includeTodos {
            table(loc("现场待办"), headers: [loc("事项"), loc("负责人"), loc("日期"), loc("优先级"), loc("问题类型"), loc("状态"), loc("完成时间"), loc("备注")], rows: snapshot.siteTodos.map {
                [$0.title, $0.owner, $0.dueDate, $0.priority.displayName, $0.issueType.displayName, $0.isDone ? locDone : $0.isOverdue ? locOverdue : locPending, Formatters.displayDateText($0.completedAt?.storageText ?? ""), $0.note]
            })
        }
        if options.includeProjectFinance {
            table(loc("项目财务流水"), headers: [loc("日期"), loc("收支"), loc("分类"), loc("状态"), loc("到期日"), loc("提醒状态"), loc("金额"), loc("对方单位"), loc("票号"), loc("关联票据数"), loc("备注"), loc("项目ID")], rows: snapshot.projectFinancialRecords.map {
                [Formatters.displayDateText($0.date), $0.direction.displayName, $0.category.displayName, $0.normalizedStatus.displayName, $0.dueDate, $0.normalizedReminderStatus.displayName, amountDisplay(value: $0.amount, currencyDisplayMode: currencyDisplayMode), $0.counterparty, $0.invoiceNumber, "\($0.linkedDocumentIds.count)", $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDocuments {
            let checklistRows = projectDocumentChecklistExportRows(snapshot: snapshot)
            table(loc("施工资料清单"), headers: [loc("项目"), loc("类别"), loc("状态"), loc("资料数"), loc("待处理"), loc("退回"), loc("已归档")], rows: checklistRows.map {
                [$0.projectName, $0.item.category.displayName, $0.item.statusText, "\($0.item.documentCount)", "\($0.item.actionCount)", "\($0.item.returnedCount)", "\($0.item.archivedCount)"]
            })
            table(loc("项目票据与资料"), headers: [loc("名称"), loc("类型"), loc("版本"), loc("版本状态"), loc("替换上一版ID"), loc("后续版本ID"), loc("报验状态"), loc("责任人"), loc("形成日期"), loc("归档编号"), loc("分部/工序"), loc("页数"), loc("金额"), loc("创建时间"), loc("关联账目ID"), loc("文件名"), loc("备注"), loc("项目ID")], rows: snapshot.projectDocuments.map {
                [$0.title, $0.category.displayName, $0.versionLabel, $0.versionState.displayName, $0.replacesDocumentId?.uuidString ?? "", $0.replacedByDocumentId?.uuidString ?? "", $0.submissionStatus.displayName, $0.responsiblePerson, Formatters.displayDateText($0.formedAt), $0.archiveNumber, $0.workSection, "\($0.pageCount)", amountDisplay(value: $0.amount, currencyDisplayMode: currencyDisplayMode), Formatters.displayDateText($0.createdAt), $0.linkedFinancialRecordId?.uuidString ?? "", $0.fileName, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectContacts {
            table(loc("项目联系人"), headers: [loc("姓名"), loc("角色"), loc("电话"), loc("公司"), loc("备注"), loc("项目ID")], rows: snapshot.projectContacts.map {
                [$0.name, $0.roleDisplayName, $0.phone, $0.company, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDrawings {
            table(loc("图纸索引"), headers: [loc("名称"), loc("图号"), loc("专业"), loc("楼层/区域"), loc("类型"), loc("版本"), loc("当前版"), loc("出图日期"), loc("接收人"), loc("文件名"), loc("文件状态"), loc("状态检查时间"), loc("外部打开失败原因"), loc("外部失败时间"), loc("问题状态"), loc("问题备注"), loc("关联待办"), loc("关联日志"), loc("关联资料"), loc("导入时间"), loc("关联日志日期"), loc("备注"), loc("项目ID")], rows: snapshot.projectDrawings.map {
                [
                    $0.name,
                    $0.drawingNumber,
                    $0.discipline,
                    $0.floorArea,
                    $0.fileType,
                    $0.version,
                    $0.isCurrentVersion ? loc("是") : loc("否"),
                    $0.issuedAt,
                    $0.receiver,
                    $0.fileName,
                    $0.fileAvailabilityStatus.displayName,
                    Formatters.displayDateText($0.fileAvailabilityCheckedAt),
                    $0.externalOpenFailureReason,
                    Formatters.displayDateText($0.externalOpenFailedAt),
                    $0.issueStatus.displayName,
                    $0.issueNote,
                    "\($0.linkedTodoIDs.count)",
                    "\($0.linkedLogIDs.count)",
                    "\($0.linkedDocumentIDs.count)",
                    Formatters.displayDateText($0.importedAt),
                    $0.relatedLogDate,
                    $0.note,
                    $0.projectId.uuidString
                ]
            })
        }
        if options.includeWarehouseMovements {
            table(loc("仓库流水"), headers: [loc("日期"), loc("类型"), loc("材料名称"), loc("规格"), loc("单位"), loc("数量"), loc("对方单位"), loc("操作人"), loc("备注"), loc("关联单据数"), loc("项目ID")], rows: snapshot.projectWarehouseMovements.map {
                [$0.date, $0.normalizedMovementType.displayName, $0.materialName, $0.specification, $0.unit, $0.quantity, $0.counterparty, $0.handler, $0.note, "\($0.linkedDocumentIds.count)", $0.projectId.uuidString]
            })
        }
        if options.includeQuickNotes {
            table(loc("随手记"), headers: [loc("标题"), loc("内容"), loc("创建时间"), loc("更新时间"), loc("附件数"), loc("项目ID")], rows: snapshot.quickNotes.map {
                [$0.title, $0.content, Formatters.displayDateText($0.createdAt), Formatters.displayDateText($0.updatedAt), "\($0.attachments.count)", $0.projectId?.uuidString ?? ""]
            })
        }
        if options.includeOperationAuditLogs {
            table(
                loc("操作审计日志"),
                headers: operationAuditDisplayHeaders(),
                rows: options.operationAuditEntries.map(operationAuditDisplayRow)
            )
        }
        body += "</body></html>"
        return Data(body.utf8)
    }
}
