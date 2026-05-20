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
internal fun NotesScreen(
    projectRepository: ProjectRepository,
    projects: List<ProjectSummary>,
    onOpenProject: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val notes by projectRepository.quickNotes.collectAsStateWithLifecycle(initialValue = emptyList())
    var showNoteForm by rememberSaveable { mutableStateOf(false) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var selectedProjectFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var editingNoteId by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmingDeleteId by rememberSaveable { mutableStateOf<String?>(null) }
    var attachmentPickerTargetId by rememberSaveable { mutableStateOf<String?>(null) }
    val quickNoteAttachmentPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val noteId = attachmentPickerTargetId
        if (uri != null && noteId != null) {
            scope.launch {
                val fileInfo = runCatching {
                    withContext(Dispatchers.IO) {
                        archiveQuickNoteAttachmentFile(
                            context = context,
                            sourceUri = uri
                        )
                    }
                }.getOrNull()
                if (fileInfo != null) {
                    projectRepository.attachQuickNoteFile(
                        noteId = noteId,
                        kind = fileInfo.kind,
                        fileName = fileInfo.name,
                        originalName = fileInfo.originalName
                    )
                }
            }
        }
        attachmentPickerTargetId = null
    }
    val activeProjects = remember(projects) {
        projects.filterBy(ProjectListFilter.Active)
    }
    val visibleNotes = remember(notes, searchQuery, selectedProjectFilter) {
        notes
            .filterNotesBy(
                query = searchQuery,
                projectId = selectedProjectFilter
            )
            .sortForNotes()
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "随手记",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = "现场问题、沟通结论和临时记录。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = { showNoteForm = !showNoteForm }) {
                    Text(if (showNoteForm) "收起" else "新建")
                }
            }
        }

        item {
            NotesSummaryCard(notes = notes)
        }

        if (showNoteForm) {
            item {
                QuickNoteFormCard(
                    projects = activeProjects,
                    onCancel = { showNoteForm = false },
                    onSave = { title, content, projectId ->
                        scope.launch {
                            projectRepository.addQuickNote(
                                title = title,
                                content = content,
                                projectId = projectId
                            )
                        }
                        showNoteForm = false
                    }
                )
            }
        }

        item {
            NotesProjectFilterRow(
                projects = activeProjects,
                selectedProjectId = selectedProjectFilter,
                onSelectProject = { selectedProjectFilter = it }
            )
        }

        item {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("搜索标题、内容或项目") },
                singleLine = true
            )
        }

        if (visibleNotes.isEmpty()) {
            item {
                DashboardEmptyCard(
                    title = "暂无随手记",
                    message = "可新建现场记录，或调整搜索和项目筛选。"
                )
            }
        } else {
            items(
                items = visibleNotes,
                key = QuickNoteSummary::id
            ) { note ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuickNoteRow(
                        note = note,
                        onOpenProject = {
                            if (note.projectId.isNotBlank()) {
                                onOpenProject(note.projectId)
                            }
                        },
                        onEdit = {
                            editingNoteId = if (editingNoteId == note.id) {
                                null
                            } else {
                                note.id
                            }
                        },
                        onAddAttachment = {
                            attachmentPickerTargetId = note.id
                            quickNoteAttachmentPicker.launch(
                                arrayOf(
                                    "image/*",
                                    "audio/*",
                                    "video/*",
                                    "application/pdf",
                                    "text/*",
                                    "*/*"
                                )
                            )
                        },
                        onOpenAttachment = { attachment ->
                            openLocalQuickNoteAttachment(context, attachment.fileName)
                        },
                        onDeleteAttachment = { attachment ->
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    deleteQuickNoteAttachmentArchive(context, attachment.fileName)
                                }
                                projectRepository.deleteQuickNoteAttachment(
                                    noteId = note.id,
                                    attachmentId = attachment.id
                                )
                            }
                        },
                        onDeleteRequest = { confirmingDeleteId = note.id }
                    )
                    if (confirmingDeleteId == note.id) {
                        ConfirmDeleteRow(
                            label = "删除这条随手记？",
                            onCancel = { confirmingDeleteId = null },
                            onConfirm = {
                                scope.launch {
                                    withContext(Dispatchers.IO) {
                                        note.attachments.forEach { attachment ->
                                            deleteQuickNoteAttachmentArchive(context, attachment.fileName)
                                        }
                                    }
                                    projectRepository.deleteQuickNote(note.id)
                                }
                                confirmingDeleteId = null
                                editingNoteId = null
                            }
                        )
                    }
                    if (editingNoteId == note.id) {
                        QuickNoteFormCard(
                            formKey = "edit-note-${note.id}",
                            titleText = "编辑随手记",
                            projects = activeProjects,
                            initialTitle = note.title,
                            initialContent = note.content,
                            initialProjectId = note.projectId.takeIf(String::isNotBlank),
                            onCancel = { editingNoteId = null },
                            onSave = { title, content, projectId ->
                                scope.launch {
                                    projectRepository.updateQuickNote(
                                        noteId = note.id,
                                        title = title,
                                        content = content,
                                        projectId = projectId
                                    )
                                }
                                editingNoteId = null
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NotesSummaryCard(notes: List<QuickNoteSummary>) {
    val linkedCount = notes.count { note -> note.projectId.isNotBlank() }
    val unlinkedCount = notes.size - linkedCount
    val attachmentCount = notes.sumOf { note -> note.attachmentCount }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ProjectMetric(
                label = "总数",
                value = "${notes.size} 条",
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "已关联",
                value = "$linkedCount 条",
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "未关联",
                value = "$unlinkedCount 条",
                modifier = Modifier.weight(1f)
            )
            ProjectMetric(
                label = "附件",
                value = "$attachmentCount 个",
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun NotesProjectFilterRow(
    projects: List<ProjectSummary>,
    selectedProjectId: String?,
    onSelectProject: (String?) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "项目筛选",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        FilterChip(
            selected = selectedProjectId == null,
            onClick = { onSelectProject(null) },
            label = { Text("全部") }
        )
        projects.take(6).forEach { project ->
            FilterChip(
                selected = selectedProjectId == project.id,
                onClick = { onSelectProject(project.id) },
                label = { Text(project.name) }
            )
        }
    }
}


@Composable
private fun QuickNoteRow(
    note: QuickNoteSummary,
    onOpenProject: () -> Unit,
    onEdit: () -> Unit,
    onAddAttachment: () -> Unit,
    onOpenAttachment: (QuickNoteAttachmentSummary) -> Unit,
    onDeleteAttachment: (QuickNoteAttachmentSummary) -> Unit,
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
                Text(
                    text = note.title.ifBlank { "未命名记录" },
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = note.updatedAt.ifBlank { note.createdAt },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                text = note.content.ifBlank { "未填写内容" },
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = noteMetaText(note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (note.attachments.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    note.attachments.forEach { attachment ->
                        QuickNoteAttachmentRow(
                            attachment = attachment,
                            onOpen = { onOpenAttachment(attachment) },
                            onDelete = { onDeleteAttachment(attachment) }
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(
                    enabled = note.projectId.isNotBlank(),
                    onClick = onOpenProject
                ) {
                    Text("项目")
                }
                TextButton(onClick = onAddAttachment) {
                    Text("附件")
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
private fun QuickNoteAttachmentRow(
    attachment: QuickNoteAttachmentSummary,
    onOpen: () -> Unit,
    onDelete: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = attachment.originalName.ifBlank { attachment.fileName },
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = quickNoteAttachmentMetaText(attachment),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        TextButton(
            enabled = attachment.fileName.isNotBlank(),
            onClick = onOpen
        ) {
            Text("打开")
        }
        TextButton(onClick = onDelete) {
            Text("移除")
        }
    }
}
