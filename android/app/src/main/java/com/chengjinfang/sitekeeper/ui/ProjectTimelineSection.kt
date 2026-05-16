package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentSummary
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.labor.LaborRecordSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodSummary
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary

private const val TIMELINE_LIMIT = 20

@Composable
fun ProjectTimelineSection(detail: ProjectDetail) {
    val items = remember(detail) { detail.toProjectTimelineItems() }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "项目时间线",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "${items.size} 条",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (items.isEmpty()) {
                Text(
                    text = "暂无项目动态",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                items.take(TIMELINE_LIMIT).forEachIndexed { index, item ->
                    ProjectTimelineRow(item = item)
                    if (index != items.take(TIMELINE_LIMIT).lastIndex) {
                        HorizontalDivider()
                    }
                }
                if (items.size > TIMELINE_LIMIT) {
                    Text(
                        text = "仅显示最近 $TIMELINE_LIMIT 条",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun ProjectTimelineRow(item: ProjectTimelineItem) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = item.kind,
                    style = MaterialTheme.typography.labelLarge,
                    color = item.kindColor()
                )
                Text(
                    text = item.date.ifBlank { "未填日期" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                text = item.title.ifBlank { item.kind },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            if (item.meta.isNotBlank()) {
                Text(
                    text = item.meta,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (item.linkedMethodTitles.isNotEmpty()) {
                Text(
                    text = "关联工艺：${item.linkedMethodTitles.joinToString("、")}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun ProjectTimelineItem.kindColor() =
    when (kind) {
        "收支", "报价" -> MaterialTheme.colorScheme.primary
        "待办" -> MaterialTheme.colorScheme.error
        "仓库", "材料" -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }

private data class ProjectTimelineItem(
    val kind: String,
    val date: String,
    val title: String,
    val meta: String = "",
    val linkedMethodTitles: List<String> = emptyList()
)

private fun ProjectDetail.toProjectTimelineItems(): List<ProjectTimelineItem> {
    val methodTitlesById = constructionMethods.associate { method -> method.id to method.displayTitle }

    fun linkedTitles(ids: List<String>): List<String> =
        ids.mapNotNull { id -> methodTitlesById[id] ?: id.takeIf(String::isNotBlank) }

    return buildList {
        dailyLogs.mapTo(this) { log -> log.toTimelineItem(linkedTitles(log.linkedConstructionMethodIds)) }
        siteTodos.mapTo(this) { todo -> todo.toTimelineItem(linkedTitles(todo.linkedConstructionMethodIds)) }
        progressTasks.mapTo(this) { task -> task.toTimelineItem() }
        financialRecords.mapTo(this) { record -> record.toTimelineItem() }
        materialItems.mapTo(this) { material -> material.toTimelineItem() }
        documents.mapTo(this) { document -> document.toTimelineItem(linkedTitles(document.linkedConstructionMethodIds)) }
        drawings.mapTo(this) { drawing -> drawing.toTimelineItem() }
        quoteItems.mapTo(this) { quote -> quote.toTimelineItem() }
        laborRecords.mapTo(this) { labor -> labor.toTimelineItem() }
        warehouseMovements.mapTo(this) { movement -> movement.toTimelineItem() }
    }
        .sortedWith(
            compareByDescending<ProjectTimelineItem> { it.sortKey() }
                .thenBy { it.kind }
                .thenBy { it.title }
        )
}

private fun DailyLogSummary.toTimelineItem(methodTitles: List<String>): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "日志",
        date = date,
        title = content.ifBlank { "施工日志" },
        meta = listOf(weather, workers.takeIf(String::isNotBlank)?.let { "$it 人" })
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · "),
        linkedMethodTitles = methodTitles
    )

private fun SiteTodoSummary.toTimelineItem(methodTitles: List<String>): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "待办",
        date = dueDate,
        title = title.ifBlank { "待办整改" },
        meta = listOf(issueType, owner, priority, if (isDone) "已完成" else "未完成")
            .filter(String::isNotBlank)
            .joinToString(" · "),
        linkedMethodTitles = methodTitles
    )

private fun ProgressTaskSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "进度",
        date = dueDate.ifBlank { startDate },
        title = title.ifBlank { "进度任务" },
        meta = listOfNotNull(
            startDate.takeIf(String::isNotBlank)?.let { "开始 $it" },
            "${(completion * 100).toInt()}%"
        ).joinToString(" · ")
    )

private fun ProjectFinancialRecordSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "收支",
        date = date.ifBlank { dueDate },
        title = listOf(direction, category, amount.takeIf(String::isNotBlank)?.let { "$it 元" })
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")
            .ifBlank { "收支记录" },
        meta = listOf(counterparty, status, note)
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun MaterialItemSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "材料",
        date = arrivalDate,
        title = listOf(name, specification)
            .filter(String::isNotBlank)
            .joinToString(" ")
            .ifBlank { "材料记录" },
        meta = listOf(quantity.takeIf(String::isNotBlank)?.let { "$it$unit" }, unitPrice, supplier, purchaseStatus)
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun ProjectDocumentSummary.toTimelineItem(methodTitles: List<String>): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "资料",
        date = createdAt,
        title = title.ifBlank { "项目资料" },
        meta = listOf(category, fileType, fileName)
            .filter(String::isNotBlank)
            .joinToString(" · "),
        linkedMethodTitles = methodTitles
    )

private fun ProjectDrawingSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "图纸",
        date = importedAt.ifBlank { relatedLogDate },
        title = name.ifBlank { fileName.ifBlank { "项目图纸" } },
        meta = listOf(version, fileType, issueStatus)
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun QuoteItemSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "报价",
        date = customerConfirmedDate,
        title = name.ifBlank { "报价项" },
        meta = listOf(versionName, status, contractAmount.takeIf(String::isNotBlank)?.let { "$it 元" })
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun LaborRecordSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "用工",
        date = date,
        title = listOf(workType, teamName)
            .filter(String::isNotBlank)
            .joinToString(" · ")
            .ifBlank { "用工记录" },
        meta = listOf(workers.takeIf(String::isNotBlank)?.let { "$it 人" }, hours.takeIf(String::isNotBlank)?.let { "$it 天" }, if (isSettled) "已结算" else "未结算")
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun ProjectWarehouseMovementSummary.toTimelineItem(): ProjectTimelineItem =
    ProjectTimelineItem(
        kind = "仓库",
        date = date.ifBlank { createdAt },
        title = listOf(movementType, materialName)
            .filter(String::isNotBlank)
            .joinToString(" · ")
            .ifBlank { "仓库流水" },
        meta = listOf(specification, quantity.takeIf(String::isNotBlank)?.let { "$it$unit" }, counterparty, handler)
            .filterNotNull()
            .filter(String::isNotBlank)
            .joinToString(" · ")
    )

private fun ProjectTimelineItem.sortKey(): String =
    date.trim().ifBlank { "0000-00-00" }
