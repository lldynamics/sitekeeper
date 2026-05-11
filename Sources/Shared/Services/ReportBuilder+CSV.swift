import Foundation

extension ReportBuilder {
    static func makeCSV(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var rows: [String] = []
        if options.includeMaterials {
            rows.append(csvSection("材料清单"))
            rows.append(csv(["名称", "数量", "单位", "单价", "规格", "品牌", "供应商", "采购状态", "进场日期", "金额", "项目ID"]))
            rows += snapshot.materialItems.map { csv([$0.name, $0.quantity, $0.unit, $0.unitPrice, $0.specification, $0.brand, $0.supplier, $0.purchaseStatus.displayName, $0.arrivalDate, money(materialLineTotal($0)), $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeQuotes {
            rows.append(csvSection("报价明细"))
            rows.append(csv(["名称", "单价", "数量", "单位", "税率", "折扣", "版本", "状态", "客户确认日期", "合同金额", "备注", "项目ID"]))
            rows += snapshot.quoteItems.map { csv([$0.name, $0.unitPrice, $0.quantity, $0.unit, $0.taxRate, $0.discountRate, $0.versionName, $0.status.displayName, $0.customerConfirmedDate, $0.contractAmount, $0.notes, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeLabor {
            rows.append(csvSection("人工记录"))
            rows.append(csv(["日期", "人数", "工时", "单价", "工种", "班组", "是否结算", "金额", "备注", "项目ID"]))
            rows += snapshot.laborRecords.map { csv([$0.date, $0.workers, $0.hours, $0.unitRate, $0.workType, $0.teamName, $0.isSettled ? locYes : locNo, money(laborLineTotal($0)), $0.note, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeDailyLogs {
            rows.append(csvSection("施工日志"))
            rows.append(csv(["日期", "天气", "人数", "内容", "安全事项", "材料进场", "明日计划", "质量问题", "整改记录", "确认人", "照片数", "项目ID"]))
            rows += snapshot.dailyLogs.map { csv([$0.date, $0.weather, $0.workers, $0.content, $0.safety, $0.materials, $0.tomorrowPlan, $0.qualityIssue, $0.rectification, $0.confirmer, "\($0.photoAttachments.count)", $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeProgress {
            rows.append(csvSection("进度任务"))
            rows.append(csv(["任务", "开始", "截止", "完成率", "备注", "项目ID"]))
            rows += snapshot.progressTasks.map { csv([$0.title, $0.startDate, $0.dueDate, "\(Int($0.clampedCompletion * 100))%", $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeTodos {
            rows.append(csvSection("现场待办"))
            rows.append(csv(["事项", "负责人", "日期", "优先级", "问题类型", "状态", "完成时间", "整改前照片", "整改后照片", "备注", "项目ID"]))
            rows += snapshot.siteTodos.map { csv([$0.title, $0.owner, $0.dueDate, $0.priority.displayName, $0.issueType.displayName, $0.isDone ? locDone : $0.isOverdue ? locOverdue : locPending, $0.completedAt ?? "", $0.rectificationBeforePhotoFileName ?? "", $0.rectificationAfterPhotoFileName ?? "", $0.note, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeProjectFinance {
            rows.append(csvSection("项目财务流水"))
            rows.append(csv(["日期", "收支", "分类", "状态", "到期日", "提醒状态", "金额", "对方单位", "票号", "关联票据数量", "备注", "项目ID"]))
            rows += snapshot.projectFinancialRecords.map {
                csv([$0.date, $0.direction.displayName, $0.category.displayName, $0.normalizedStatus.displayName, $0.dueDate, $0.normalizedReminderStatus.displayName, $0.amount, $0.counterparty, $0.invoiceNumber, "\($0.linkedDocumentIds.count)", $0.note, $0.projectId.uuidString])
            }
            rows.append("")
        }
        if options.includeProjectDocuments {
            rows.append(csvSection("项目票据与资料"))
            rows.append(csv(["名称", "类型", "页数", "金额", "创建时间", "关联账目ID", "文件名", "备注", "项目ID"]))
            rows += snapshot.projectDocuments.map {
                csv([$0.title, $0.category.displayName, "\($0.pageCount)", $0.amount, $0.createdAt, $0.linkedFinancialRecordId?.uuidString ?? "", $0.fileName, $0.note, $0.projectId.uuidString])
            }
            rows.append("")
        }
        if options.includeProjectContacts {
            rows.append(csvSection("项目联系人"))
            rows.append(csv(["姓名", "角色", "电话", "公司", "备注", "项目ID"]))
            rows += snapshot.projectContacts.map { csv([$0.name, $0.roleDisplayName, $0.phone, $0.company, $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeProjectDrawings {
            rows.append(csvSection("图纸索引"))
            rows.append(csv(["名称", "类型", "版本", "文件名", "问题状态", "问题备注", "导入时间", "关联日志日期", "备注", "项目ID"]))
            rows += snapshot.projectDrawings.map { csv([$0.name, $0.fileType, $0.version, $0.fileName, $0.issueStatus.displayName, $0.issueNote, $0.importedAt, $0.relatedLogDate, $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeWarehouseMovements {
            rows.append(csvSection("仓库流水"))
            rows.append(csv(["日期", "类型", "材料名称", "规格", "单位", "数量", "对方单位", "操作人", "备注", "关联单据数", "项目ID"]))
            rows += snapshot.projectWarehouseMovements.map { csv([$0.date, $0.normalizedMovementType.displayName, $0.materialName, $0.specification, $0.unit, $0.quantity, $0.counterparty, $0.handler, $0.note, "\($0.linkedDocumentIds.count)", $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeQuickNotes {
            rows.append(csvSection("随手记"))
            rows.append(csv(["标题", "内容", "创建时间", "更新时间", "附件数", "项目ID"]))
            rows += snapshot.quickNotes.map { csv([$0.title, $0.content, $0.createdAt, $0.updatedAt, "\($0.attachments.count)", $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeLightingCircuits {
            rows.append(csvSection("照明回路"))
            rows.append(csv(["方案名称", "供电类型", "电压", "功率因数", "需用系数", "断路器裕量", "线径裕量", "铜导线", "负荷数", "更新时间", "项目ID"]))
            rows += snapshot.lightingCircuitPlans.map { csv([$0.name, $0.supplyType.displayName, $0.voltage, $0.powerFactor, $0.demandFactor, $0.breakerFactor, $0.wireFactor, $0.isCopper ? locYes : locNo, "\($0.loads.count)", $0.updatedAt, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includePaymentRecords {
            rows.append(csvSection("付款记录"))
            rows.append(csv(["日期", "金额", "方式", "备注", "是否开票", "项目ID"]))
            rows += snapshot.paymentRecords.map { csv([$0.date, $0.amount, $0.normalizedMethod.displayName, $0.note, $0.isInvoiced ? locYes : locNo, $0.projectId.uuidString]) }
        }
        return Data(rows.joined(separator: "\n").utf8)
    }
}
