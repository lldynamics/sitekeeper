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
internal fun BackupScreen(
    projectRepository: ProjectRepository,
    onOpenProject: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var statusText by rememberSaveable { mutableStateOf("本机数据") }
    var pendingExportJson by remember { mutableStateOf<String?>(null) }
    var pendingImport by remember { mutableStateOf<PendingBackupImport?>(null) }
    var archiveUsage by remember { mutableStateOf<DocumentArchiveUsage?>(null) }
    var dataHealth by remember { mutableStateOf<LocalDataHealthSnapshot?>(null) }

    fun refreshLocalDiagnostics() {
        scope.launch {
            runCatching {
                val rawJson = projectRepository.exportBackupJson()
                projectDocumentArchiveUsage(
                    context = context,
                    rawJson = rawJson
                ) to localDataHealth(
                    context = context,
                    rawJson = rawJson
                )
            }.onSuccess { (usage, health) ->
                archiveUsage = usage
                dataHealth = health
            }
        }
    }

    LaunchedEffect(projectRepository) {
        runCatching {
            val rawJson = projectRepository.exportBackupJson()
            projectDocumentArchiveUsage(
                context = context,
                rawJson = rawJson
            ) to localDataHealth(
                context = context,
                rawJson = rawJson
            )
        }.onSuccess { (usage, health) ->
            archiveUsage = usage
            dataHealth = health
        }
    }

    fun importPendingBackup(mode: BackupImportMode) {
        val import = pendingImport ?: return
        scope.launch {
            statusText = if (mode == BackupImportMode.Replace) {
                "正在覆盖导入"
            } else {
                "正在合并导入"
            }
            val importResult = runCatching {
                projectRepository.importBackupJson(
                    rawJson = import.rawJson,
                    mode = mode
                )
            }
            importResult.onSuccess { result ->
                val modeText = if (result.mode == BackupImportMode.Replace) "覆盖导入" else "合并导入"
                val restoredFileCount = restoreBackupPackageFiles(
                    context = context,
                    tempDir = import.attachmentTempDir,
                    projectRepository = projectRepository,
                    replaceExistingFiles = result.mode == BackupImportMode.Replace,
                    restorableDocumentIds = import.restorableDocumentIds,
                    restorablePhotoFileNames = import.restorablePhotoFileNames,
                    restorableDrawingIdsByFileName = import.restorableDrawingIdsByFileName,
                    restorableQuickNoteAttachmentFileNames = import.restorableQuickNoteAttachmentFileNames
                )
                statusText = if (restoredFileCount > 0) {
                    "已${modeText} ${result.totalCount} 条记录，恢复 $restoredFileCount 个文件"
                } else {
                    "已${modeText} ${result.totalCount} 条记录"
                }
                import.clearTempFiles()
                pendingImport = null
                refreshLocalDiagnostics()
            }.onFailure { error ->
                statusText = "导入失败：${error.message ?: "JSON 无法解析"}"
            }
        }
    }

    val exportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip")
    ) { uri ->
        val exportJson = pendingExportJson
        if (uri == null || exportJson == null) {
            pendingExportJson = null
            statusText = "已取消导出"
            return@rememberLauncherForActivityResult
        }

        scope.launch {
            statusText = "正在写入备份"
            runCatching {
                writeBackupPackageToUri(
                    context = context,
                    uri = uri,
                    rawJson = exportJson
                )
            }.onSuccess { result ->
                statusText = "已导出备份包，含 ${result.documentFileCount} 个资料文件、${result.photoFileCount} 个照片文件、${result.drawingFileCount} 个图纸文件、${result.quickNoteAttachmentFileCount} 个随手记附件"
            }.onFailure { error ->
                statusText = "导出失败：${error.message ?: "无法写入文件"}"
            }
            pendingExportJson = null
        }
    }

    val importLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) {
            statusText = "已取消导入"
            return@rememberLauncherForActivityResult
        }

        scope.launch {
            statusText = "正在读取备份"
            runCatching {
                val backupPackage = readBackupImportFromUri(
                    context = context,
                    uri = uri
                )
                PendingBackupImport(
                    rawJson = backupPackage.rawJson,
                    preview = projectRepository.previewBackupJson(backupPackage.rawJson),
                    attachmentCount = backupPackage.attachmentCount,
                    attachmentTempDir = backupPackage.attachmentTempDir,
                    preflightWarnings = backupPackage.preflightWarnings,
                    restorableDocumentIds = backupPackage.restorableDocumentIds,
                    restorablePhotoFileNames = backupPackage.restorablePhotoFileNames,
                    restorableDrawingIdsByFileName = backupPackage.restorableDrawingIdsByFileName,
                    restorableQuickNoteAttachmentFileNames = backupPackage.restorableQuickNoteAttachmentFileNames
                )
            }.onSuccess { import ->
                pendingImport?.clearTempFiles()
                pendingImport = import
                statusText = if (import.preflightWarnings.isNotEmpty()) {
                    "已读取 ${import.preview.totalCount} 条记录，预检 ${import.preflightWarnings.size} 项提示"
                } else if (import.attachmentCount > 0) {
                    "已读取 ${import.preview.totalCount} 条记录，附件 ${import.attachmentCount} 个，确认后导入"
                } else {
                    "已读取 ${import.preview.totalCount} 条记录，确认后导入"
                }
            }.onFailure { error ->
                statusText = "导入失败：${error.message ?: "JSON 无法解析"}"
            }
        }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(
                text = "我的",
                style = MaterialTheme.typography.headlineMedium
            )
        }

        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
                ),
                shape = RoundedCornerShape(8.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "本机备份",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    archiveUsage?.let { usage ->
                        Text(
                            text = documentArchiveUsageText(usage),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (usage.orphanFileCount > 0) {
                            TextButton(
                                onClick = {
                                    scope.launch {
                                        statusText = "正在清理孤立资料文件"
                                        runCatching {
                                            val rawJson = projectRepository.exportBackupJson()
                                            cleanupOrphanProjectDocumentArchives(
                                                context = context,
                                                rawJson = rawJson
                                            )
                                        }.onSuccess { deletedCount ->
                                            statusText = if (deletedCount > 0) {
                                                "已清理 $deletedCount 个孤立资料文件"
                                            } else {
                                                "没有孤立资料文件"
                                            }
                                            refreshLocalDiagnostics()
                                        }.onFailure { error ->
                                            statusText = "清理失败：${error.message ?: "无法删除文件"}"
                                        }
                                    }
                                }
                            ) {
                                Text("清理孤立附件")
                            }
                        }
                    }
                    pendingImport?.let { import ->
                        ImportPreviewCard(
                            preview = import.preview,
                            attachmentCount = import.attachmentCount,
                            restorableDocumentCount = import.restorableDocumentIds.size,
                            restorablePhotoCount = import.restorablePhotoFileNames.size,
                            restorableDrawingCount = import.restorableDrawingIdsByFileName.size,
                            restorableQuickNoteAttachmentCount = import.restorableQuickNoteAttachmentFileNames.size,
                            preflightWarnings = import.preflightWarnings,
                            onMerge = { importPendingBackup(BackupImportMode.Merge) },
                            onReplace = { importPendingBackup(BackupImportMode.Replace) },
                            onCancel = {
                                import.clearTempFiles()
                                pendingImport = null
                                statusText = "已取消导入"
                            }
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Button(
                            onClick = {
                                importLauncher.launch(
                                    arrayOf(
                                        "application/zip",
                                        "application/json",
                                        "text/*",
                                        "*/*"
                                    )
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("导入备份")
                        }
                        Button(
                            onClick = {
                                scope.launch {
                                    statusText = "正在准备导出"
                                    runCatching {
                                        projectRepository.exportBackupJson()
                                    }.onSuccess { json ->
                                        pendingExportJson = json
                                        exportLauncher.launch(defaultBackupPackageFileName())
                                    }.onFailure { error ->
                                        statusText = "导出失败：${error.message ?: "无法生成备份"}"
                                    }
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("导出备份包")
                        }
                    }
                }
            }
        }

        item {
            DataHealthCard(
                snapshot = dataHealth,
                onOpenProject = onOpenProject,
                onRefresh = {
                    statusText = "正在重新体检"
                    refreshLocalDiagnostics()
                },
                onCreateFixTodos = {
                    val fixTodos = dataHealth?.fixTodos.orEmpty()
                    if (fixTodos.isEmpty()) {
                        statusText = "没有需要生成的整改待办"
                    } else {
                        scope.launch {
                            statusText = "正在生成整改待办"
                            val createdCount = fixTodos.count { todo ->
                                projectRepository.addSiteTodoIfAbsent(
                                    projectId = todo.projectId,
                                    title = todo.title,
                                    owner = "",
                                    dueDate = todayText(),
                                    priority = todo.priority,
                                    issueType = todo.issueType,
                                    note = todo.note
                                )
                            }
                            statusText = if (createdCount > 0) {
                                "已生成 $createdCount 条整改待办"
                            } else {
                                "整改待办已存在"
                            }
                            refreshLocalDiagnostics()
                        }
                    }
                },
                onCleanupOrphans = {
                    scope.launch {
                        statusText = "正在清理孤立文件"
                        runCatching {
                            cleanupOrphanLocalArchives(
                                context = context,
                                rawJson = projectRepository.exportBackupJson()
                            )
                        }.onSuccess { result ->
                            statusText = if (result.deletedFileCount > 0) {
                                "已清理 ${result.deletedFileCount} 个孤立文件，释放 ${dataHealthBytesText(result.deletedBytes)}"
                            } else {
                                "没有孤立文件"
                            }
                            refreshLocalDiagnostics()
                        }.onFailure { error ->
                            statusText = "清理失败：${error.message ?: "无法删除文件"}"
                        }
                    }
                }
            )
        }
    }
}

private data class PendingBackupImport(
    val rawJson: String,
    val preview: BackupImportPreview,
    val attachmentCount: Int = 0,
    val attachmentTempDir: File? = null,
    val preflightWarnings: List<String> = emptyList(),
    val restorableDocumentIds: Set<String> = emptySet(),
    val restorablePhotoFileNames: Set<String> = emptySet(),
    val restorableDrawingIdsByFileName: Map<String, String> = emptyMap(),
    val restorableQuickNoteAttachmentFileNames: Set<String> = emptySet()
) {
    fun clearTempFiles() {
        attachmentTempDir?.deleteRecursively()
    }
}

@Composable
private fun DataHealthCard(
    snapshot: LocalDataHealthSnapshot?,
    onOpenProject: (String) -> Unit,
    onRefresh: () -> Unit,
    onCreateFixTodos: () -> Unit,
    onCleanupOrphans: () -> Unit
) {
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
                    text = "数据体检",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(onClick = onRefresh) {
                    Text("重新体检")
                }
            }
            if (snapshot == null) {
                Text(
                    text = "正在读取本机数据",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = localDataHealthSummaryText(snapshot),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (snapshot.issueCount > 0) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    }
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ProjectMetric(
                        label = "记录",
                        value = "${snapshot.recordCount}",
                        modifier = Modifier.weight(1f)
                    )
                    ProjectMetric(
                        label = "引用文件",
                        value = "${snapshot.referencedFileCount}",
                        modifier = Modifier.weight(1f)
                    )
                    ProjectMetric(
                        label = "项目",
                        value = "${snapshot.projectCount}",
                        modifier = Modifier.weight(1f)
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ProjectMetric(
                        label = "缺失",
                        value = "${snapshot.missingFileCount}",
                        modifier = Modifier.weight(1f)
                    )
                    ProjectMetric(
                        label = "孤立",
                        value = "${snapshot.orphanFileCount}",
                        modifier = Modifier.weight(1f)
                    )
                    ProjectMetric(
                        label = "可释放",
                        value = dataHealthBytesText(snapshot.orphanFileBytes),
                        modifier = Modifier.weight(1f)
                    )
                }
                Text(
                    text = listOf(
                        "资料缺失 ${snapshot.missingDocumentFileCount}",
                        "照片缺失 ${snapshot.missingPhotoFileCount}",
                        "图纸缺失 ${snapshot.missingDrawingFileCount}",
                        "随手记附件缺失 ${snapshot.missingQuickNoteAttachmentCount}"
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (snapshot.fixTodos.isNotEmpty()) {
                    Text(
                        text = "可生成整改待办 ${snapshot.fixTodos.size} 条",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    HorizontalDivider()
                    Text(
                        text = "缺失明细",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    snapshot.fixTodos.take(6).forEach { todo ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp)
                            ) {
                                Text(
                                    text = todo.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = todo.note,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            TextButton(onClick = { onOpenProject(todo.projectId) }) {
                                Text("打开项目")
                            }
                        }
                    }
                    if (snapshot.fixTodos.size > 6) {
                        Text(
                            text = "还有 ${snapshot.fixTodos.size - 6} 条缺失项",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    TextButton(onClick = onCreateFixTodos) {
                        Text("生成整改待办")
                    }
                }
                Text(
                    text = listOf(
                        "孤立资料 ${snapshot.orphanDocumentFileCount}",
                        "孤立照片 ${snapshot.orphanPhotoFileCount}",
                        "孤立图纸 ${snapshot.orphanDrawingFileCount}",
                        "孤立随手记 ${snapshot.orphanQuickNoteAttachmentCount}"
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (snapshot.orphanFileCount > 0) {
                    TextButton(onClick = onCleanupOrphans) {
                        Text("清理孤立文件")
                    }
                }
            }
        }
    }
}

@Composable
private fun ImportPreviewCard(
    preview: BackupImportPreview,
    attachmentCount: Int,
    restorableDocumentCount: Int,
    restorablePhotoCount: Int,
    restorableDrawingCount: Int,
    restorableQuickNoteAttachmentCount: Int,
    preflightWarnings: List<String>,
    onMerge: () -> Unit,
    onReplace: () -> Unit,
    onCancel: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        HorizontalDivider()
        Text(
            text = "导入预览",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = importPreviewText(preview),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (attachmentCount > 0) {
            Text(
                text = "随包文件 $attachmentCount · 资料可恢复 $restorableDocumentCount · 照片可恢复 $restorablePhotoCount · 图纸可恢复 $restorableDrawingCount · 随手记附件可恢复 $restorableQuickNoteAttachmentCount",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (preflightWarnings.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "导入预检",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                preflightWarnings.forEach { warning ->
                    Text(
                        text = warning,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
        Text(
            text = "覆盖会先清空本机项目、进度、日志、待办、收支、材料、资料附件和照片文件。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(
                onClick = onCancel,
                modifier = Modifier.weight(1f)
            ) {
                Text("取消")
            }
            Button(
                onClick = onMerge,
                modifier = Modifier.weight(1f)
            ) {
                Text("合并")
            }
            Button(
                onClick = onReplace,
                modifier = Modifier.weight(1f)
            ) {
                Text("覆盖")
            }
        }
    }
}
