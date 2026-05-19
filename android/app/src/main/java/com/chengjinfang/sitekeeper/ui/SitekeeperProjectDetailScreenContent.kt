package com.chengjinfang.sitekeeper.ui

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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
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
import com.chengjinfang.sitekeeper.delivery.projectDeliveryPackagePreflightSummaryText
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskSummary
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
internal fun ProjectDetailScreenContent(
    detail: ProjectDetail,
    onBack: () -> Unit,
    overviewActions: ProjectOverviewActions,
    dailyTodoActions: ProjectDailyTodoActions,
    financeMaterialActions: ProjectFinanceMaterialActions,
    assetsActions: ProjectAssetsActions,
    commercialActions: ProjectCommercialActions
) {
    val onUpdateProject = overviewActions.onUpdateProject
    val onSetProjectArchived = overviewActions.onSetProjectArchived
    val onAttachDailyLogPhoto = dailyTodoActions.onAttachDailyLogPhoto
    val onAddProgressTask = dailyTodoActions.onAddProgressTask
    val onUpdateProgressTask = dailyTodoActions.onUpdateProgressTask
    val onSetProgressTaskCompletion = dailyTodoActions.onSetProgressTaskCompletion
    val onDeleteProgressTask = dailyTodoActions.onDeleteProgressTask
    val onAttachSiteTodoPhoto = dailyTodoActions.onAttachSiteTodoPhoto
    val onAddProjectContact = assetsActions.onAddProjectContact
    val onUpdateProjectContact = assetsActions.onUpdateProjectContact
    val onDeleteProjectContact = assetsActions.onDeleteProjectContact
    val onAttachProjectDocumentFile = assetsActions.onAttachProjectDocumentFile
    val onAttachProjectDrawingFile = assetsActions.onAttachProjectDrawingFile
    val context = LocalContext.current
    val isArchived = detail.project.status == "已归档"
    var showProjectEditForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showFinancialRecordForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showMaterialItemForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showDailyLogForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showProgressTaskForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showTodoForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showContactForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showDocumentForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showDrawingForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showQuoteForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showLaborForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showWarehouseForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var editingFinancialRecordId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingMaterialItemId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingDailyLogId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingProgressTaskId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingTodoId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingContactId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingDocumentId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingDrawingId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingQuoteItemId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingLaborRecordId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var editingWarehouseMovementId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var confirmingDeleteKey by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    val mediaState = rememberProjectDetailMediaState(
        detail = detail,
        onAttachProjectDocumentFile = onAttachProjectDocumentFile,
        onAttachProjectDrawingFile = onAttachProjectDrawingFile,
        onAttachDailyLogPhoto = onAttachDailyLogPhoto,
        onAttachSiteTodoPhoto = onAttachSiteTodoPhoto
    )

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onBack) {
                    Text("返回项目")
                }
                Text(
                    text = detail.project.name,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = listOf(detail.project.location, detail.project.managerName)
                        .filter(String::isNotBlank)
                        .joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { showProjectEditForm = !showProjectEditForm }) {
                        Text(if (showProjectEditForm) "收起" else "编辑项目")
                    }
                    TextButton(onClick = { onSetProjectArchived(!isArchived) }) {
                        Text(if (isArchived) "恢复项目" else "归档项目")
                    }
                }
            }
        }

        if (showProjectEditForm) {
            item {
                ProjectFormCard(
                    formKey = "edit-project-${detail.project.id}",
                    title = "编辑项目",
                    initialName = detail.project.name,
                    initialLocation = detail.project.location,
                    initialManagerName = detail.project.managerName,
                    initialContractAmount = detail.project.contractAmount,
                    initialExpectedEndDate = detail.project.expectedEndDate,
                    onCancel = { showProjectEditForm = false },
                    onSave = { name, location, managerName, contractAmount, expectedEndDate ->
                        onUpdateProject(name, location, managerName, contractAmount, expectedEndDate)
                        showProjectEditForm = false
                    }
                )
            }
        }

        item {
            ProjectDetailMetricRow(project = detail.project)
        }

        item {
            ProjectTimelineSection(detail = detail)
        }

        item {
            ProjectDeliveryExportCard(
                detail = detail,
                preflight = mediaState.deliveryPreflight,
                statusText = mediaState.deliveryExportStatus,
                onExport = {
                    mediaState.launchDeliveryExport()
                }
            )
        }

        item {
            SectionTitle(
                title = "进度任务",
                count = detail.progressTasks.size,
                actionLabel = if (showProgressTaskForm) "收起" else "添加进度",
                onAction = { showProgressTaskForm = !showProgressTaskForm }
            )
        }

        if (showProgressTaskForm) {
            item {
                ProgressTaskFormCard(
                    onCancel = { showProgressTaskForm = false },
                    onSave = { title, startDate, dueDate, completion, note ->
                        onAddProgressTask(title, startDate, dueDate, completion, note)
                        showProgressTaskForm = false
                    }
                )
            }
        }

        if (detail.progressTasks.isEmpty()) {
            item {
                CompactEmptyText("暂无进度任务")
            }
        } else {
            items(
                items = detail.progressTasks,
                key = ProgressTaskSummary::id
            ) { task ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ProgressTaskRow(
                        task = task,
                        onEdit = {
                            editingProgressTaskId = if (editingProgressTaskId == task.id) {
                                null
                            } else {
                                task.id
                            }
                        },
                        onToggleDone = {
                            onSetProgressTaskCompletion(
                                task.id,
                                if (task.completion >= 1.0) 0.0 else 1.0
                            )
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "progress-${task.id}"
                        }
                    )
                    if (confirmingDeleteKey == "progress-${task.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条进度任务？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteProgressTask(task.id)
                                confirmingDeleteKey = null
                                editingProgressTaskId = null
                            }
                        )
                    }
                    if (editingProgressTaskId == task.id) {
                        ProgressTaskFormCard(
                            formKey = "edit-progress-${task.id}",
                            titleText = "编辑进度任务",
                            initialTitle = task.title,
                            initialStartDate = task.startDate,
                            initialDueDate = task.dueDate,
                            initialCompletion = progressPercentText(task.completion),
                            initialNote = task.note,
                            onCancel = { editingProgressTaskId = null },
                            onSave = { title, startDate, dueDate, completion, note ->
                                onUpdateProgressTask(
                                    task.id,
                                    title,
                                    startDate,
                                    dueDate,
                                    completion,
                                    note
                                )
                                editingProgressTaskId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "项目联系人",
                count = detail.contacts.size,
                actionLabel = if (showContactForm) "收起" else "添加联系人",
                onAction = { showContactForm = !showContactForm }
            )
        }

        if (showContactForm) {
            item {
                ProjectContactFormCard(
                    onCancel = { showContactForm = false },
                    onSave = { name, role, company, phone, note ->
                        onAddProjectContact(name, role, company, phone, note)
                        showContactForm = false
                    }
                )
            }
        }

        if (detail.contacts.isEmpty()) {
            item {
                CompactEmptyText("暂无联系人")
            }
        } else {
            items(
                items = detail.contacts,
                key = ProjectContactSummary::id
            ) { contact ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ProjectContactRow(
                        contact = contact,
                        onEdit = {
                            editingContactId = if (editingContactId == contact.id) {
                                null
                            } else {
                                contact.id
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "contact-${contact.id}"
                        }
                    )
                    if (confirmingDeleteKey == "contact-${contact.id}") {
                        ConfirmDeleteRow(
                            label = "删除这个联系人？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteProjectContact(contact.id)
                                confirmingDeleteKey = null
                                editingContactId = null
                            }
                        )
                    }
                    if (editingContactId == contact.id) {
                        ProjectContactFormCard(
                            formKey = "edit-contact-${contact.id}",
                            title = "编辑联系人",
                            initialName = contact.name,
                            initialRole = contact.role,
                            initialCompany = contact.company,
                            initialPhone = contact.phone,
                            initialNote = contact.note,
                            onCancel = { editingContactId = null },
                            onSave = { name, role, company, phone, note ->
                                onUpdateProjectContact(
                                    contact.id,
                                    name,
                                    role,
                                    company,
                                    phone,
                                    note
                                )
                                editingContactId = null
                            }
                        )
                    }
                }
            }
        }

        projectDocumentsAndDrawingsSections(
            detail = detail,
            context = context,
            mediaState = mediaState,
            actions = assetsActions,
            showDocumentForm = showDocumentForm,
            onShowDocumentFormChange = { showDocumentForm = it },
            editingDocumentId = editingDocumentId,
            onEditingDocumentIdChange = { editingDocumentId = it },
            showDrawingForm = showDrawingForm,
            onShowDrawingFormChange = { showDrawingForm = it },
            editingDrawingId = editingDrawingId,
            onEditingDrawingIdChange = { editingDrawingId = it },
            confirmingDeleteKey = confirmingDeleteKey,
            onConfirmingDeleteKeyChange = { confirmingDeleteKey = it }
        )

        item {
            FinanceOverviewCard(records = detail.financialRecords)
        }

        projectCommercialSections(
            detail = detail,
            actions = commercialActions,
            showQuoteForm = showQuoteForm,
            onShowQuoteFormChange = { showQuoteForm = it },
            editingQuoteItemId = editingQuoteItemId,
            onEditingQuoteItemIdChange = { editingQuoteItemId = it },
            showLaborForm = showLaborForm,
            onShowLaborFormChange = { showLaborForm = it },
            editingLaborRecordId = editingLaborRecordId,
            onEditingLaborRecordIdChange = { editingLaborRecordId = it },
            showWarehouseForm = showWarehouseForm,
            onShowWarehouseFormChange = { showWarehouseForm = it },
            editingWarehouseMovementId = editingWarehouseMovementId,
            onEditingWarehouseMovementIdChange = { editingWarehouseMovementId = it },
            confirmingDeleteKey = confirmingDeleteKey,
            onConfirmingDeleteKeyChange = { confirmingDeleteKey = it }
        )

        projectFinanceAndMaterialSections(
            detail = detail,
            actions = financeMaterialActions,
            showFinancialRecordForm = showFinancialRecordForm,
            onShowFinancialRecordFormChange = { showFinancialRecordForm = it },
            editingFinancialRecordId = editingFinancialRecordId,
            onEditingFinancialRecordIdChange = { editingFinancialRecordId = it },
            showMaterialItemForm = showMaterialItemForm,
            onShowMaterialItemFormChange = { showMaterialItemForm = it },
            editingMaterialItemId = editingMaterialItemId,
            onEditingMaterialItemIdChange = { editingMaterialItemId = it },
            confirmingDeleteKey = confirmingDeleteKey,
            onConfirmingDeleteKeyChange = { confirmingDeleteKey = it }
        )

        projectDailyLogAndTodoSections(
            detail = detail,
            context = context,
            mediaState = mediaState,
            actions = dailyTodoActions,
            showDailyLogForm = showDailyLogForm,
            onShowDailyLogFormChange = { showDailyLogForm = it },
            editingDailyLogId = editingDailyLogId,
            onEditingDailyLogIdChange = { editingDailyLogId = it },
            showTodoForm = showTodoForm,
            onShowTodoFormChange = { showTodoForm = it },
            editingTodoId = editingTodoId,
            onEditingTodoIdChange = { editingTodoId = it },
            confirmingDeleteKey = confirmingDeleteKey,
            onConfirmingDeleteKeyChange = { confirmingDeleteKey = it }
        )
    }
}
