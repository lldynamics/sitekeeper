import Foundation
import UIKit
import UniformTypeIdentifiers

struct ExportContentOptions {
    var includeMaterials = true
    var includeQuotes = true
    var includeLabor = true
    var includeDailyLogs = true
    var includeProgress = true
    var includeTodos = true
    var includeProjectFinance = true
    var includeProjectDocuments = true
    var includeProjectContacts = true
    var includeProjectDrawings = true
    var includeWarehouseMovements = true
    var includeQuickNotes = true
    var includeLightingCircuits = true
    var includePaymentRecords = true
}

struct ExportPayload {
    var data: Data
    var sourceFileURL: URL?
    var contentType: UTType
    var defaultFilename: String

    init(data: Data, contentType: UTType, defaultFilename: String) {
        self.data = data
        self.sourceFileURL = nil
        self.contentType = contentType
        self.defaultFilename = defaultFilename
    }

    init(fileURL: URL, contentType: UTType, defaultFilename: String) {
        self.data = Data()
        self.sourceFileURL = fileURL
        self.contentType = contentType
        self.defaultFilename = defaultFilename
    }
}

extension UTType {
    static var excelHTML: UTType {
        UTType(filenameExtension: "xls", conformingTo: .data) ?? .data
    }

    static var zipArchive: UTType {
        UTType.zip
    }
}

struct QuotationDocumentMeta {
    var companyName: String
    var companyPhone: String
    var companyAddress: String
    var customerName: String
    var projectAddress: String
    var validUntil: String
    var signerName: String
}

struct ReportPhotoItem {
    var date: String
    var projectName: String
    var tag: String
    var note: String
    var fileName: String
}

enum ProjectPackageArchiveError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消交付包导出。"
        }
    }
}

struct ProjectPackageExportProgress {
    let completedSteps: Int
    let totalSteps: Int
    let currentItem: String

    var fractionCompleted: Double {
        guard totalSteps > 0 else { return 0 }
        return min(max(Double(completedSteps) / Double(totalSteps), 0), 1)
    }
}

enum ReportBuilder {
    static func makeCSV(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var rows: [String] = []
        if options.includeMaterials {
            rows.append("[材料清单]")
            rows.append(csv(["名称", "数量", "单位", "单价", "规格", "品牌", "供应商", "采购状态", "进场日期", "金额", "项目ID"]))
            rows += snapshot.materialItems.map { csv([$0.name, $0.quantity, $0.unit, $0.unitPrice, $0.specification, $0.brand, $0.supplier, $0.purchaseStatus, $0.arrivalDate, money(materialLineTotal($0)), $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeQuotes {
            rows.append("[报价明细]")
            rows.append(csv(["名称", "单价", "数量", "单位", "税率", "折扣", "版本", "状态", "客户确认日期", "合同金额", "备注", "项目ID"]))
            rows += snapshot.quoteItems.map { csv([$0.name, $0.unitPrice, $0.quantity, $0.unit, $0.taxRate, $0.discountRate, $0.versionName, $0.status, $0.customerConfirmedDate, $0.contractAmount, $0.notes, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeLabor {
            rows.append("[人工记录]")
            rows.append(csv(["日期", "人数", "工时", "单价", "工种", "班组", "是否结算", "金额", "备注", "项目ID"]))
            rows += snapshot.laborRecords.map { csv([$0.date, $0.workers, $0.hours, $0.unitRate, $0.workType, $0.teamName, $0.isSettled ? "是" : "否", money(laborLineTotal($0)), $0.note, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeDailyLogs {
            rows.append("[施工日志]")
            rows.append(csv(["日期", "天气", "人数", "内容", "安全事项", "材料进场", "明日计划", "质量问题", "整改记录", "确认人", "照片数", "项目ID"]))
            rows += snapshot.dailyLogs.map { csv([$0.date, $0.weather, $0.workers, $0.content, $0.safety, $0.materials, $0.tomorrowPlan, $0.qualityIssue, $0.rectification, $0.confirmer, "\($0.photoAttachments.count)", $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeProgress {
            rows.append("[进度任务]")
            rows.append(csv(["任务", "开始", "截止", "完成率", "备注", "项目ID"]))
            rows += snapshot.progressTasks.map { csv([$0.title, $0.startDate, $0.dueDate, "\(Int($0.clampedCompletion * 100))%", $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeTodos {
            rows.append("[现场待办]")
            rows.append(csv(["事项", "负责人", "日期", "优先级", "问题类型", "状态", "完成时间", "整改前照片", "整改后照片", "备注", "项目ID"]))
            rows += snapshot.siteTodos.map { csv([$0.title, $0.owner, $0.dueDate, $0.priority, $0.issueType, $0.isDone ? "完成" : $0.isOverdue ? "延期" : "待办", $0.completedAt ?? "", $0.rectificationBeforePhotoFileName ?? "", $0.rectificationAfterPhotoFileName ?? "", $0.note, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeProjectFinance {
            rows.append("[项目财务流水]")
            rows.append(csv(["日期", "收支", "分类", "金额", "对方单位", "票号", "关联票据数量", "备注", "项目ID"]))
            rows += snapshot.projectFinancialRecords.map {
                csv([$0.date, $0.direction, $0.category, $0.amount, $0.counterparty, $0.invoiceNumber, "\($0.linkedDocumentIds.count)", $0.note, $0.projectId.uuidString])
            }
            rows.append("")
        }
        if options.includeProjectDocuments {
            rows.append("[项目票据与资料]")
            rows.append(csv(["名称", "类型", "页数", "金额", "创建时间", "关联账目ID", "文件名", "备注", "项目ID"]))
            rows += snapshot.projectDocuments.map {
                csv([$0.title, $0.category, "\($0.pageCount)", $0.amount, $0.createdAt, $0.linkedFinancialRecordId?.uuidString ?? "", $0.fileName, $0.note, $0.projectId.uuidString])
            }
            rows.append("")
        }
        if options.includeProjectContacts {
            rows.append("[项目联系人]")
            rows.append(csv(["姓名", "角色", "电话", "公司", "备注", "项目ID"]))
            rows += snapshot.projectContacts.map { csv([$0.name, $0.role, $0.phone, $0.company, $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeProjectDrawings {
            rows.append("[图纸索引]")
            rows.append(csv(["名称", "类型", "版本", "文件名", "问题状态", "问题备注", "导入时间", "关联日志日期", "备注", "项目ID"]))
            rows += snapshot.projectDrawings.map { csv([$0.name, $0.fileType, $0.version, $0.fileName, $0.issueStatus, $0.issueNote, $0.importedAt, $0.relatedLogDate, $0.note, $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeWarehouseMovements {
            rows.append("[仓库流水]")
            rows.append(csv(["日期", "类型", "材料名称", "规格", "单位", "数量", "对方单位", "操作人", "备注", "关联单据数", "项目ID"]))
            rows += snapshot.projectWarehouseMovements.map { csv([$0.date, $0.movementType, $0.materialName, $0.specification, $0.unit, $0.quantity, $0.counterparty, $0.handler, $0.note, "\($0.linkedDocumentIds.count)", $0.projectId.uuidString]) }
            rows.append("")
        }
        if options.includeQuickNotes {
            rows.append("[随手记]")
            rows.append(csv(["标题", "内容", "创建时间", "更新时间", "附件数", "项目ID"]))
            rows += snapshot.quickNotes.map { csv([$0.title, $0.content, $0.createdAt, $0.updatedAt, "\($0.attachments.count)", $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includeLightingCircuits {
            rows.append("[照明回路]")
            rows.append(csv(["方案名称", "供电类型", "电压", "功率因数", "需用系数", "断路器裕量", "线径裕量", "铜导线", "负荷数", "更新时间", "项目ID"]))
            rows += snapshot.lightingCircuitPlans.map { csv([$0.name, $0.supplyType.displayName, $0.voltage, $0.powerFactor, $0.demandFactor, $0.breakerFactor, $0.wireFactor, $0.isCopper ? "是" : "否", "\($0.loads.count)", $0.updatedAt, $0.projectId?.uuidString ?? ""]) }
            rows.append("")
        }
        if options.includePaymentRecords {
            rows.append("[付款记录]")
            rows.append(csv(["日期", "金额", "方式", "备注", "是否开票", "项目ID"]))
            rows += snapshot.paymentRecords.map { csv([$0.date, $0.amount, $0.method, $0.note, $0.isInvoiced ? "是" : "否", $0.projectId.uuidString]) }
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    static func makeExcelHTML(snapshot: BackupSnapshot, options: ExportContentOptions) -> Data {
        var body = "<html><head><meta charset=\"utf-8\"></head><body>"
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
            table("材料清单", headers: ["名称", "数量", "单位", "单价", "规格", "品牌", "供应商", "采购状态", "进场日期", "金额"], rows: snapshot.materialItems.map {
                [$0.name, $0.quantity, $0.unit, $0.unitPrice, $0.specification, $0.brand, $0.supplier, $0.purchaseStatus, $0.arrivalDate, money(materialLineTotal($0))]
            })
        }
        if options.includeQuotes {
            table("报价明细", headers: ["名称", "单价", "数量", "单位", "版本", "状态", "确认日期", "合同金额", "金额", "备注"], rows: snapshot.quoteItems.map {
                [$0.name, $0.unitPrice, $0.quantity, $0.unit, $0.versionName, $0.status, $0.customerConfirmedDate, $0.contractAmount, money(quoteLineTotal($0)), $0.notes]
            })
        }
        if options.includeLabor {
            table("人工记录", headers: ["日期", "人数", "工时", "单价", "工种", "班组", "结算", "金额", "备注"], rows: snapshot.laborRecords.map {
                [$0.date, $0.workers, $0.hours, $0.unitRate, $0.workType, $0.teamName, $0.isSettled ? "是" : "否", money(laborLineTotal($0)), $0.note]
            })
        }
        if options.includeDailyLogs {
            table("施工日志", headers: ["日期", "天气", "人数", "内容", "安全事项", "材料进场", "明日计划", "质量问题", "整改记录", "确认人", "照片数"], rows: snapshot.dailyLogs.map {
                [$0.date, $0.weather, $0.workers, $0.content, $0.safety, $0.materials, $0.tomorrowPlan, $0.qualityIssue, $0.rectification, $0.confirmer, "\($0.photoAttachments.count)"]
            })
        }
        if options.includeProgress {
            table("进度任务", headers: ["任务", "开始", "截止", "完成率", "备注"], rows: snapshot.progressTasks.map {
                [$0.title, $0.startDate, $0.dueDate, "\(Int($0.clampedCompletion * 100))%", $0.note]
            })
        }
        if options.includeTodos {
            table("现场待办", headers: ["事项", "负责人", "日期", "优先级", "问题类型", "状态", "完成时间", "备注"], rows: snapshot.siteTodos.map {
                [$0.title, $0.owner, $0.dueDate, $0.priority, $0.issueType, $0.isDone ? "完成" : $0.isOverdue ? "延期" : "待办", $0.completedAt ?? "", $0.note]
            })
        }
        if options.includeProjectFinance {
            table("项目财务流水", headers: ["日期", "收支", "分类", "金额", "对方单位", "票号", "关联票据数", "备注", "项目ID"], rows: snapshot.projectFinancialRecords.map {
                [$0.date, $0.direction, $0.category, $0.amount, $0.counterparty, $0.invoiceNumber, "\($0.linkedDocumentIds.count)", $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDocuments {
            table("项目票据与资料", headers: ["名称", "类型", "页数", "金额", "创建时间", "关联账目ID", "文件名", "备注", "项目ID"], rows: snapshot.projectDocuments.map {
                [$0.title, $0.category, "\($0.pageCount)", $0.amount, $0.createdAt, $0.linkedFinancialRecordId?.uuidString ?? "", $0.fileName, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectContacts {
            table("项目联系人", headers: ["姓名", "角色", "电话", "公司", "备注", "项目ID"], rows: snapshot.projectContacts.map {
                [$0.name, $0.role, $0.phone, $0.company, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeProjectDrawings {
            table("图纸索引", headers: ["名称", "类型", "版本", "文件名", "问题状态", "问题备注", "导入时间", "关联日志日期", "备注", "项目ID"], rows: snapshot.projectDrawings.map {
                [$0.name, $0.fileType, $0.version, $0.fileName, $0.issueStatus, $0.issueNote, $0.importedAt, $0.relatedLogDate, $0.note, $0.projectId.uuidString]
            })
        }
        if options.includeWarehouseMovements {
            table("仓库流水", headers: ["日期", "类型", "材料名称", "规格", "单位", "数量", "对方单位", "操作人", "备注", "关联单据数", "项目ID"], rows: snapshot.projectWarehouseMovements.map {
                [$0.date, $0.movementType, $0.materialName, $0.specification, $0.unit, $0.quantity, $0.counterparty, $0.handler, $0.note, "\($0.linkedDocumentIds.count)", $0.projectId.uuidString]
            })
        }
        if options.includeQuickNotes {
            table("随手记", headers: ["标题", "内容", "创建时间", "更新时间", "附件数", "项目ID"], rows: snapshot.quickNotes.map {
                [$0.title, $0.content, $0.createdAt, $0.updatedAt, "\($0.attachments.count)", $0.projectId?.uuidString ?? ""]
            })
        }
        if options.includeLightingCircuits {
            table("照明回路", headers: ["方案名称", "供电类型", "电压", "功率因数", "需用系数", "断路器裕量", "线径裕量", "铜导线", "负荷数", "更新时间", "项目ID"], rows: snapshot.lightingCircuitPlans.map {
                [$0.name, $0.supplyType.displayName, $0.voltage, $0.powerFactor, $0.demandFactor, $0.breakerFactor, $0.wireFactor, $0.isCopper ? "是" : "否", "\($0.loads.count)", $0.updatedAt, $0.projectId?.uuidString ?? ""]
            })
        }
        if options.includePaymentRecords {
            table("付款记录", headers: ["日期", "金额", "方式", "备注", "是否开票", "项目ID"], rows: snapshot.paymentRecords.map {
                [$0.date, $0.amount, $0.method, $0.note, $0.isInvoiced ? "是" : "否", $0.projectId.uuidString]
            })
        }
        body += "</body></html>"
        return Data(body.utf8)
    }

    static func makePDF(snapshot: BackupSnapshot, options: ExportContentOptions, title: String = "\(AppBrand.displayName) 数据导出") -> Data {
        var lines: [String] = [title, "生成时间: \(Formatters.now())", ""]
        if options.includeMaterials {
            lines.append("材料清单")
            lines += snapshot.materialItems.map {
                "- \($0.name)  \($0.quantity) \($0.unit)  单价\(money(number($0.unitPrice)))  金额\(money(materialLineTotal($0)))"
            }
            lines.append("")
        }
        if options.includeQuotes {
            let total = snapshot.quoteItems.reduce(0) { $0 + quoteGrandTotal($1) }
            lines.append("报价明细  合计 \(money(total))")
            lines += snapshot.quoteItems.map { "- \($0.name)  \($0.quantity)\($0.unit)  \(money(quoteGrandTotal($0)))" }
            lines.append("")
        }
        if options.includeLabor {
            lines.append("人工记录")
            lines += snapshot.laborRecords.map {
                "- \($0.date)  \($0.workers)人 × \($0.hours)h  单价\(money(number($0.unitRate)))  金额\(money(laborLineTotal($0)))  \($0.note)"
            }
            lines.append("")
        }
        if options.includeDailyLogs {
            lines.append("施工日志")
            lines += snapshot.dailyLogs.map { "- \($0.date) \($0.weather) \($0.workers)  \($0.content)" }
            lines.append("")
        }
        if options.includeTodos && !snapshot.siteTodos.isEmpty {
            lines.append("现场待办")
            lines += snapshot.siteTodos.map { "- \($0.dueDate) [\($0.priority)] [\($0.issueType)] \($0.isDone ? "完成" : $0.isOverdue ? "延期" : "待办")  \($0.title) \($0.owner)" }
            lines.append("")
        }
        if options.includeProgress {
            lines.append("进度任务")
            lines += snapshot.progressTasks.map { "- \($0.title)  \(Int($0.clampedCompletion * 100))%  \($0.startDate)-\($0.dueDate)" }
        }
        if options.includeProjectFinance {
            lines.append("")
            lines.append("项目财务流水")
            lines += snapshot.projectFinancialRecords.sorted(by: { $0.date > $1.date }).map {
                "- \($0.date) [\($0.direction)] [\($0.category)] \(money(number($0.amount)))  \($0.counterparty)  票据\($0.linkedDocumentIds.count)份"
            }
        }
        if options.includeProjectDocuments {
            lines.append("")
            lines.append("项目票据与资料")
            lines += snapshot.projectDocuments.sorted(by: { $0.createdAt > $1.createdAt }).map {
                "- \($0.createdAt) [\($0.category)] \($0.title)  \($0.pageCount)页  \(money(number($0.amount)))"
            }
        }
        if options.includeProjectContacts && !snapshot.projectContacts.isEmpty {
            lines.append("")
            lines.append("项目联系人")
            lines += snapshot.projectContacts.map { "- \($0.name) [\($0.role)] \($0.phone) \($0.company)" }
        }
        if options.includeProjectDrawings && !snapshot.projectDrawings.isEmpty {
            lines.append("")
            lines.append("图纸索引")
            lines += snapshot.projectDrawings.map { "- \($0.name) \($0.fileType) v\($0.version) [\($0.issueStatus)]" }
        }
        if options.includeWarehouseMovements && !snapshot.projectWarehouseMovements.isEmpty {
            lines.append("")
            lines.append("仓库流水")
            lines += snapshot.projectWarehouseMovements.map { "- \($0.date) [\($0.movementType)] \($0.materialName) × \($0.quantity)\($0.unit)  \($0.counterparty)" }
        }
        if options.includeQuickNotes && !snapshot.quickNotes.isEmpty {
            lines.append("")
            lines.append("随手记")
            lines += snapshot.quickNotes.map { "- \($0.title)  \($0.updatedAt)  附件\($0.attachments.count)个" }
        }
        if options.includeLightingCircuits && !snapshot.lightingCircuitPlans.isEmpty {
            lines.append("")
            lines.append("照明回路")
            lines += snapshot.lightingCircuitPlans.map { (plan: LightingCircuitPlan) in return "- \(plan.name) [\(plan.supplyType.displayName)] \(plan.voltage)V  \(plan.loads.count)个负荷" }
        }
        if options.includePaymentRecords && !snapshot.paymentRecords.isEmpty {
            lines.append("")
            lines.append("付款记录")
            lines += snapshot.paymentRecords.map { "- \($0.date) \(money(number($0.amount))) [\($0.method)] \($0.note)" }
        }
        return pdfData(lines: lines)
    }

    static func makeLightingCircuitPlansPDF(projectName: String, plans: [LightingCircuitPlan]) -> Data {
        var lines: [String] = ["\(projectName)-照明回路方案", "生成时间: \(Formatters.now())", ""]
        guard !plans.isEmpty else {
            lines.append("暂无回路方案")
            return pdfData(lines: lines)
        }

        for plan in plans.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            lines.append("方案: \(plan.name)")
            lines.append("更新时间: \(plan.updatedAt)")

            guard let evaluation = evaluateLightingPlan(plan) else {
                lines.append("参数无效，无法计算")
                lines.append("")
                continue
            }

            lines.append("供电: \(plan.supplyType.displayName)  \(Int(evaluation.voltage))V")
            lines.append("功率因数: \(fmt(evaluation.powerFactor))  需用系数: \(fmt(evaluation.demandFactor))")
            lines.append("回路明细:")
            for row in evaluation.rows {
                let phaseText = row.phaseName.isEmpty ? "" : "  相别\(row.phaseName)"
                lines.append(
                    "- \(row.name): 装机\(fmt(row.installedPowerKW))kW, 计算\(fmt(row.demandPowerKW))kW, " +
                    "I=\(fmt(row.currentA))A, 空开\(row.breakerA)A, 线径\(row.wireSectionText)\(phaseText)"
                )
            }

            lines.append("汇总: 回路数 \(evaluation.rows.count), 总装机 \(fmt(evaluation.totalInstalledPowerKW))kW, 总计算 \(fmt(evaluation.totalDemandPowerKW))kW, 电流合计 \(fmt(evaluation.totalCurrentA))A")
            if let totals = evaluation.phaseTotals, let imbalance = evaluation.imbalancePercent {
                lines.append("A/B/C相电流: \(fmt(totals[0])) / \(fmt(totals[1])) / \(fmt(totals[2])) A")
                lines.append("三相不平衡: \(fmt(imbalance))%")
            }
            lines.append("")
        }
        return pdfData(lines: lines)
    }

    static func makeLightingCircuitPlansExcelHTML(projectName: String, plans: [LightingCircuitPlan]) -> Data {
        var body = "<html><head><meta charset=\"utf-8\"></head><body>"
        body += "<h1>\(escapeHTML(projectName))-照明回路方案</h1>"
        body += "<p>生成时间: \(escapeHTML(Formatters.now()))</p>"

        if plans.isEmpty {
            body += "<p>暂无回路方案</p></body></html>"
            return Data(body.utf8)
        }

        for plan in plans.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            body += "<h2>\(escapeHTML(plan.name))</h2>"
            body += "<p>更新时间: \(escapeHTML(plan.updatedAt))</p>"

            guard let evaluation = evaluateLightingPlan(plan) else {
                body += "<p>参数无效，无法计算</p>"
                continue
            }

            body += "<table border=\"1\" cellspacing=\"0\" cellpadding=\"4\">"
            body += "<tr><th>回路名称</th><th>装机(kW)</th><th>计算(kW)</th><th>电流(A)</th><th>断路器(A)</th><th>线径(mm²)</th><th>相别</th></tr>"
            for row in evaluation.rows {
                body += "<tr>"
                body += "<td>\(escapeHTML(row.name))</td>"
                body += "<td>\(fmt(row.installedPowerKW))</td>"
                body += "<td>\(fmt(row.demandPowerKW))</td>"
                body += "<td>\(fmt(row.currentA))</td>"
                body += "<td>\(row.breakerA)</td>"
                body += "<td>\(escapeHTML(row.wireSectionText))</td>"
                body += "<td>\(escapeHTML(row.phaseName))</td>"
                body += "</tr>"
            }
            body += "</table>"
            body += "<p>汇总: 回路数 \(evaluation.rows.count), 总装机 \(fmt(evaluation.totalInstalledPowerKW))kW, 总计算 \(fmt(evaluation.totalDemandPowerKW))kW, 电流合计 \(fmt(evaluation.totalCurrentA))A</p>"
            if let totals = evaluation.phaseTotals, let imbalance = evaluation.imbalancePercent {
                body += "<p>A/B/C相电流: \(fmt(totals[0])) / \(fmt(totals[1])) / \(fmt(totals[2])) A, 三相不平衡: \(fmt(imbalance))%</p>"
            }
        }
        body += "</body></html>"
        return Data(body.utf8)
    }

    static func makeQuotationPDF(
        title: String,
        items: [QuoteItem],
        projects: [Project]
    ) -> Data {
        let validityDays = max(1, UserPreferences.int(UserPreferenceKeys.quoteValidityDays, default: 15))
        let validUntil = Formatters.date.string(
            from: Calendar.current.date(byAdding: .day, value: validityDays, to: Date()) ?? Date()
        )
        let projectAddress = resolvedSingleProjectAddress(items: items, projects: projects) ?? "未填写"
        let companyName = UserPreferences.string(UserPreferenceKeys.companyName, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyPhone = UserPreferences.string(UserPreferenceKeys.companyPhone, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let companyAddress = UserPreferences.string(UserPreferenceKeys.companyAddress, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let meta = QuotationDocumentMeta(
            companyName: companyName.isEmpty ? "未填写" : companyName,
            companyPhone: companyPhone.isEmpty ? "未填写" : companyPhone,
            companyAddress: companyAddress.isEmpty ? "未填写" : companyAddress,
            customerName: "未填写",
            projectAddress: projectAddress,
            validUntil: validUntil,
            signerName: "项目负责人"
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

        let subtotal = items.reduce(0) { $0 + quoteLineTotal($1) }
        let tax = items.reduce(0) { $0 + quoteLineTotal($1) * ((Double($1.taxRate) ?? 0) / 100) }
        let discount = items.reduce(0) { $0 + quoteLineTotal($1) * ((Double($1.discountRate) ?? 0) / 100) }
        let total = subtotal + tax - discount
        let projectName = resolvedProjectName(items: items, projects: projects)

        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = 36

            y = drawPDFText(title, at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20), alignment: .center) + 4
            y = drawPDFText(meta.companyName, at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11), alignment: .center)
            y = drawPDFText("电话: \(meta.companyPhone)    地址: \(meta.companyAddress)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 10), alignment: .center) + 12

            y = drawPDFText("客户名称: \(meta.customerName)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText("项目名称: \(projectName)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText("项目地址: \(meta.projectAddress)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
            y = drawPDFText("报价日期: \(Formatters.date.string(from: Date()))    有效期至: \(meta.validUntil)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11)) + 10

            let columns: [(title: String, width: CGFloat)] = [
                ("项目", 124), ("单位", 38), ("数量", 44), ("单价", 62),
                ("税率", 42), ("折扣", 42), ("金额", 76), ("备注", 95)
            ]
            let rowHeight: CGFloat = 24
            y = drawPDFTableHeader(columns: columns, startX: margin, y: y, height: rowHeight)

            let rows = items.isEmpty ? [[
                "暂无明细", "-", "-", "-", "-", "-", "-", "-"
            ]] : items.map { item in
                [
                    item.name,
                    item.unit,
                    item.quantity,
                    money(Double(item.unitPrice) ?? 0),
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
            y = drawPDFText("小计: \(money(subtotal))", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText("税额: \(money(tax))    折扣: -\(money(discount))", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            y = drawPDFText("合计: \(money(total))", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 14)) + 18

            _ = drawPDFText("签字确认: \(meta.signerName)____________________", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
        }
    }

    static func makeDailyReportPDF(project: Project?, logs: [DailyLog]) -> Data {
        let title = project.map { "\($0.name)-施工日报" } ?? "施工日报"
        var lines: [String] = [title, "生成时间: \(Formatters.now())", ""]
        if let project {
            lines.append("客户: \(project.customerName.isEmpty ? "未填写" : project.customerName)")
            lines.append("地址: \(project.location)")
            lines.append("负责人: \(project.managerName.isEmpty ? "未填写" : project.managerName)")
            lines.append("")
        }
        if logs.isEmpty {
            lines.append("暂无施工日志")
            return pdfData(lines: lines)
        }
        for log in logs.sorted(by: { $0.date > $1.date }) {
            lines.append("\(log.date)  \(log.weather)  \(log.workers)")
            lines.append("施工内容: \(log.content)")
            if !log.safety.isEmpty { lines.append("安全事项: \(log.safety)") }
            if !log.materials.isEmpty { lines.append("材料进场: \(log.materials)") }
            if !log.tomorrowPlan.isEmpty { lines.append("明日计划: \(log.tomorrowPlan)") }
            if !log.qualityIssue.isEmpty { lines.append("质量问题: \(log.qualityIssue)") }
            if !log.rectification.isEmpty { lines.append("整改记录: \(log.rectification)") }
            if !log.confirmer.isEmpty { lines.append("现场确认: \(log.confirmer)") }
            if !log.photoAttachments.isEmpty {
                let photoText = log.photoAttachments.map { "\($0.tag): \($0.note.isEmpty ? $0.fileName : $0.note)" }.joined(separator: "；")
                lines.append("照片: \(photoText)")
            }
            lines.append("")
        }
        return pdfData(lines: lines)
    }

    static func makePhotoWallPDF(title: String, items: [ReportPhotoItem]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            drawPhotoWallPages(title: title, items: items, context: context, page: page, margin: 36)
        }
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
        let contract = Double(project.contractAmount) ?? 0
        let paid = paidAmountOverride ?? Double(project.paidAmount) ?? 0
        let materialCost = materials.reduce(0) { $0 + materialLineTotal($1) }
        let laborCost = labor.reduce(0) { $0 + laborLineTotal($1) }
        let totalLaborHours = labor.reduce(0) { $0 + laborHours($1) }
        let progress = tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.clampedCompletion } / Double(tasks.count)

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
                    tag: photo.tag,
                    note: photo.note,
                    fileName: photo.fileName
                )
            }
        }

        return renderer.pdfData { context in
            // 1. 封面
            context.beginPage()
            var y: CGFloat = 90
            y = drawPDFText("\(project.name) 项目交付包", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 24), alignment: .center) + 12
            _ = drawPDFText("生成时间: \(Formatters.now())", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12), alignment: .center)
            y = 220
            y = drawPDFText("项目地址: \(project.location)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText("客户: \(project.customerName.isEmpty ? "未填写" : project.customerName)  电话: \(project.customerPhone.isEmpty ? "-" : project.customerPhone)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText("负责人: \(project.managerName.isEmpty ? "未填写" : project.managerName)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText("工期: \(project.startDate.isEmpty ? "未填写" : project.startDate) 至 \(project.expectedEndDate.isEmpty ? "未填写" : project.expectedEndDate)", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText("合同金额: \(money(contract))  已收: \(money(paid))  未收: \(money(max(contract - paid, 0)))", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            y = drawPDFText("报价合计: \(money(quoteTotal))  材料成本: \(money(materialCost))  人工成本: \(money(laborCost))", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            _ = drawPDFText("毛利估算: \(money(contract - materialCost - laborCost))  工时: \(fmt(totalLaborHours))  进度: \(Int(progress * 100))%", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))

            // 2. 目录
            context.beginPage()
            var tocY: CGFloat = 90
            tocY = drawPDFText("目录", at: CGPoint(x: margin, y: tocY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20))
            let tocItems = [
                "1. 项目封面",
                "2. 目录",
                "3. 报价表",
                "4. 日志表",
                "5. 项目财务流水",
                "6. 票据索引",
                "7. 联系人与随手记",
                "8. 照片页",
                "9. 签字页"
            ]
            for item in tocItems {
                tocY = drawPDFText(item, at: CGPoint(x: margin, y: tocY + 6), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            }
            _ = drawPDFText("附: 材料 \(materials.count) 条 · 人工 \(labor.count) 条 · 待办 \(todos.count) 条 · 图纸 \(drawings.count) 份", at: CGPoint(x: margin, y: tocY + 16), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))

            // 3. 报价表
            let quoteColumns: [(title: String, width: CGFloat)] = [
                ("项目", 140), ("版本", 44), ("状态", 48), ("数量", 44), ("单价", 62), ("金额", 74), ("确认日期", 74), ("备注", 73)
            ]
            var quoteRows = quotes.map { item in
                [
                    item.name,
                    item.versionName,
                    item.status,
                    "\(item.quantity)\(item.unit)",
                    money(number(item.unitPrice)),
                    money(quoteGrandTotal(item)),
                    item.customerConfirmedDate.isEmpty ? "-" : item.customerConfirmedDate,
                    item.notes
                ]
            }
            if quoteRows.isEmpty {
                quoteRows = [["暂无报价", "-", "-", "-", "-", "-", "-", "-"]]
            }
            var quoteIndex = 0
            while quoteIndex < quoteRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText("报价表", at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: quoteColumns, startX: margin, y: tableY + 6, height: 24)
                while quoteIndex < quoteRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: quoteRows[quoteIndex], columns: quoteColumns, startX: margin, y: tableY, height: 24)
                    quoteIndex += 1
                }
                if quoteIndex == quoteRows.count {
                    _ = drawPDFText("报价合计: \(money(quoteTotal))", at: CGPoint(x: margin, y: tableY + 12), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 12))
                }
            }

            // 4. 日志表
            let logColumns: [(title: String, width: CGFloat)] = [
                ("日期", 72), ("天气", 44), ("人数", 44), ("施工内容", 248), ("照片数", 44), ("确认人", 74)
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
                logRows = [["暂无日志", "-", "-", "-", "-", "-"]]
            }
            var logIndex = 0
            while logIndex < logRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText("日志表", at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: logColumns, startX: margin, y: tableY + 6, height: 24)
                while logIndex < logRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: logRows[logIndex], columns: logColumns, startX: margin, y: tableY, height: 24)
                    logIndex += 1
                }
            }

            // 5. 项目财务流水
            let financeColumns: [(title: String, width: CGFloat)] = [
                ("日期", 76), ("收支", 44), ("分类", 60), ("金额", 70), ("对方", 110), ("票号", 90), ("票据", 48), ("备注", 97)
            ]
            var financeRows = financialRecords.sorted(by: { $0.date > $1.date }).map { row in
                [
                    row.date,
                    row.direction,
                    row.category,
                    money(number(row.amount)),
                    row.counterparty,
                    row.invoiceNumber,
                    "\(row.linkedDocumentIds.count)",
                    row.note
                ]
            }
            if financeRows.isEmpty {
                financeRows = [["暂无财务记录", "-", "-", "-", "-", "-", "-", "-"]]
            }
            var financeIndex = 0
            while financeIndex < financeRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText("项目财务流水", at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                tableY = drawPDFTableHeader(columns: financeColumns, startX: margin, y: tableY + 6, height: 24)
                while financeIndex < financeRows.count {
                    if tableY > page.height - 64 { break }
                    tableY = drawPDFTableRow(values: financeRows[financeIndex], columns: financeColumns, startX: margin, y: tableY, height: 24)
                    financeIndex += 1
                }
            }

            // 6. 票据索引与附件页
            let docColumns: [(title: String, width: CGFloat)] = [
                ("名称", 170), ("类型", 84), ("页数", 48), ("金额", 72), ("时间", 106), ("备注", 79)
            ]
            var docRows = documents.sorted(by: { $0.createdAt > $1.createdAt }).map { doc in
                [
                    doc.title,
                    doc.category,
                    "\(doc.pageCount)",
                    money(number(doc.amount)),
                    doc.createdAt,
                    doc.note
                ]
            }
            if docRows.isEmpty {
                docRows = [["暂无票据资料", "-", "-", "-", "-", "-"]]
            }
            var docIndex = 0
            while docIndex < docRows.count {
                context.beginPage()
                var tableY: CGFloat = 48
                tableY = drawPDFText("票据索引", at: CGPoint(x: margin, y: tableY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
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
                y = drawPDFText("票据附件页", at: CGPoint(x: margin, y: y), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
                _ = drawPDFText("本交付包包含 \(documents.count) 份票据/资料索引，原始文件已随 ZIP 打包，可在“01-票据原件”目录查看。", at: CGPoint(x: margin, y: y + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            }

            // 7. 联系人与随手记
            context.beginPage()
            var contactY: CGFloat = 48
            contactY = drawPDFText("联系人", at: CGPoint(x: margin, y: contactY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
            if contacts.isEmpty {
                contactY = drawPDFText("暂无联系人", at: CGPoint(x: margin, y: contactY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            } else {
                for contact in contacts.prefix(18) {
                    let line = "\(contact.name)  \(contact.role)  \(contact.company)  \(contact.phone)"
                    contactY = drawPDFText(line, at: CGPoint(x: margin, y: contactY + 6), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
                }
            }
            contactY = drawPDFText("随手记", at: CGPoint(x: margin, y: contactY + 20), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 17))
            if quickNotes.isEmpty {
                _ = drawPDFText("暂无随手记", at: CGPoint(x: margin, y: contactY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 12))
            } else {
                var noteY = contactY
                for note in quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).prefix(14) {
                    if noteY > page.height - 88 {
                        context.beginPage()
                        noteY = 48
                    }
                    let content = QuickNoteText.displayContent(for: note)
                    let attachmentText = QuickNoteText.attachmentSummary(note.attachments)
                    let line = "\(note.createdAt)  \(content)\(attachmentText.isEmpty ? "" : "  附件: \(attachmentText)")"
                    noteY = drawPDFText(line, at: CGPoint(x: margin, y: noteY + 8), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 11))
                }
            }

            // 8. 照片页
            drawPhotoWallPages(
                title: "\(project.name)-照片页",
                items: photoItems,
                context: context,
                page: page,
                margin: margin
            )

            // 9. 签字页
            context.beginPage()
            var signY: CGFloat = 120
            signY = drawPDFText("签字确认页", at: CGPoint(x: margin, y: signY), maxWidth: maxWidth, font: UIFont.boldSystemFont(ofSize: 20), alignment: .center) + 28
            signY = drawPDFText("项目名称: \(project.name)", at: CGPoint(x: margin, y: signY), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText("客户确认: ____________________", at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText("项目负责人: ____________________", at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            signY = drawPDFText("监理/验收: ____________________", at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
            _ = drawPDFText("日期: ____________________", at: CGPoint(x: margin, y: signY + 26), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13))
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
                try? zip.close()
                try? FileManager.default.removeItem(at: packageURL)
            }
        }

        let folder = safeZipName(project.name)
        let pdfName = "\(folder)_项目交付包.pdf"
        var stagedRawBytes = 0
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: packagePDF,
            path: "\(folder)/00-交付包/\(pdfName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress("写入交付包 PDF")

        let readme = [
            "项目交付包",
            "项目: \(project.name)",
            "导出时间: \(Formatters.now())",
            "内容:",
            "1. 00-交付包/\(pdfName)",
            "2. 01-票据原件/ (票据/资料原始文件)",
            "3. 02-图纸原件/ (图纸原始文件，含 PDF/DWG/DXF)",
            "4. 03-现场照片原件/ (日志和整改照片文件)",
            "5. 04-随手记/ (清单和原始附件)",
            "6. 05-联系人/ (联系人清单)"
        ].joined(separator: "\n")
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(readme.utf8),
            path: "\(folder)/README.txt",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress("写入说明文件")

        for document in documents {
            try failIfCancelled()
            let fileBytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            let sourceURL = ProjectDocumentStorage.fileURL(for: document.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                reportProgress("检查票据 \(document.title)")
                continue
            }
            let title = safeZipName(document.title)
            let fileName = document.fileName.lowercased().hasSuffix(".pdf") ? document.fileName : "\(document.fileName).pdf"
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/01-票据原件/\(title)-\(fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress("打包票据 \(document.title)")
        }

        for drawing in drawings {
            try failIfCancelled()
            let fileBytes = DrawingStorage.fileSize(for: drawing.fileName)
            let sourceURL = DrawingStorage.fileURL(for: drawing.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                reportProgress("检查图纸 \(drawing.name)")
                continue
            }
            let name = safeZipName(drawing.name)
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/02-图纸原件/\(name)-\(drawing.fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress("打包图纸 \(drawing.name)")
        }

        for log in logs {
            for photo in log.photoAttachments {
                try failIfCancelled()
                let fileBytes = PhotoStorage.fileSize(for: photo.fileName)
                let sourceURL = PhotoStorage.fileURL(for: photo.fileName)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    reportProgress("检查照片 \(log.date) \(photo.tag)")
                    continue
                }
                let tag = safeZipName(photo.tag)
                try addStoredFileToProjectPackageZip(
                    zip: &zip,
                    sourceFileURL: sourceURL,
                    fileBytes: fileBytes,
                    path: "\(folder)/03-现场照片原件/\(log.date)-\(tag)-\(photo.fileName)",
                    stagedRawBytes: &stagedRawBytes
                )
                reportProgress("打包照片 \(log.date) \(photo.tag)")
            }
        }

        if !quickNotes.isEmpty {
            let lines = quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).map { note in
                let content = QuickNoteText.displayContent(for: note)
                let attachmentText = QuickNoteText.attachmentSummary(note.attachments)
                return "\(note.createdAt)\t\(content)\t\(attachmentText)"
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(lines.joined(separator: "\n").utf8),
                path: "\(folder)/04-随手记/随手记清单.tsv",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress("写入随手记清单")
            for note in quickNotes {
                for attachment in note.attachments {
                    try failIfCancelled()
                    let fileBytes = QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
                    let sourceURL = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        reportProgress("检查随手记附件 \(note.title.isEmpty ? note.createdAt : note.title)")
                        continue
                    }
                    let title = safeZipName(note.title.isEmpty ? "随手记" : note.title)
                    let kind = safeZipName(attachment.attachmentKind.title)
                    let created = safeZipName(note.createdAt)
                    try addStoredFileToProjectPackageZip(
                        zip: &zip,
                        sourceFileURL: sourceURL,
                        fileBytes: fileBytes,
                        path: "\(folder)/04-随手记/\(kind)/\(created)-\(title)-\(attachment.fileName)",
                        stagedRawBytes: &stagedRawBytes
                    )
                    reportProgress("打包随手记附件 \(note.title.isEmpty ? note.createdAt : note.title)")
                }
            }
        }

        if !contacts.isEmpty {
            let header = "姓名\t角色\t公司/班组\t电话\t备注"
            let rows = contacts.sorted { $0.name < $1.name }.map {
                "\($0.name)\t\($0.role)\t\($0.company)\t\($0.phone)\t\($0.note)"
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + rows).joined(separator: "\n").utf8),
                path: "\(folder)/05-联系人/联系人清单.tsv",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress("写入联系人清单")
        }

        let finishedURL = try zip.finish()
        writerFinished = true
        return finishedURL
    }

    private static func addGeneratedFileToProjectPackageZip(
        zip: inout StreamingZipArchiveWriter,
        data: Data,
        path: String,
        stagedRawBytes: inout Int
    ) throws {
        try zip.addFile(path: path, data: data)
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
        try zip.addFile(path: path, sourceFileURL: sourceFileURL)
        stagedRawBytes += resolvedFileBytes
    }

    static func quoteLineTotal(_ item: QuoteItem) -> Double {
        (Double(item.unitPrice) ?? 0) * (Double(item.quantity) ?? 0)
    }

    static func materialLineTotal(_ item: MaterialItem) -> Double {
        number(item.quantity) * number(item.unitPrice)
    }

    static func laborHours(_ record: LaborRecord) -> Double {
        let workers = number(record.workers)
        let hours = number(record.hours)
        return workers > 0 ? workers * hours : hours
    }

    static func laborLineTotal(_ record: LaborRecord) -> Double {
        laborHours(record) * number(record.unitRate)
    }

    static func number(_ text: String) -> Double {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) else { return 0 }
        return Double(normalized[range]) ?? 0
    }

    static func quoteGrandTotal(_ item: QuoteItem) -> Double {
        let line = quoteLineTotal(item)
        let tax = line * ((Double(item.taxRate) ?? 0) / 100)
        let discount = line * ((Double(item.discountRate) ?? 0) / 100)
        return line + tax - discount
    }

    static func money(_ value: Double) -> String {
        "¥" + String(format: "%.2f", value)
    }

    private static func safeZipName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        let compact = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "未命名项目" : compact
    }

    private static func estimatedProjectPackageStepCount(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        contacts: [ProjectContact]
    ) -> Int {
        var total = 2 // PDF + README
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
        margin: CGFloat
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
            _ = drawPDFText("生成时间: \(Formatters.now())", at: CGPoint(x: margin, y: 58), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 10), alignment: .center)
            if sortedItems.isEmpty {
                _ = drawPDFText("暂无照片", at: CGPoint(x: margin, y: 120), maxWidth: maxWidth, font: UIFont.systemFont(ofSize: 13), alignment: .center)
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
                    if let image = PhotoStorage.thumbnail(for: item.fileName) {
                        image.draw(in: imageRect)
                    } else {
                        UIColor.secondarySystemFill.setFill()
                        UIBezierPath(rect: imageRect).fill()
                    }
                    let titleText = "\(item.date) · \(item.projectName)"
                    _ = drawPDFText(titleText, at: CGPoint(x: x + 8, y: y + 160), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText("标签: \(item.tag)", at: CGPoint(x: x + 8, y: y + 176), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    _ = drawPDFText(item.note.isEmpty ? "备注: -" : "备注: \(item.note)", at: CGPoint(x: x + 8, y: y + 192), maxWidth: cardWidth - 16, font: UIFont.systemFont(ofSize: 10))
                    index += 1
                }
            }
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

    private static func escapeHTML(_ text: String) -> String {
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
        if names.isEmpty { return "未指定" }
        if names.count == 1 { return names.first ?? "未指定" }
        return "多个项目"
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

    private static func fmtSection(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static func phaseName(_ index: Int) -> String {
        switch index {
        case 0: return "A"
        case 1: return "B"
        case 2: return "C"
        default: return ""
        }
    }

    private static func evaluateLightingPlan(_ plan: LightingCircuitPlan) -> LightingPlanEvaluation? {
        guard let voltage = Double(plan.voltage), voltage > 0,
              let powerFactor = Double(plan.powerFactor), powerFactor > 0, powerFactor <= 1,
              let demandFactor = Double(plan.demandFactor), demandFactor > 0,
              let breakerFactor = Double(plan.breakerFactor), breakerFactor > 0,
              let wireFactor = Double(plan.wireFactor), wireFactor > 0 else {
            return nil
        }

        let rows = plan.loads.compactMap { load -> LightingPlanRow? in
            let installedPower = Double(load.powerKW) ?? 0
            guard installedPower > 0 else { return nil }
            let demandPower = installedPower * demandFactor
            let current = EngineeringCalculations.circuitCurrent(
                powerKW: demandPower,
                voltage: voltage,
                powerFactor: powerFactor,
                isThreePhase: plan.supplyType == .threePhase
            )
            let breaker = EngineeringCalculations.recommendedBreaker(current: current, safetyFactor: breakerFactor)
            let section = EngineeringCalculations.recommendedWireSectionByAmpacity(current: current, isCopper: plan.isCopper, safetyFactor: wireFactor)
            return LightingPlanRow(
                name: load.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名回路" : load.name,
                installedPowerKW: installedPower,
                demandPowerKW: demandPower,
                currentA: current,
                breakerA: breaker,
                wireSectionText: section.map { fmtSection($0) } ?? "超规格"
            )
        }

        guard !rows.isEmpty else { return nil }
        var enrichedRows = rows
        var phaseTotals: [Double]? = nil
        var imbalance: Double? = nil

        if plan.supplyType == .threePhase {
            let assignments = EngineeringCalculations.assignThreePhases(currents: rows.map(\.currentA))
            for index in assignments.indices where index < enrichedRows.count {
                enrichedRows[index].phaseName = phaseName(assignments[index])
            }
            let totals = EngineeringCalculations.phaseTotals(currents: rows.map(\.currentA), assignments: assignments)
            phaseTotals = totals
            imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
        }

        return LightingPlanEvaluation(
            voltage: voltage,
            powerFactor: powerFactor,
            demandFactor: demandFactor,
            rows: enrichedRows,
            totalInstalledPowerKW: rows.reduce(0) { $0 + $1.installedPowerKW },
            totalDemandPowerKW: rows.reduce(0) { $0 + $1.demandPowerKW },
            totalCurrentA: rows.reduce(0) { $0 + $1.currentA },
            phaseTotals: phaseTotals,
            imbalancePercent: imbalance
        )
    }

    private static func pdfData(lines: [String]) -> Data {
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
                let font = line.isEmpty ? UIFont.systemFont(ofSize: 6) : UIFont.systemFont(ofSize: line.hasSuffix("明细") || line.hasSuffix("记录") || line.hasSuffix("任务") || line.hasSuffix("清单") ? 15 : 11, weight: line.hasSuffix("明细") || line.hasSuffix("记录") || line.hasSuffix("任务") || line.hasSuffix("清单") ? .semibold : .regular)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attr = NSAttributedString(string: line, attributes: [.font: font, .paragraphStyle: paragraph])
                let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                attr.draw(with: CGRect(x: margin, y: y, width: maxWidth, height: ceil(rect.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += max(16, ceil(rect.height) + 6)
            }
        }
    }
}

private struct LightingPlanRow {
    var name: String
    var installedPowerKW: Double
    var demandPowerKW: Double
    var currentA: Double
    var breakerA: Int
    var wireSectionText: String
    var phaseName: String = ""
}

private struct LightingPlanEvaluation {
    var voltage: Double
    var powerFactor: Double
    var demandFactor: Double
    var rows: [LightingPlanRow]
    var totalInstalledPowerKW: Double
    var totalDemandPowerKW: Double
    var totalCurrentA: Double
    var phaseTotals: [Double]?
    var imbalancePercent: Double?
}
