package com.chengjinfang.sitekeeper.delivery

import android.content.Context
import android.net.Uri
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal fun defaultProjectDeliveryFileName(
    projectName: String,
    timestamp: String = SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(Date())
): String =
    "${safeProjectFileName(projectName)}-交付报告-$timestamp.md"

internal suspend fun writeProjectDeliveryReportToUri(
    context: Context,
    uri: Uri,
    detail: ProjectDetail
) {
    withContext(Dispatchers.IO) {
        val report = buildProjectDeliveryMarkdown(detail)
        val rawOutput = context.contentResolver.openOutputStream(uri)
            ?: error("无法打开导出文件")
        BufferedOutputStream(rawOutput).use { output ->
            output.write(report.toByteArray(Charsets.UTF_8))
        }
    }
}

internal fun buildProjectDeliveryMarkdown(
    detail: ProjectDetail,
    exportedAt: String = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA).format(Date())
): String {
    val methodTitleById = detail.constructionMethods.associate { method ->
        method.id to method.displayTitle
    }
    val todoPhotoCount = detail.siteTodos.sumOf { todo ->
        listOf(todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName)
            .count { !it.isNullOrBlank() }
    }
    val dailyPhotoCount = detail.dailyLogs.sumOf { it.photoCount }
    val attachedDocumentCount = detail.documents.count { it.localUri.isNotBlank() }
    val attachedDrawingCount = detail.drawings.count { it.localUri.isNotBlank() }
    val linkedMethodCount = linkedConstructionMethodCount(detail)
    val totalRecordCount = detail.dailyLogs.size +
        detail.siteTodos.size +
        detail.progressTasks.size +
        detail.financialRecords.size +
        detail.materialItems.size +
        detail.contacts.size +
        detail.documents.size +
        detail.drawings.size +
        detail.quoteItems.size +
        detail.laborRecords.size +
        detail.warehouseMovements.size

    return buildString {
        appendLine("# 项目交付报告")
        appendLine()
        appendLine("## 项目概况")
        appendLine("- 导出时间：${exportedAt.ifBlank { "-" }}")
        appendLine("- 项目名称：${detail.project.name.ifBlank { "-" }}")
        appendLine("- 项目地点：${detail.project.location.ifBlank { "-" }}")
        appendLine("- 项目状态：${detail.project.status.ifBlank { "-" }}")
        appendLine("- 项目负责人：${detail.project.managerName.ifBlank { "-" }}")
        appendLine("- 计划完工：${detail.project.expectedEndDate.ifBlank { "-" }}")
        appendLine()

        appendLine("## 交付摘要")
        appendLine("- 合同金额：${detail.project.contractAmount.ifBlank { "-" }}")
        appendLine("- 已收金额：${detail.project.paidAmount.ifBlank { "-" }}")
        appendLine("- 收款状态：${detail.project.paymentStatus.ifBlank { "-" }}")
        appendLine("- 记录合计：$totalRecordCount 条")
        appendLine("- 资料附件：$attachedDocumentCount/${detail.documents.size} 份")
        appendLine("- 图纸附件：$attachedDrawingCount/${detail.drawings.size} 份")
        appendLine("- 现场照片：${dailyPhotoCount + todoPhotoCount} 张")
        appendLine("- 关联工艺：$linkedMethodCount 项")
        appendLine("- 风险提示：${riskSummaryText(detail)}")
        appendLine()

        appendReportSection(
            title = "关键时间线",
            items = deliveryTimelineEntries(detail, methodTitleById),
            emptyText = "暂无可交付记录"
        ) { entry ->
            reportLine(entry.date, entry.kind, listOf(entry.title, entry.meta).joinFilled("；"))
        }

        appendReportSection(
            title = "联系人",
            items = detail.contacts.sortedBy { it.name },
            emptyText = "暂无联系人"
        ) { contact ->
            reportLine(
                contact.name.ifBlank { "未命名联系人" },
                contact.role,
                listOf(contact.company, contact.phone, contact.note).joinFilled("；")
            )
        }

        appendReportSection(
            title = "项目资料",
            items = detail.documents.sortedByDescending { it.createdAt },
            emptyText = "暂无项目资料"
        ) { document ->
            val fileState = when {
                document.localUri.isNotBlank() -> "已归档原文件"
                document.fileName.isNotBlank() -> "仅登记文件名"
                else -> "未附原文件"
            }
            reportLine(
                document.createdAt,
                document.title.ifBlank { "未命名资料" },
                listOf(
                    document.category,
                    document.fileName,
                    document.fileType,
                    document.pageCount.takeIf { it > 0 }?.let { "$it 页" },
                    document.amount.takeIf(String::isNotBlank)?.let { "金额 $it" },
                    fileState,
                    methodMeta(document.linkedConstructionMethodIds, methodTitleById),
                    document.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "图纸版本",
            items = detail.drawings.sortedWith(compareByDescending<ProjectDrawingSummary> { it.importedAt }.thenBy { it.name }),
            emptyText = "暂无项目图纸"
        ) { drawing ->
            reportLine(
                drawing.importedAt,
                drawing.name.ifBlank { "未命名图纸" },
                listOf(
                    drawing.fileName,
                    drawing.fileType,
                    drawing.version.takeIf(String::isNotBlank)?.let { "版本 $it" },
                    if (drawing.isCurrentVersion) "当前版" else "历史版",
                    drawing.issueStatus,
                    drawing.relatedLogDate.takeIf(String::isNotBlank)?.let { "关联日志 $it" },
                    if (drawing.localUri.isNotBlank()) "已归档原文件" else "未附原文件",
                    drawing.issueNote,
                    drawing.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "进度任务",
            items = detail.progressTasks.sortedBy { it.dueDate },
            emptyText = "暂无进度任务"
        ) { task ->
            reportLine(
                task.dueDate,
                task.title.ifBlank { "未命名进度" },
                listOf(
                    task.startDate.takeIf(String::isNotBlank)?.let { "开始 $it" },
                    "完成 ${progressPercent(task.completion)}",
                    task.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "施工日志",
            items = detail.dailyLogs.sortedByDescending { it.date },
            emptyText = "暂无施工日志"
        ) { log ->
            reportLine(
                log.date,
                log.content.ifBlank { "施工日志" },
                listOf(
                    log.weather,
                    log.workers.takeIf(String::isNotBlank)?.let { "$it 人" },
                    log.materials.takeIf(String::isNotBlank)?.let { "材料 $it" },
                    log.safety.takeIf(String::isNotBlank)?.let { "安全 $it" },
                    log.tomorrowPlan.takeIf(String::isNotBlank)?.let { "明日 $it" },
                    log.photoCount.takeIf { it > 0 }?.let { "$it 张照片" },
                    methodMeta(log.linkedConstructionMethodIds, methodTitleById)
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "待办整改",
            items = detail.siteTodos.sortedBy { it.dueDate },
            emptyText = "暂无待办整改"
        ) { todo ->
            val photoText = listOf(
                todo.rectificationBeforePhotoFileName?.takeIf(String::isNotBlank)?.let { "整改前照片" },
                todo.rectificationAfterPhotoFileName?.takeIf(String::isNotBlank)?.let { "整改后照片" }
            ).filterNotNull().joinFilled("、")
            reportLine(
                todo.dueDate,
                todo.title.ifBlank { "未命名待办" },
                listOf(
                    if (todo.isDone) "已完成" else "未完成",
                    todo.owner.takeIf(String::isNotBlank)?.let { "责任 $it" },
                    todo.priority,
                    todo.issueType,
                    photoText,
                    methodMeta(todo.linkedConstructionMethodIds, methodTitleById),
                    todo.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "收支记录",
            items = detail.financialRecords.sortedByDescending { it.date },
            emptyText = "暂无收支记录"
        ) { record ->
            reportLine(
                record.date,
                "${record.direction.ifBlank { "收支" }} ${record.amount}".trim(),
                listOf(
                    record.category,
                    record.counterparty,
                    record.status,
                    record.dueDate.takeIf(String::isNotBlank)?.let { "到期 $it" },
                    record.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "材料与采购",
            items = detail.materialItems.sortedBy { it.arrivalDate },
            emptyText = "暂无材料记录"
        ) { material ->
            reportLine(
                material.arrivalDate,
                material.name.ifBlank { "未命名材料" },
                listOf(
                    material.specification,
                    "${material.quantity} ${material.unit}".trim(),
                    material.unitPrice.takeIf(String::isNotBlank)?.let { "单价 $it" },
                    material.supplier,
                    material.purchaseStatus
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "报价项",
            items = detail.quoteItems.sortedBy { it.name },
            emptyText = "暂无报价项"
        ) { quote ->
            reportLine(
                quote.name.ifBlank { "未命名报价" },
                quote.status,
                listOf(
                    quote.versionName,
                    "${quote.quantity} ${quote.unit}".trim(),
                    quote.unitPrice.takeIf(String::isNotBlank)?.let { "单价 $it" },
                    quote.contractAmount.takeIf(String::isNotBlank)?.let { "合同 $it" },
                    quote.customerConfirmedDate.takeIf(String::isNotBlank)?.let { "确认 $it" },
                    quote.notes
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "人工记录",
            items = detail.laborRecords.sortedByDescending { it.date },
            emptyText = "暂无人工记录"
        ) { labor ->
            reportLine(
                labor.date,
                listOf(labor.workType, labor.teamName).joinFilled(" · ").ifBlank { "人工记录" },
                listOf(
                    labor.workers.takeIf(String::isNotBlank)?.let { "$it 人" },
                    labor.hours.takeIf(String::isNotBlank)?.let { "$it 工日" },
                    labor.unitRate.takeIf(String::isNotBlank)?.let { "单价 $it" },
                    if (labor.isSettled) "已结算" else "未结算",
                    labor.note
                ).joinFilled("；")
            )
        }

        appendReportSection(
            title = "仓库流水",
            items = detail.warehouseMovements.sortedByDescending { it.date },
            emptyText = "暂无仓库流水"
        ) { movement ->
            reportLine(
                movement.date,
                "${movement.movementType.ifBlank { "出入库" }} ${movement.materialName}".trim(),
                listOf(
                    movement.specification,
                    "${movement.quantity} ${movement.unit}".trim(),
                    movement.counterparty,
                    movement.handler.takeIf(String::isNotBlank)?.let { "经手 $it" },
                    movement.linkedDocumentCount.takeIf { it > 0 }?.let { "$it 个单据" },
                    movement.note
                ).joinFilled("；")
            )
        }
    }
}

private data class DeliveryTimelineEntry(
    val date: String,
    val kind: String,
    val title: String,
    val meta: String
)

private fun deliveryTimelineEntries(
    detail: ProjectDetail,
    methodTitleById: Map<String, String>
): List<DeliveryTimelineEntry> =
    buildList {
        detail.dailyLogs.forEach { log ->
            add(
                DeliveryTimelineEntry(
                    date = log.date,
                    kind = "施工日志",
                    title = log.content.ifBlank { "施工日志" },
                    meta = listOf(
                        log.weather,
                        log.photoCount.takeIf { it > 0 }?.let { "$it 张照片" },
                        methodMeta(log.linkedConstructionMethodIds, methodTitleById)
                    ).joinFilled("；")
                )
            )
        }
        detail.siteTodos.forEach { todo ->
            add(
                DeliveryTimelineEntry(
                    date = todo.dueDate,
                    kind = "待办整改",
                    title = todo.title.ifBlank { "未命名待办" },
                    meta = listOf(
                        if (todo.isDone) "已完成" else "未完成",
                        todo.owner.takeIf(String::isNotBlank)?.let { "责任 $it" },
                        todo.priority,
                        methodMeta(todo.linkedConstructionMethodIds, methodTitleById)
                    ).joinFilled("；")
                )
            )
        }
        detail.progressTasks.forEach { task ->
            add(
                DeliveryTimelineEntry(
                    date = task.dueDate.ifBlank { task.startDate },
                    kind = "进度",
                    title = task.title.ifBlank { "未命名进度" },
                    meta = "完成 ${progressPercent(task.completion)}"
                )
            )
        }
        detail.financialRecords.forEach { record ->
            add(
                DeliveryTimelineEntry(
                    date = record.date.ifBlank { record.dueDate },
                    kind = record.direction.ifBlank { "收支" },
                    title = record.category.ifBlank { record.amount },
                    meta = listOf(record.amount, record.counterparty, record.status).joinFilled("；")
                )
            )
        }
        detail.materialItems.forEach { material ->
            add(
                DeliveryTimelineEntry(
                    date = material.arrivalDate,
                    kind = "材料",
                    title = material.name.ifBlank { "未命名材料" },
                    meta = listOf(material.specification, material.purchaseStatus).joinFilled("；")
                )
            )
        }
        detail.documents.forEach { document ->
            add(
                DeliveryTimelineEntry(
                    date = document.createdAt,
                    kind = "资料",
                    title = document.title.ifBlank { "未命名资料" },
                    meta = listOf(document.category, document.fileName, methodMeta(document.linkedConstructionMethodIds, methodTitleById)).joinFilled("；")
                )
            )
        }
        detail.drawings.forEach { drawing ->
            add(
                DeliveryTimelineEntry(
                    date = drawing.importedAt.ifBlank { drawing.relatedLogDate },
                    kind = "图纸",
                    title = drawing.name.ifBlank { "未命名图纸" },
                    meta = listOf(drawing.version, if (drawing.isCurrentVersion) "当前版" else "历史版", drawing.issueStatus).joinFilled("；")
                )
            )
        }
        detail.quoteItems.forEach { quote ->
            add(
                DeliveryTimelineEntry(
                    date = quote.customerConfirmedDate,
                    kind = "报价",
                    title = quote.name.ifBlank { "未命名报价" },
                    meta = listOf(quote.versionName, quote.status, quote.contractAmount).joinFilled("；")
                )
            )
        }
        detail.laborRecords.forEach { labor ->
            add(
                DeliveryTimelineEntry(
                    date = labor.date,
                    kind = "人工",
                    title = listOf(labor.workType, labor.teamName).joinFilled(" · ").ifBlank { "人工记录" },
                    meta = listOf(labor.workers.takeIf(String::isNotBlank)?.let { "$it 人" }, if (labor.isSettled) "已结算" else "未结算").joinFilled("；")
                )
            )
        }
        detail.warehouseMovements.forEach { movement ->
            add(
                DeliveryTimelineEntry(
                    date = movement.date,
                    kind = movement.movementType.ifBlank { "仓库" },
                    title = movement.materialName.ifBlank { "仓库流水" },
                    meta = listOf(movement.specification, "${movement.quantity} ${movement.unit}".trim(), movement.handler).joinFilled("；")
                )
            )
        }
    }
        .sortedWith(
            compareByDescending<DeliveryTimelineEntry> { it.date }
                .thenBy { it.kind }
                .thenBy { it.title }
        )

private fun <T> StringBuilder.appendReportSection(
    title: String,
    items: List<T>,
    emptyText: String,
    lineText: (T) -> String
) {
    appendLine("## $title")
    if (items.isEmpty()) {
        appendLine("- $emptyText")
    } else {
        items.forEach { item ->
            appendLine("- ${lineText(item)}")
        }
    }
    appendLine()
}

private fun linkedConstructionMethodCount(detail: ProjectDetail): Int =
    buildSet {
        detail.dailyLogs.flatMap { it.linkedConstructionMethodIds }.forEach(::add)
        detail.siteTodos.flatMap { it.linkedConstructionMethodIds }.forEach(::add)
        detail.documents.flatMap { it.linkedConstructionMethodIds }.forEach(::add)
    }.size

private fun riskSummaryText(detail: ProjectDetail): String {
    val riskItems = listOfNotNull(
        detail.project.overdueTodoCount.takeIf { it > 0 }?.let { "逾期待办 $it 项" },
        detail.project.dueIncomeCount.takeIf { it > 0 }?.let { "到期待收 $it 项" },
        detail.project.unarrivedMaterialCount.takeIf { it > 0 }?.let { "未到货材料 $it 项" }
    )
    return riskItems.ifEmpty { listOf("暂无待处理风险") }.joinToString("；")
}

private fun methodMeta(
    methodIds: List<String>,
    methodTitleById: Map<String, String>
): String =
    methodIds
        .mapNotNull { methodTitleById[it]?.takeIf(String::isNotBlank) }
        .distinct()
        .joinFilled("、")
        .takeIf(String::isNotBlank)
        ?.let { "工艺：$it" }
        .orEmpty()

private fun reportLine(
    first: String,
    second: String,
    third: String
): String =
    listOf(first, second, third)
        .joinFilled("｜")
        .ifBlank { "-" }

private fun List<String?>.joinFilled(separator: String): String =
    mapNotNull { item ->
        item
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            ?.takeIf(String::isNotBlank)
    }.joinToString(separator)

private fun progressPercent(completion: Double): String =
    "${(completion.coerceIn(0.0, 1.0) * 100).toInt()}%"

internal fun safeProjectFileName(projectName: String): String =
    projectName
        .trim()
        .replace(Regex("[\\\\/:*?\"<>|\\s]+"), "-")
        .trim('-')
        .ifBlank { "sitekeeper-project" }
