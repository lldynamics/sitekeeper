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
internal fun ChecklistScreen(
    projectRepository: ProjectRepository,
    onOpenProject: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    val todos by projectRepository.checklistTodos.collectAsStateWithLifecycle(initialValue = emptyList())
    var statusFilter by rememberSaveable { mutableStateOf(ChecklistStatusFilter.Open) }
    var priorityFilter by rememberSaveable { mutableStateOf(ChecklistPriorityFilter.All) }
    var ownerQuery by rememberSaveable { mutableStateOf("") }
    var editingTodoId by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmingDeleteId by rememberSaveable { mutableStateOf<String?>(null) }
    val visibleTodos = remember(todos, statusFilter, priorityFilter, ownerQuery) {
        todos
            .filterChecklistBy(
                statusFilter = statusFilter,
                priorityFilter = priorityFilter,
                ownerQuery = ownerQuery
            )
            .sortForChecklist()
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "清单",
                    style = MaterialTheme.typography.headlineMedium
                )
                Text(
                    text = "跨项目跟进未完成、逾期和高优先级待办。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            ChecklistSummaryCard(todos = todos)
        }

        item {
            ChecklistStatusFilterRow(
                selectedFilter = statusFilter,
                onSelectFilter = { statusFilter = it }
            )
        }

        item {
            ChecklistPriorityFilterRow(
                selectedFilter = priorityFilter,
                onSelectFilter = { priorityFilter = it }
            )
        }

        item {
            OutlinedTextField(
                value = ownerQuery,
                onValueChange = { ownerQuery = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("筛选负责人、事项或项目") },
                singleLine = true
            )
        }

        if (visibleTodos.isEmpty()) {
            item {
                ChecklistEmptyCard(
                    title = checklistEmptyTitle(statusFilter),
                    message = "可切换筛选条件，或从项目详情添加待办。"
                )
            }
        } else {
            items(
                items = visibleTodos,
                key = ChecklistTodoSummary::id
            ) { todo ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ChecklistTodoRow(
                        todo = todo,
                        onOpenProject = {
                            if (todo.projectId.isNotBlank()) {
                                onOpenProject(todo.projectId)
                            }
                        },
                        onEdit = {
                            editingTodoId = if (editingTodoId == todo.id) {
                                null
                            } else {
                                todo.id
                            }
                        },
                        onToggleDone = {
                            scope.launch {
                                projectRepository.setSiteTodoDone(
                                    todoId = todo.id,
                                    isDone = !todo.isDone
                                )
                            }
                        },
                        onDeleteRequest = { confirmingDeleteId = todo.id }
                    )
                    if (confirmingDeleteId == todo.id) {
                        ConfirmDeleteRow(
                            label = "删除这条待办？",
                            onCancel = { confirmingDeleteId = null },
                            onConfirm = {
                                scope.launch {
                                    projectRepository.deleteSiteTodo(todo.id)
                                }
                                confirmingDeleteId = null
                                editingTodoId = null
                            }
                        )
                    }
                    if (editingTodoId == todo.id) {
                        SiteTodoFormCard(
                            formKey = "checklist-edit-${todo.id}",
                            titleText = "编辑待办整改",
                            initialTitle = todo.title,
                            initialOwner = todo.owner,
                            initialDueDate = todo.dueDate,
                            initialPriority = todo.priority,
                            initialIssueType = todo.issueType,
                            initialLinkedMethodIds = todo.linkedConstructionMethodIds,
                            onCancel = { editingTodoId = null },
                            onSave = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                                scope.launch {
                                    projectRepository.updateSiteTodo(
                                        todoId = todo.id,
                                        title = title,
                                        owner = owner,
                                        dueDate = dueDate,
                                        priority = priority,
                                        issueType = issueType,
                                        linkedConstructionMethodIds = linkedMethodIds
                                    )
                                }
                                editingTodoId = null
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ChecklistSummaryCard(todos: List<ChecklistTodoSummary>) {
    val activeTodos = todos.filter { todo -> !todo.isProjectArchived }
    val openCount = activeTodos.count { todo -> !todo.isDone }
    val overdueCount = activeTodos.count { todo -> todo.isOverdue }
    val highPriorityCount = activeTodos.count { todo ->
        !todo.isDone && todo.priority == "高"
    }
    val doneCount = activeTodos.count { todo -> todo.isDone }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = "待办汇总",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "未完成",
                    value = "$openCount 项",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "逾期",
                    value = "$overdueCount 项",
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "高优先级",
                    value = "$highPriorityCount 项",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "已完成",
                    value = "$doneCount 项",
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun ChecklistStatusFilterRow(
    selectedFilter: ChecklistStatusFilter,
    onSelectFilter: (ChecklistStatusFilter) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ChecklistStatusFilter.entries.forEach { filter ->
            FilterChip(
                selected = selectedFilter == filter,
                onClick = { onSelectFilter(filter) },
                label = { Text(filter.title) }
            )
        }
    }
}

@Composable
private fun ChecklistPriorityFilterRow(
    selectedFilter: ChecklistPriorityFilter,
    onSelectFilter: (ChecklistPriorityFilter) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ChecklistPriorityFilter.entries.forEach { filter ->
            FilterChip(
                selected = selectedFilter == filter,
                onClick = { onSelectFilter(filter) },
                label = { Text(filter.title) }
            )
        }
    }
}

@Composable
private fun ChecklistTodoRow(
    todo: ChecklistTodoSummary,
    onOpenProject: () -> Unit,
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
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = todo.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(todo.projectName, todo.projectLocation)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = checklistTodoStateText(todo),
                    style = MaterialTheme.typography.labelLarge,
                    color = if (todo.isOverdue) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
            Text(
                text = listOf(todo.issueType, todo.priority, todo.owner, todo.dueDate)
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
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(
                    enabled = todo.projectId.isNotBlank(),
                    onClick = onOpenProject
                ) {
                    Text("项目")
                }
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
private fun ChecklistEmptyCard(
    title: String,
    message: String
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
