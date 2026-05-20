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
internal fun FinanceOverviewCard(records: List<ProjectFinancialRecordSummary>) {
    val income = records
        .filter { it.direction == "收入" }
        .sumOf { amountValue(it.amount) }
    val expense = records
        .filter { it.direction == "支出" }
        .sumOf { amountValue(it.amount) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ProjectMetric(
                label = "收入",
                value = moneyText(income),
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "支出",
                value = moneyText(expense),
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "差额",
                value = moneyText(income - expense),
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
internal fun FinancialRecordRow(
    record: ProjectFinancialRecordSummary,
    onEdit: () -> Unit,
    onUpdateStatus: (String) -> Unit,
    onDeleteRequest: () -> Unit
) {
    val targetStatus = if (record.status == "正式") "待处理" else "正式"
    val actionLabel = if (targetStatus == "正式") "设为正式" else "设为待处理"
    val statusLine = listOf(
        record.status,
        record.dueDate.takeIf(String::isNotBlank)?.let { "到期：$it" }.orEmpty()
    ).filter(String::isNotBlank).joinToString(" · ")

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = "${record.direction} · ${record.category}",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(record.date, record.counterparty)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = record.amount.ifBlank { "-" },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (record.direction == "收入") {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    }
                )
            }
            if (statusLine.isNotBlank()) {
                Text(
                    text = statusLine,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (record.note.isNotBlank()) {
                Text(
                    text = record.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = { onUpdateStatus(targetStatus) }) {
                    Text(actionLabel)
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun QuoteItemRow(
    quote: QuoteItemSummary,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = quote.name.ifBlank { "未命名报价" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = quoteMetaText(quote),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = quote.contractAmount.ifBlank { quoteLineAmountText(quote) },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            if (quote.notes.isNotBlank()) {
                Text(
                    text = quote.notes,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun LaborRecordRow(
    labor: LaborRecordSummary,
    onEdit: () -> Unit,
    onToggleSettled: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = laborTitleText(labor),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = laborMetaText(labor),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = if (labor.isSettled) "已结算" else "未结算",
                    style = MaterialTheme.typography.labelLarge,
                    color = if (labor.isSettled) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (labor.note.isNotBlank()) {
                Text(
                    text = labor.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onToggleSettled) {
                    Text(if (labor.isSettled) "设为未结算" else "标记结算")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun WarehouseStockSummaryCard(
    movements: List<ProjectWarehouseMovementSummary>
) {
    val stockLines = remember(movements) { warehouseStockLines(movements) }
    val negativeCount = stockLines.count { it.quantity < 0.0 }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "库存材料",
                    value = stockLines.size.toString(),
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "负库存",
                    value = negativeCount.toString(),
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "流水",
                    value = movements.size.toString(),
                    modifier = Modifier.weight(1f)
                )
            }
            stockLines.take(3).forEach { line ->
                Text(
                    text = "${line.name}${line.specification.takeIf(String::isNotBlank)?.let { " · $it" }.orEmpty()}：${moneyText(line.quantity)} ${line.unit}".trim(),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (line.quantity < 0.0) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
            }
        }
    }
}

@Composable
internal fun WarehouseMovementRow(
    movement: ProjectWarehouseMovementSummary,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val isInbound = movement.movementType != "出库"

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = movement.materialName.ifBlank { "未命名材料" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = warehouseMetaText(movement),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = warehouseSignedQuantityText(movement),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isInbound) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    }
                )
            }
            if (movement.note.isNotBlank()) {
                Text(
                    text = movement.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun MaterialItemRow(
    material: MaterialItemSummary,
    onEdit: () -> Unit,
    onUpdateStatus: (String) -> Unit,
    onDeleteRequest: () -> Unit
) {
    val targetStatus = nextMaterialPurchaseStatus(material.purchaseStatus)
    val actionLabel = if (targetStatus == "待采购") {
        "设为待采购"
    } else {
        "标记$targetStatus"
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = material.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(material.specification, material.supplier)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = material.purchaseStatus,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "数量",
                    value = "${material.quantity} ${material.unit}".trim(),
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "单价",
                    value = material.unitPrice.ifBlank { "-" },
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "进场",
                    value = material.arrivalDate.ifBlank { "-" },
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = { onUpdateStatus(targetStatus) }) {
                    Text(actionLabel)
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun ProgressTaskRow(
    task: ProgressTaskSummary,
    onEdit: () -> Unit,
    onToggleDone: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = task.title.ifBlank { "未命名进度" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(task.startDate, task.dueDate)
                            .filter(String::isNotBlank)
                            .joinToString(" 至 "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = progressPercentText(task.completion),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (task.completion >= 1.0) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (task.note.isNotBlank()) {
                Text(
                    text = task.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onToggleDone) {
                    Text(if (task.completion >= 1.0) "重新打开" else "标记完成")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun ProjectDetailMetricRow(project: ProjectSummary) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ProjectMetric(
                label = "合同",
                value = project.contractAmount.ifBlank { "-" },
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "已收",
                value = project.paidAmount.ifBlank { "-" },
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "状态",
                value = project.status,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
internal fun ProjectDeliveryExportCard(
    detail: ProjectDetail,
    preflight: ProjectDeliveryPackagePreflight?,
    statusText: String,
    onExport: () -> Unit
) {
    val recordCount = detail.dailyLogs.size +
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
    val metadataAttachmentCount = detail.documents.count { it.localUri.isNotBlank() } +
        detail.drawings.count { it.localUri.isNotBlank() }
    val metadataPhotoCount = detail.dailyLogs.sumOf { it.photoCount } +
        detail.siteTodos.sumOf { todo ->
            listOf(todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName)
                .count { !it.isNullOrBlank() }
        }
    val packagedFileCount = preflight?.packagedFileCount ?: (metadataAttachmentCount + metadataPhotoCount)
    val missingFileCount = preflight?.missingFileCount ?: 0

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "项目交付",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Button(onClick = onExport) {
                    Text("导出交付包")
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "记录",
                    value = "$recordCount",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "可打包",
                    value = "$packagedFileCount",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "缺失",
                    value = "$missingFileCount",
                    modifier = Modifier.weight(1f)
                )
            }
            if (preflight == null) {
                Text(
                    text = "正在体检交付文件",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = "资料 ${preflight.documentFileCount} · 图纸 ${preflight.drawingFileCount} · 照片 ${preflight.photoFileCount}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = projectDeliveryPackagePreflightSummaryText(preflight),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (preflight.missingFileCount > 0) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    }
                )
                if (preflight.missingFiles.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        preflight.missingFiles.take(5).forEach { missingFile ->
                            Text(
                                text = missingFile,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (preflight.missingFiles.size > 5) {
                            Text(
                                text = "还有 ${preflight.missingFiles.size - 5} 个缺失文件",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
            if (statusText.isNotBlank()) {
                Text(
                    text = statusText,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
internal fun SectionTitle(
    title: String,
    count: Int,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "$count",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (actionLabel != null && onAction != null) {
                TextButton(onClick = onAction) {
                    Text(actionLabel)
                }
            }
        }
    }
    HorizontalDivider()
}

@Composable
internal fun DailyLogRow(
    log: DailyLogSummary,
    linkedMethodTitles: List<String>,
    onEdit: () -> Unit,
    onAddPhoto: () -> Unit,
    onOpenPhoto: (String) -> Unit,
    onDeletePhoto: (String) -> Unit,
    onDeleteRequest: () -> Unit
) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = log.date,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = listOf(log.weather, "${log.workers} 人")
                        .filter(String::isNotBlank)
                        .joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                text = log.content.ifBlank { "未填写施工内容" },
                style = MaterialTheme.typography.bodyMedium
            )
            if (log.tomorrowPlan.isNotBlank()) {
                Text(
                    text = "明日：${log.tomorrowPlan}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinkedConstructionMethodText(linkedMethodTitles)
            if (log.photoFileNames.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    log.photoFileNames.forEach { fileName ->
                        PhotoAttachmentLine(
                            label = fileName,
                            canOpen = canOpenLocalPhoto(context, fileName),
                            onOpen = { onOpenPhoto(fileName) },
                            onDelete = { onDeletePhoto(fileName) }
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onAddPhoto) {
                    Text("添加照片")
                }
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun ProjectContactRow(
    contact: ProjectContactSummary,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = contact.name.ifBlank { "未命名联系人" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(contact.role, contact.company)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = contact.phone.ifBlank { "-" },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (contact.note.isNotBlank()) {
                Text(
                    text = contact.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun ProjectDocumentRow(
    document: ProjectDocumentSummary,
    linkedMethodTitles: List<String>,
    onOpenFile: () -> Unit,
    onPickFile: () -> Unit,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val archiveStatus = rememberDocumentArchiveStatus(localUri = document.localUri)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = document.title.ifBlank { "未命名资料" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = projectDocumentMetaText(document),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = document.fileType.ifBlank { "-" },
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (document.fileName.isNotBlank()) {
                Text(
                    text = document.fileName,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            LinkedConstructionMethodText(linkedMethodTitles)
            Text(
                text = archiveStatus.title,
                style = MaterialTheme.typography.labelLarge,
                color = when (archiveStatus) {
                    DocumentArchiveStatus.Archived -> MaterialTheme.colorScheme.primary
                    DocumentArchiveStatus.Missing -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
                fontWeight = FontWeight.SemiBold
            )
            if (document.note.isNotBlank()) {
                Text(
                    text = document.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(
                    enabled = archiveStatus == DocumentArchiveStatus.Archived,
                    onClick = onOpenFile
                ) {
                    Text("打开")
                }
                TextButton(onClick = onPickFile) {
                    Text(projectDocumentPickActionText(archiveStatus))
                }
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun ProjectDrawingRow(
    drawing: ProjectDrawingSummary,
    onOpenFile: () -> Unit,
    onPickFile: () -> Unit,
    onEdit: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val archiveStatus = rememberDocumentArchiveStatus(drawing.localUri)
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = drawing.name.ifBlank { "未命名图纸" },
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = projectDrawingMetaText(drawing),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = drawing.issueStatus.ifBlank { "无问题" },
                    style = MaterialTheme.typography.labelLarge,
                    color = if (drawing.issueStatus == "无问题" || drawing.issueStatus.isBlank()) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.error
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (drawing.fileName.isNotBlank()) {
                Text(
                    text = drawing.fileName,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Text(
                text = archiveStatus.title,
                style = MaterialTheme.typography.labelLarge,
                color = when (archiveStatus) {
                    DocumentArchiveStatus.Archived -> MaterialTheme.colorScheme.primary
                    DocumentArchiveStatus.Missing -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.onSurfaceVariant
                },
                fontWeight = FontWeight.SemiBold
            )
            if (drawing.issueNote.isNotBlank()) {
                Text(
                    text = drawing.issueNote,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            if (drawing.note.isNotBlank()) {
                Text(
                    text = drawing.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(
                    enabled = archiveStatus == DocumentArchiveStatus.Archived,
                    onClick = onOpenFile
                ) {
                    Text("打开")
                }
                TextButton(onClick = onPickFile) {
                    Text(projectDocumentPickActionText(archiveStatus))
                }
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun rememberDocumentArchiveStatus(localUri: String): DocumentArchiveStatus {
    val context = LocalContext.current
    var status by remember(localUri) {
        mutableStateOf(
            if (localUri.isBlank()) {
                DocumentArchiveStatus.NotLinked
            } else {
                DocumentArchiveStatus.Checking
            }
        )
    }

    LaunchedEffect(localUri) {
        status = if (localUri.isBlank()) {
            DocumentArchiveStatus.NotLinked
        } else {
            val canOpen = withContext(Dispatchers.IO) {
                canOpenLocalDocument(context, localUri)
            }
            if (canOpen) {
                DocumentArchiveStatus.Archived
            } else {
                DocumentArchiveStatus.Missing
            }
        }
    }

    return status
}

@Composable
internal fun SiteTodoRow(
    todo: SiteTodoSummary,
    linkedMethodTitles: List<String>,
    onEdit: () -> Unit,
    onToggleDone: () -> Unit,
    onAttachBeforePhoto: () -> Unit,
    onAttachAfterPhoto: () -> Unit,
    onOpenPhoto: (String) -> Unit,
    onDeleteBeforePhoto: () -> Unit,
    onDeleteAfterPhoto: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    val context = LocalContext.current
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = todo.title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = if (todo.isDone) "已完成" else todo.priority,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (todo.isDone) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
            Text(
                text = listOf(todo.issueType, todo.owner, todo.dueDate)
                    .filter(String::isNotBlank)
                    .joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (todo.note.isNotBlank()) {
                Text(
                    text = todo.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            LinkedConstructionMethodText(linkedMethodTitles)
            TodoPhotoLine(
                label = "整改前",
                fileName = todo.rectificationBeforePhotoFileName,
                canOpen = todo.rectificationBeforePhotoFileName?.let { canOpenLocalPhoto(context, it) } ?: false,
                onAttach = onAttachBeforePhoto,
                onOpen = { fileName -> onOpenPhoto(fileName) },
                onDelete = onDeleteBeforePhoto
            )
            TodoPhotoLine(
                label = "整改后",
                fileName = todo.rectificationAfterPhotoFileName,
                canOpen = todo.rectificationAfterPhotoFileName?.let { canOpenLocalPhoto(context, it) } ?: false,
                onAttach = onAttachAfterPhoto,
                onOpen = { fileName -> onOpenPhoto(fileName) },
                onDelete = onDeleteAfterPhoto
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onEdit) {
                    Text("编辑")
                }
                TextButton(onClick = onToggleDone) {
                    Text(if (todo.isDone) "重新打开" else "标记完成")
                }
                TextButton(onClick = onDeleteRequest) {
                    Text("删除")
                }
            }
        }
    }
}

@Composable
internal fun PhotoAttachmentLine(
    label: String,
    canOpen: Boolean,
    onOpen: () -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            color = if (canOpen) {
                MaterialTheme.colorScheme.onSurfaceVariant
            } else {
                MaterialTheme.colorScheme.error
            }
        )
        TextButton(
            onClick = onOpen,
            enabled = canOpen
        ) {
            Text("打开")
        }
        TextButton(onClick = onDelete) {
            Text("移除")
        }
    }
}

@Composable
internal fun TodoPhotoLine(
    label: String,
    fileName: String?,
    canOpen: Boolean,
    onAttach: () -> Unit,
    onOpen: (String) -> Unit,
    onDelete: () -> Unit
) {
    if (fileName.isNullOrBlank()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "$label：未添加",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TextButton(onClick = onAttach) {
                Text("添加$label")
            }
        }
    } else {
        PhotoAttachmentLine(
            label = "$label：$fileName",
            canOpen = canOpen,
            onOpen = { onOpen(fileName) },
            onDelete = onDelete
        )
    }
}
