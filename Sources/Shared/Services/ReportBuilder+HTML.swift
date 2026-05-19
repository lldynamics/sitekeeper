import Foundation

extension ReportBuilder {
    static func makeExcelHTML(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var body = "<html><head><meta charset=\"utf-8\"></head><body>"
        let currencyDisplayMode = options.currencyDisplayMode
        func table(_ title: String, headers: [String], rows: [[String]]) {
            body += "<h2>\(escapeHTML(title))</h2><table border=\"1\" cellspacing=\"0\" cellpadding=\"4\"><tr>"
            body += headers.map { "<th>\(escapeHTML($0))</th>" }.joined()
            body += "</tr>"
            for row in rows {
                body += "<tr>" + row.map { "<td>\(escapeHTML($0))</td>" }.joined() + "</tr>"
            }
            body += "</table>"
        }
        if options.includeMaterials {
            table(loc("材料清单"), headers: ["名称", "数量", "单位", "单价", "规格", "品牌", "供应商", "采购状态", "进场日期", "金额"], rows: snapshot.materialItems.map {
                [$0.name, $0.quantity, $0.unit, $0.unitPrice, $0.specification, $0.brand, $0.supplier, $0.purchaseStatus.displayName, $0.arrivalDate, money(materialLineTotal($0), currencyDisplayMode: currencyDisplayMode)]
            })
        }
        if options.includeQuotes {
            table(loc("报价明细"), headers: ["名称", "单价", "数量", "单位", "版本", "状态", "确认日期", "合同金额", "金额", "备注"], rows: snapshot.quoteItems.map {
                [$0.name, $0.unitPrice, $0.quantity, $0.unit, $0.versionName, $0.status.displayName, $0.customerConfirmedDate, amountDisplay(rawText: $0.contractAmount, currencyDisplayMode: currencyDisplayMode), money(quoteLineTotal($0), currencyDisplayMode: currencyDisplayMode), $0.notes]
            })
        }
        if options.includeLabor {
            table(loc("人工记录"), headers: ["日期", "人数", "工时", "单价", "工种", "班组", "结算", "金额", "备注"], rows: snapshot.laborRecords.map {
                [$0.date, $0.workers, $0.hours, $0.unitRate, $0.workType, $0.teamName, $0.isSettled ? locYes : locNo, money(laborLineTotal($0), currencyDisplayMode: currencyDisplayMode), $0.note]
            })
        }
        if options.includeDailyLogs {
            table(loc("施工日志"), headers: ["日期", "天气", "人数", "内容", "安全事项", "材料进场", "明日计划", "质量问题", "整改记录", "确认人", "照片数"], rows: snapshot.dailyLogs.map {
                [$0.date, $0.weather, $0.workers, $0.content, $0.safety, $0.materials, $0.tomorrowPlan, $0.qualityIssue, $0.rectification, $0.confirmer, "\($0.photoAttachments.count)"]
            })
        }
        if options.includeProgress {
            table(loc("进度任务"), headers: ["任务", "开始", "截止", "完成率", "备注"], rows: snapshot.progressTasks.map {
                [$0.title, $0.startDate, $0.dueDate, "\(Int($0.clampedCompletion * 100))%", $0.note]
            })
        }
        if options.includeTodos {
            table(loc("现场待办"), headers: ["事项", "负责人", "日期", "优先级", "问题类型", "状态", "完成时间", "备注"], rows: snapshot.siteTodos.map {
                [$0.title, $0.owner, $0.dueDate, $0.priority.displayName, $0.issueType.displayName, $0.isDone ? locDone : $0.isOverdue ? locOverdue : locPending, $0.completedAt ?? "", $0.note]
            })
        }
        if options.includeProjectFinance {
            table(loc("项目财务流水"), headers: ["日期", "收支", "分类", "状态", "到期日", "提醒状态", "金额", "对方单位", "票号", "关联票据数", "备注", "项目ID"], rows: snapshot.projectFinancialRecords.map {
                [$0.date, $0.direction.displayName, $0.category.displayName, $0.normalizedStatus.displayName, $0.dueDate, $0.normalizedReminderStatus.displayName, amountDisplay(rawText: $0.amount, currencyDisplayMode: currencyDisplayMode), $0.counterparty, $0.invoiceNumber, "\($0.linkedDocumentIds.count)", $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDocuments {
            let checklistRows = projectDocumentChecklistExportRows(snapshot: snapshot)
            table(loc("施工资料清单"), headers: ["项目", "类别", "状态", "资料数", "待处理", "退回", "已归档"], rows: checklistRows.map {
                [$0.projectName, $0.item.category.displayName, $0.item.statusText, "\($0.item.documentCount)", "\($0.item.actionCount)", "\($0.item.returnedCount)", "\($0.item.archivedCount)"]
            })
            table(loc("项目票据与资料"), headers: ["名称", "类型", "版本", "版本状态", "替换上一版ID", "后续版本ID", "报验状态", "责任人", "形成日期", "归档编号", "分部/工序", "页数", "金额", "创建时间", "关联账目ID", "文件名", "备注", "项目ID"], rows: snapshot.projectDocuments.map {
                [$0.title, $0.category.displayName, $0.versionLabel, $0.versionState.displayName, $0.replacesDocumentId?.uuidString ?? "", $0.replacedByDocumentId?.uuidString ?? "", $0.submissionStatus.displayName, $0.responsiblePerson, $0.formedAt, $0.archiveNumber, $0.workSection, "\($0.pageCount)", amountDisplay(rawText: $0.amount, currencyDisplayMode: currencyDisplayMode), $0.createdAt, $0.linkedFinancialRecordId?.uuidString ?? "", $0.fileName, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectContacts {
            table(loc("项目联系人"), headers: ["姓名", "角色", "电话", "公司", "备注", "项目ID"], rows: snapshot.projectContacts.map {
                [$0.name, $0.roleDisplayName, $0.phone, $0.company, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDrawings {
            table(loc("图纸索引"), headers: ["名称", "类型", "版本", "文件名", "问题状态", "问题备注", "导入时间", "关联日志日期", "备注", "项目ID"], rows: snapshot.projectDrawings.map {
                [$0.name, $0.fileType, $0.version, $0.fileName, $0.issueStatus.displayName, $0.issueNote, $0.importedAt, $0.relatedLogDate, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeWarehouseMovements {
            table(loc("仓库流水"), headers: ["日期", "类型", "材料名称", "规格", "单位", "数量", "对方单位", "操作人", "备注", "关联单据数", "项目ID"], rows: snapshot.projectWarehouseMovements.map {
                [$0.date, $0.normalizedMovementType.displayName, $0.materialName, $0.specification, $0.unit, $0.quantity, $0.counterparty, $0.handler, $0.note, "\($0.linkedDocumentIds.count)", $0.projectId.uuidString]
            })
        }
        if options.includeQuickNotes {
            table(loc("随手记"), headers: ["标题", "内容", "创建时间", "更新时间", "附件数", "项目ID"], rows: snapshot.quickNotes.map {
                [$0.title, $0.content, $0.createdAt, $0.updatedAt, "\($0.attachments.count)", $0.projectId?.uuidString ?? ""]
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
