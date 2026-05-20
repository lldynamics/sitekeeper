package com.chengjinfang.sitekeeper.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.chengjinfang.sitekeeper.calculator.CalculatorResult
import com.chengjinfang.sitekeeper.calculator.ConcreteGrade
import com.chengjinfang.sitekeeper.calculator.UnitCategory
import com.chengjinfang.sitekeeper.calculator.UnitDefinition
import com.chengjinfang.sitekeeper.calculator.WireMaterial
import com.chengjinfang.sitekeeper.calculator.calculateConcrete
import com.chengjinfang.sitekeeper.calculator.calculateCurrent
import com.chengjinfang.sitekeeper.calculator.calculateTile
import com.chengjinfang.sitekeeper.calculator.calculateUnitConversion
import com.chengjinfang.sitekeeper.calculator.calculateVoltageDrop
import com.chengjinfang.sitekeeper.calculator.calculateWallArea
import com.chengjinfang.sitekeeper.calculator.parseCalculatorNumber
import com.chengjinfang.sitekeeper.backup.DocumentArchiveUsage
import com.chengjinfang.sitekeeper.backup.archiveDocumentFile
import com.chengjinfang.sitekeeper.backup.archiveDrawingFile
import com.chengjinfang.sitekeeper.backup.archivePhotoFile
import com.chengjinfang.sitekeeper.backup.archiveQuickNoteAttachmentFile
import com.chengjinfang.sitekeeper.backup.canOpenLocalDocument
import com.chengjinfang.sitekeeper.backup.canOpenLocalPhoto
import com.chengjinfang.sitekeeper.backup.cleanupOrphanLocalArchives
import com.chengjinfang.sitekeeper.backup.cleanupOrphanProjectDocumentArchives
import com.chengjinfang.sitekeeper.backup.defaultBackupPackageFileName
import com.chengjinfang.sitekeeper.backup.deleteDrawingArchive
import com.chengjinfang.sitekeeper.backup.deletePhotoArchive
import com.chengjinfang.sitekeeper.backup.deleteProjectDocumentArchive
import com.chengjinfang.sitekeeper.backup.deleteQuickNoteAttachmentArchive
import com.chengjinfang.sitekeeper.backup.documentArchiveUsageText
import com.chengjinfang.sitekeeper.backup.localDataHealth
import com.chengjinfang.sitekeeper.backup.LocalDataHealthSnapshot
import com.chengjinfang.sitekeeper.backup.localDataHealthSummaryText
import com.chengjinfang.sitekeeper.backup.openLocalPhoto
import com.chengjinfang.sitekeeper.backup.openLocalDocument
import com.chengjinfang.sitekeeper.backup.openLocalQuickNoteAttachment
import com.chengjinfang.sitekeeper.backup.projectDocumentArchiveUsage
import com.chengjinfang.sitekeeper.backup.readBackupImportFromUri
import com.chengjinfang.sitekeeper.backup.restoreBackupPackageFiles
import com.chengjinfang.sitekeeper.backup.writeBackupPackageToUri
import com.chengjinfang.sitekeeper.database.contact.ProjectContactSummary
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentSummary
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.labor.LaborRecordSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodSummary
import com.chengjinfang.sitekeeper.database.project.BackupImportMode
import com.chengjinfang.sitekeeper.database.project.BackupImportPreview
import com.chengjinfang.sitekeeper.database.project.ChecklistTodoSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import com.chengjinfang.sitekeeper.database.project.ProjectSummary
import com.chengjinfang.sitekeeper.database.project.QuickNoteAttachmentSummary
import com.chengjinfang.sitekeeper.database.project.QuickNoteSummary
import com.chengjinfang.sitekeeper.database.project.SiteTodoPhotoTarget
import com.chengjinfang.sitekeeper.delivery.defaultProjectDeliveryPackageFileName
import com.chengjinfang.sitekeeper.delivery.projectDeliveryPackagePreflight
import com.chengjinfang.sitekeeper.delivery.ProjectDeliveryPackagePreflight
import com.chengjinfang.sitekeeper.delivery.projectDeliveryPackagePreflightSummaryText
import com.chengjinfang.sitekeeper.delivery.writeProjectDeliveryPackageToUri
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskSummary
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale



@Composable
internal fun ProjectMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
internal fun ProjectRiskLine(project: ProjectSummary) {
    val riskText = projectRiskText(project)
    if (riskText.isBlank()) {
        return
    }

    Text(
        text = riskText,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.error,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
internal fun CompactEmptyText(text: String) {
    Text(
        text = text,
        modifier = Modifier.padding(vertical = 8.dp),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

internal fun amountValue(text: String): Double =
    text
        .replace(",", "")
        .trim()
        .toDoubleOrNull()
        ?: 0.0

internal fun moneyText(value: Double): String =
    if (value % 1.0 == 0.0) {
        String.format(Locale.US, "%.0f", value)
    } else {
        String.format(Locale.US, "%.2f", value)
    }

internal fun dataHealthBytesText(bytes: Long): String =
    when {
        bytes >= 1024L * 1024L * 1024L -> String.format(Locale.US, "%.1fGB", bytes / 1024.0 / 1024.0 / 1024.0)
        bytes >= 1024L * 1024L -> String.format(Locale.US, "%.1fMB", bytes / 1024.0 / 1024.0)
        bytes >= 1024L -> String.format(Locale.US, "%.1fKB", bytes / 1024.0)
        else -> "${bytes}B"
    }

internal fun progressPercentText(completion: Double): String =
    "${(completion.coerceIn(0.0, 1.0) * 100).toInt()}%"

internal fun quoteLineAmountText(quote: QuoteItemSummary): String {
    val amount = amountValue(quote.unitPrice) * amountValue(quote.quantity)
    return if (amount > 0.0) moneyText(amount) else "-"
}

internal fun quoteMetaText(quote: QuoteItemSummary): String =
    listOfNotNull(
        quote.versionName.takeIf(String::isNotBlank),
        quote.status.takeIf(String::isNotBlank),
        "${quote.quantity} ${quote.unit}".trim().takeIf(String::isNotBlank),
        quote.unitPrice.takeIf(String::isNotBlank)?.let { "单价 $it" },
        quote.customerConfirmedDate.takeIf(String::isNotBlank)?.let { "确认 $it" }
    ).joinToString(" · ")

internal fun laborTitleText(labor: LaborRecordSummary): String =
    listOf(labor.workType, labor.teamName)
        .filter(String::isNotBlank)
        .joinToString(" · ")
        .ifBlank { "人工记录" }

internal fun laborMetaText(labor: LaborRecordSummary): String =
    listOfNotNull(
        labor.date.takeIf(String::isNotBlank),
        labor.workers.takeIf(String::isNotBlank)?.let { "$it 人" },
        labor.hours.takeIf(String::isNotBlank)?.let { "$it 工日" },
        labor.unitRate.takeIf(String::isNotBlank)?.let { "单价 $it" }
    ).joinToString(" · ")

internal data class WarehouseStockLine(
    val name: String,
    val specification: String,
    val unit: String,
    val quantity: Double
)

internal fun warehouseStockLines(
    movements: List<ProjectWarehouseMovementSummary>
): List<WarehouseStockLine> =
    movements
        .groupBy { movement ->
            listOf(
                movement.materialName.trim(),
                movement.specification.trim(),
                movement.unit.trim()
            ).joinToString("|")
        }
        .map { (_, items) ->
            val first = items.first()
            val quantity = items.sumOf { movement ->
                val sign = if (movement.movementType == "出库") -1.0 else 1.0
                amountValue(movement.quantity) * sign
            }
            WarehouseStockLine(
                name = first.materialName.ifBlank { "未命名材料" },
                specification = first.specification,
                unit = first.unit.ifBlank { "件" },
                quantity = quantity
            )
        }
        .sortedWith(
            compareByDescending<WarehouseStockLine> { it.quantity < 0.0 }
                .thenBy { it.name }
        )

internal fun warehouseSignedQuantityText(movement: ProjectWarehouseMovementSummary): String {
    val prefix = if (movement.movementType == "出库") "-" else "+"
    return "$prefix${movement.quantity} ${movement.unit}".trim()
}

internal fun warehouseMetaText(movement: ProjectWarehouseMovementSummary): String =
    listOfNotNull(
        movement.movementType.takeIf(String::isNotBlank),
        movement.date.takeIf(String::isNotBlank),
        movement.specification.takeIf(String::isNotBlank),
        movement.counterparty.takeIf(String::isNotBlank),
        movement.handler.takeIf(String::isNotBlank)?.let { "经手 $it" },
        movement.linkedDocumentCount.takeIf { it > 0 }?.let { "$it 个单据" }
    ).joinToString(" · ")

internal fun nextMaterialPurchaseStatus(status: String): String =
    when (status) {
        "待采购" -> "已采购"
        "已采购" -> "已进场"
        "已进场" -> "待采购"
        else -> "已采购"
    }

internal fun importPreviewText(preview: BackupImportPreview): String =
    listOf(
        "项目 ${preview.projectCount}",
        "日志 ${preview.dailyLogCount}",
        "待办 ${preview.siteTodoCount}",
        "收支 ${preview.financialRecordCount}",
        "材料 ${preview.materialItemCount}",
        "随手记 ${preview.quickNoteCount}",
        "联系人 ${preview.projectContactCount}",
        "资料 ${preview.projectDocumentCount}",
        "进度 ${preview.progressTaskCount}",
        "图纸 ${preview.projectDrawingCount}",
        "报价 ${preview.quoteItemCount}",
        "人工 ${preview.laborRecordCount}",
        "仓库 ${preview.projectWarehouseMovementCount}",
        "价格库 ${preview.materialPriceEntryCount}",
        "供应商 ${preview.supplierProfileCount}",
        "工艺 ${preview.constructionMethodCount}"
    ).joinToString(" · ")

internal fun linkedMethodTitles(
    methods: List<ConstructionMethodSummary>,
    linkedIds: List<String>
): List<String> {
    if (linkedIds.isEmpty()) {
        return emptyList()
    }
    val methodsById = methods.associateBy { method -> method.id }
    return linkedIds.mapNotNull { methodId ->
        methodsById[methodId]?.displayTitle ?: methodId.takeIf(String::isNotBlank)
    }
}

internal fun projectRiskText(project: ProjectSummary): String =
    listOfNotNull(
        riskItemText(
            label = "逾期待办",
            count = project.overdueTodoCount
        ),
        riskItemText(
            label = "到期收款",
            count = project.dueIncomeCount
        ),
        riskItemText(
            label = "未进场材料",
            count = project.unarrivedMaterialCount
        )
    ).joinToString(" · ")

internal fun riskItemText(
    label: String,
    count: Int
): String? =
    if (count > 0) {
        "$label $count"
    } else {
        null
    }

internal fun ProjectSummary.totalRiskCount(): Int =
    overdueTodoCount + dueIncomeCount + unarrivedMaterialCount

internal fun List<ProjectSummary>.sortByRiskPriority(): List<ProjectSummary> =
    sortedWith(
        compareByDescending<ProjectSummary> { it.overdueTodoCount }
            .thenByDescending { it.dueIncomeCount }
            .thenByDescending { it.unarrivedMaterialCount }
            .thenByDescending { it.latestActivityDate.ifBlank { "0000-00-00" } }
            .thenBy { it.name.lowercase(Locale.ROOT) }
    )

internal fun dashboardProjectSublineText(project: ProjectSummary): String =
    listOfNotNull(
        project.expectedEndDate
            .takeIf(String::isNotBlank)
            ?.let { "计划完工 $it" },
        project.latestActivityDate
            .takeIf(String::isNotBlank)
            ?.let { "最近 $it" }
    ).joinToString(" · ").ifBlank { "暂无日期" }

internal fun List<ChecklistTodoSummary>.filterChecklistBy(
    statusFilter: ChecklistStatusFilter,
    priorityFilter: ChecklistPriorityFilter,
    ownerQuery: String
): List<ChecklistTodoSummary> {
    val keyword = ownerQuery.trim().lowercase(Locale.ROOT)

    return filter { todo ->
        todo.matchesStatusFilter(statusFilter) &&
            todo.matchesPriorityFilter(priorityFilter) &&
            todo.matchesChecklistKeyword(keyword)
    }
}

internal fun ChecklistTodoSummary.matchesStatusFilter(filter: ChecklistStatusFilter): Boolean =
    when (filter) {
        ChecklistStatusFilter.Open -> !isDone && !isProjectArchived
        ChecklistStatusFilter.Overdue -> isOverdue && !isProjectArchived
        ChecklistStatusFilter.All -> true
        ChecklistStatusFilter.Done -> isDone
    }

internal fun ChecklistTodoSummary.matchesPriorityFilter(filter: ChecklistPriorityFilter): Boolean =
    filter.priority == null || priority == filter.priority

internal fun ChecklistTodoSummary.matchesChecklistKeyword(keyword: String): Boolean =
    keyword.isBlank() ||
        listOf(title, owner, projectName, projectLocation, issueType)
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }

internal fun List<ChecklistTodoSummary>.sortForChecklist(): List<ChecklistTodoSummary> =
    sortedWith(
        compareBy<ChecklistTodoSummary> { it.isDone }
            .thenBy { !it.isOverdue }
            .thenByDescending { priorityWeight(it.priority) }
            .thenBy { it.dueDate.ifBlank { "9999-99-99" } }
            .thenBy { it.projectName.lowercase(Locale.ROOT) }
            .thenBy { it.title.lowercase(Locale.ROOT) }
    )

internal fun priorityWeight(priority: String): Int =
    when (priority) {
        "高" -> 3
        "普通" -> 2
        "低" -> 1
        else -> 2
    }

internal fun checklistTodoStateText(todo: ChecklistTodoSummary): String =
    when {
        todo.isDone -> "已完成"
        todo.isProjectArchived -> "归档项目"
        todo.isOverdue -> "逾期"
        else -> "未完成"
    }

internal fun checklistEmptyTitle(filter: ChecklistStatusFilter): String =
    when (filter) {
        ChecklistStatusFilter.Open -> "暂无未完成待办"
        ChecklistStatusFilter.Overdue -> "暂无逾期待办"
        ChecklistStatusFilter.All -> "暂无待办"
        ChecklistStatusFilter.Done -> "暂无已完成待办"
    }

internal fun List<QuickNoteSummary>.filterNotesBy(
    query: String,
    projectId: String?
): List<QuickNoteSummary> {
    val keyword = query.trim().lowercase(Locale.ROOT)

    return filter { note ->
        (projectId == null || note.projectId == projectId) &&
            note.matchesNoteKeyword(keyword)
    }
}

internal fun QuickNoteSummary.matchesNoteKeyword(keyword: String): Boolean =
    keyword.isBlank() ||
        (
            listOf(title, content, projectName, projectLocation) +
                attachments.flatMap { attachment ->
                    listOf(
                        attachment.originalName,
                        attachment.fileName,
                        quickNoteAttachmentKindText(attachment.kind)
                    )
                }
            )
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }

internal fun List<QuickNoteSummary>.sortForNotes(): List<QuickNoteSummary> =
    sortedWith(
        compareByDescending<QuickNoteSummary> { it.updatedAt.ifBlank { it.createdAt } }
            .thenBy { it.title.lowercase(Locale.ROOT) }
    )

internal fun noteMetaText(note: QuickNoteSummary): String =
    listOfNotNull(
        note.projectName
            .takeIf(String::isNotBlank)
            ?.let { projectName ->
                if (note.isProjectArchived) {
                    "$projectName · 已归档"
                } else {
                    projectName
                }
            }
            ?: "未关联项目",
        note.attachmentCount
            .takeIf { it > 0 }
            ?.let { "附件 $it" }
    ).joinToString(" · ")

internal fun quickNoteAttachmentMetaText(attachment: QuickNoteAttachmentSummary): String =
    listOfNotNull(
        quickNoteAttachmentKindText(attachment.kind),
        attachment.createdAt.takeIf(String::isNotBlank),
        attachment.durationSeconds
            ?.takeIf { it > 0.0 }
            ?.let { seconds -> "${seconds.toInt()} 秒" }
    ).joinToString(" · ")

internal fun quickNoteAttachmentKindText(kind: String): String =
    when (kind.lowercase(Locale.ROOT)) {
        "photo", "image" -> "照片"
        "audio", "voice" -> "录音"
        "video" -> "视频"
        else -> "文件"
    }

internal fun projectDocumentMetaText(document: ProjectDocumentSummary): String =
    listOfNotNull(
        document.category.takeIf(String::isNotBlank),
        "${document.pageCount.coerceAtLeast(1)} 页",
        document.amount.takeIf(String::isNotBlank)?.let { "金额 $it" },
        document.createdAt.takeIf(String::isNotBlank)
    ).joinToString(" · ")

internal fun projectDrawingMetaText(drawing: ProjectDrawingSummary): String =
    listOfNotNull(
        drawing.fileType.takeIf(String::isNotBlank),
        drawing.version.takeIf(String::isNotBlank),
        if (drawing.isCurrentVersion) "当前版本" else "历史版本",
        drawing.relatedLogDate.takeIf(String::isNotBlank)?.let { "关联 $it" },
        drawing.importedAt.takeIf(String::isNotBlank)
    ).joinToString(" · ")

internal fun projectDocumentPickActionText(status: DocumentArchiveStatus): String =
    when (status) {
        DocumentArchiveStatus.NotLinked -> "选择文件"
        DocumentArchiveStatus.Checking -> "更换文件"
        DocumentArchiveStatus.Archived -> "更换文件"
        DocumentArchiveStatus.Missing -> "重新选择"
    }

internal fun List<ProjectSummary>.filterBy(filter: ProjectListFilter): List<ProjectSummary> =
    when (filter) {
        ProjectListFilter.Active -> filter { it.status != "已归档" }
        ProjectListFilter.All -> this
        ProjectListFilter.Archived -> filter { it.status == "已归档" }
    }

internal fun List<ProjectSummary>.searchBy(query: String): List<ProjectSummary> {
    val keyword = query.trim().lowercase(Locale.ROOT)
    if (keyword.isBlank()) {
        return this
    }

    return filter { project ->
        listOf(project.name, project.location, project.managerName)
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }
    }
}

internal fun List<ProjectSummary>.sortBy(option: ProjectSortOption): List<ProjectSummary> =
    when (option) {
        ProjectSortOption.LatestActivity -> sortedWith(
            compareByDescending<ProjectSummary> { it.latestActivityDate.ifBlank { "0000-00-00" } }
                .thenBy { it.name.lowercase(Locale.ROOT) }
        )
        ProjectSortOption.Name -> sortedBy { it.name.lowercase(Locale.ROOT) }
        ProjectSortOption.ExpectedEnd -> sortedWith(
            compareBy<ProjectSummary> { it.expectedEndDate.ifBlank { "9999-99-99" } }
                .thenBy { it.name.lowercase(Locale.ROOT) }
        )
    }

internal fun emptyProjectTitle(
    filter: ProjectListFilter,
    searchQuery: String
): String =
    if (searchQuery.isNotBlank()) {
        "未找到匹配项目"
    } else when (filter) {
        ProjectListFilter.Active -> "暂无进行中项目"
        ProjectListFilter.All -> "暂无项目"
        ProjectListFilter.Archived -> "暂无已归档项目"
    }

internal fun emptyProjectMessage(
    filter: ProjectListFilter,
    searchQuery: String
): String =
    if (searchQuery.isNotBlank()) {
        "换个关键词或切换筛选条件。"
    } else when (filter) {
        ProjectListFilter.Active -> "可新建项目或切到全部查看归档项目。"
        ProjectListFilter.All -> "等待导入备份或新建项目。"
        ProjectListFilter.Archived -> "归档项目会显示在这里。"
    }

internal fun todayText(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
