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
internal fun QuickNoteFormCard(
    formKey: String = "new-quick-note",
    titleText: String = "新建随手记",
    projects: List<ProjectSummary>,
    initialTitle: String = "",
    initialContent: String = "",
    initialProjectId: String? = null,
    onCancel: () -> Unit,
    onSave: (
        title: String,
        content: String,
        projectId: String?
    ) -> Unit
) {
    var title by rememberSaveable(formKey, initialTitle) { mutableStateOf(initialTitle) }
    var content by rememberSaveable(formKey, initialContent) { mutableStateOf(initialContent) }
    var projectId by rememberSaveable(formKey, initialProjectId) { mutableStateOf(initialProjectId) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = title,
                onValueChange = { title = it },
                label = "标题"
            )
            FormTextField(
                value = content,
                onValueChange = { content = it },
                label = "内容",
                singleLine = false
            )
            QuickNoteProjectPicker(
                projects = projects,
                selectedProjectId = projectId,
                onSelectProject = { projectId = it }
            )
            FormActionRow(
                enabled = title.isNotBlank() || content.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(
                        title.ifBlank { content.take(18) },
                        content,
                        projectId
                    )
                }
            )
        }
    }
}

@Composable
internal fun QuickNoteProjectPicker(
    projects: List<ProjectSummary>,
    selectedProjectId: String?,
    onSelectProject: (String?) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "关联项目",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        FilterChip(
            selected = selectedProjectId == null,
            onClick = { onSelectProject(null) },
            label = { Text("不关联") }
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
internal fun ProjectFormCard(
    formKey: String = "new-project",
    title: String = "新建项目",
    initialName: String = "",
    initialLocation: String = "",
    initialManagerName: String = "",
    initialContractAmount: String = "",
    initialExpectedEndDate: String = "",
    onCancel: () -> Unit,
    onSave: (
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initialName) { mutableStateOf(initialName) }
    var location by rememberSaveable(formKey, initialLocation) { mutableStateOf(initialLocation) }
    var managerName by rememberSaveable(formKey, initialManagerName) { mutableStateOf(initialManagerName) }
    var contractAmount by rememberSaveable(formKey, initialContractAmount) { mutableStateOf(initialContractAmount) }
    var expectedEndDate by rememberSaveable(formKey, initialExpectedEndDate) { mutableStateOf(initialExpectedEndDate) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = name,
                onValueChange = { name = it },
                label = "项目名称"
            )
            FormTextField(
                value = location,
                onValueChange = { location = it },
                label = "地点"
            )
            FormTextField(
                value = managerName,
                onValueChange = { managerName = it },
                label = "负责人"
            )
            FormTextField(
                value = contractAmount,
                onValueChange = { contractAmount = it },
                label = "合同金额"
            )
            FormTextField(
                value = expectedEndDate,
                onValueChange = { expectedEndDate = it },
                label = "计划完工"
            )
            FormActionRow(
                enabled = name.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(name, location, managerName, contractAmount, expectedEndDate)
                }
            )
        }
    }
}

@Composable
internal fun DailyLogFormCard(
    formKey: String = "new-daily-log",
    title: String = "添加施工日志",
    availableMethods: List<ConstructionMethodSummary> = emptyList(),
    initialDate: String? = null,
    initialContent: String = "",
    initialWorkers: String = "",
    initialWeather: String = "",
    initialLinkedMethodIds: List<String> = emptyList(),
    onCancel: () -> Unit,
    onSave: (date: String, content: String, workers: String, weather: String, linkedMethodIds: List<String>) -> Unit
) {
    val today = remember { todayText() }
    var date by rememberSaveable(formKey, initialDate) { mutableStateOf(initialDate ?: today) }
    var content by rememberSaveable(formKey, initialContent) { mutableStateOf(initialContent) }
    var workers by rememberSaveable(formKey, initialWorkers) { mutableStateOf(initialWorkers) }
    var weather by rememberSaveable(formKey, initialWeather) { mutableStateOf(initialWeather) }
    var linkedMethodIds by rememberSaveable(formKey, initialLinkedMethodIds) { mutableStateOf(initialLinkedMethodIds) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = date,
                onValueChange = { date = it },
                label = "日期"
            )
            FormTextField(
                value = weather,
                onValueChange = { weather = it },
                label = "天气"
            )
            FormTextField(
                value = workers,
                onValueChange = { workers = it },
                label = "人数"
            )
            FormTextField(
                value = content,
                onValueChange = { content = it },
                label = "施工内容",
                singleLine = false
            )
            ConstructionMethodPicker(
                methods = availableMethods,
                selectedIds = linkedMethodIds,
                onSelectedIdsChange = { linkedMethodIds = it }
            )
            FormActionRow(
                enabled = content.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(date, content, workers, weather, linkedMethodIds)
                }
            )
        }
    }
}

@Composable
internal fun ProgressTaskFormCard(
    formKey: String = "new-progress-task",
    titleText: String = "添加进度任务",
    initialTitle: String = "",
    initialStartDate: String? = null,
    initialDueDate: String = "",
    initialCompletion: String = "",
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        title: String,
        startDate: String,
        dueDate: String,
        completion: String,
        note: String
    ) -> Unit
) {
    val today = remember { todayText() }
    var title by rememberSaveable(formKey, initialTitle) { mutableStateOf(initialTitle) }
    var startDate by rememberSaveable(formKey, initialStartDate) { mutableStateOf(initialStartDate ?: today) }
    var dueDate by rememberSaveable(formKey, initialDueDate) { mutableStateOf(initialDueDate) }
    var completion by rememberSaveable(formKey, initialCompletion) { mutableStateOf(initialCompletion) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = title,
                onValueChange = { title = it },
                label = "任务"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = startDate,
                    onValueChange = { startDate = it },
                    label = "开始",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = dueDate,
                    onValueChange = { dueDate = it },
                    label = "截止",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = completion,
                onValueChange = { completion = it },
                label = "完成度"
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = title.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(title, startDate, dueDate, completion, note)
                }
            )
        }
    }
}

@Composable
internal fun ProjectContactFormCard(
    formKey: String = "new-project-contact",
    title: String = "添加联系人",
    initialName: String = "",
    initialRole: String = "业主",
    initialCompany: String = "",
    initialPhone: String = "",
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initialName) { mutableStateOf(initialName) }
    var role by rememberSaveable(formKey, initialRole) { mutableStateOf(initialRole) }
    var company by rememberSaveable(formKey, initialCompany) { mutableStateOf(initialCompany) }
    var phone by rememberSaveable(formKey, initialPhone) { mutableStateOf(initialPhone) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = name,
                onValueChange = { name = it },
                label = "姓名"
            )
            FormTextField(
                value = role,
                onValueChange = { role = it },
                label = "角色"
            )
            FormTextField(
                value = company,
                onValueChange = { company = it },
                label = "单位"
            )
            FormTextField(
                value = phone,
                onValueChange = { phone = it },
                label = "电话"
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = name.isNotBlank() || phone.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(name, role, company, phone, note)
                }
            )
        }
    }
}

@Composable
internal fun ProjectDocumentFormCard(
    formKey: String = "new-project-document",
    titleText: String = "添加项目资料",
    availableMethods: List<ConstructionMethodSummary> = emptyList(),
    initialTitle: String = "",
    initialCategory: String = "施工资料",
    initialFileName: String = "",
    initialFileType: String = "pdf",
    initialPageCount: String = "1",
    initialAmount: String = "",
    initialNote: String = "",
    initialLinkedMethodIds: List<String> = emptyList(),
    onCancel: () -> Unit,
    onSave: (
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedMethodIds: List<String>
    ) -> Unit
) {
    var title by rememberSaveable(formKey, initialTitle) { mutableStateOf(initialTitle) }
    var category by rememberSaveable(formKey, initialCategory) { mutableStateOf(initialCategory) }
    var fileName by rememberSaveable(formKey, initialFileName) { mutableStateOf(initialFileName) }
    var fileType by rememberSaveable(formKey, initialFileType) { mutableStateOf(initialFileType) }
    var pageCount by rememberSaveable(formKey, initialPageCount) { mutableStateOf(initialPageCount) }
    var amount by rememberSaveable(formKey, initialAmount) { mutableStateOf(initialAmount) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }
    var linkedMethodIds by rememberSaveable(formKey, initialLinkedMethodIds) { mutableStateOf(initialLinkedMethodIds) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = title,
                onValueChange = { title = it },
                label = "资料名称"
            )
            FormTextField(
                value = category,
                onValueChange = { category = it },
                label = "分类"
            )
            FormTextField(
                value = fileName,
                onValueChange = { fileName = it },
                label = "文件名"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = fileType,
                    onValueChange = { fileType = it },
                    label = "类型",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = pageCount,
                    onValueChange = { pageCount = it },
                    label = "页数",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = amount,
                onValueChange = { amount = it },
                label = "金额"
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            ConstructionMethodPicker(
                methods = availableMethods,
                selectedIds = linkedMethodIds,
                onSelectedIdsChange = { linkedMethodIds = it }
            )
            FormActionRow(
                enabled = title.isNotBlank() || fileName.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds)
                }
            )
        }
    }
}

@Composable
internal fun ProjectDrawingFormCard(
    formKey: String = "new-project-drawing",
    titleText: String = "添加项目图纸",
    initialName: String = "",
    initialFileName: String = "",
    initialFileType: String = "pdf",
    initialVersion: String = "V1",
    initialRelatedLogDate: String = "",
    initialIssueStatus: String = "无问题",
    initialIssueNote: String = "",
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initialName) { mutableStateOf(initialName) }
    var fileName by rememberSaveable(formKey, initialFileName) { mutableStateOf(initialFileName) }
    var fileType by rememberSaveable(formKey, initialFileType) { mutableStateOf(initialFileType) }
    var version by rememberSaveable(formKey, initialVersion) { mutableStateOf(initialVersion) }
    var relatedLogDate by rememberSaveable(formKey, initialRelatedLogDate) { mutableStateOf(initialRelatedLogDate) }
    var issueStatus by rememberSaveable(formKey, initialIssueStatus) { mutableStateOf(initialIssueStatus) }
    var issueNote by rememberSaveable(formKey, initialIssueNote) { mutableStateOf(initialIssueNote) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = name,
                onValueChange = { name = it },
                label = "图纸名称"
            )
            FormTextField(
                value = fileName,
                onValueChange = { fileName = it },
                label = "文件名"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = fileType,
                    onValueChange = { fileType = it },
                    label = "类型",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = version,
                    onValueChange = { version = it },
                    label = "版本",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = relatedLogDate,
                onValueChange = { relatedLogDate = it },
                label = "关联日期"
            )
            FormTextField(
                value = issueStatus,
                onValueChange = { issueStatus = it },
                label = "问题状态"
            )
            FormTextField(
                value = issueNote,
                onValueChange = { issueNote = it },
                label = "问题说明",
                singleLine = false
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = name.isNotBlank() || fileName.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note)
                }
            )
        }
    }
}

@Composable
internal fun SiteTodoFormCard(
    formKey: String = "new-site-todo",
    titleText: String = "添加待办整改",
    availableMethods: List<ConstructionMethodSummary> = emptyList(),
    initialTitle: String = "",
    initialOwner: String = "",
    initialDueDate: String? = null,
    initialPriority: String = "普通",
    initialIssueType: String = "现场",
    initialLinkedMethodIds: List<String> = emptyList(),
    onCancel: () -> Unit,
    onSave: (
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String,
        linkedMethodIds: List<String>
    ) -> Unit
) {
    val today = remember { todayText() }
    var title by rememberSaveable(formKey, initialTitle) { mutableStateOf(initialTitle) }
    var owner by rememberSaveable(formKey, initialOwner) { mutableStateOf(initialOwner) }
    var dueDate by rememberSaveable(formKey, initialDueDate) { mutableStateOf(initialDueDate ?: today) }
    var priority by rememberSaveable(formKey, initialPriority) { mutableStateOf(initialPriority) }
    var issueType by rememberSaveable(formKey, initialIssueType) { mutableStateOf(initialIssueType) }
    var linkedMethodIds by rememberSaveable(formKey, initialLinkedMethodIds) { mutableStateOf(initialLinkedMethodIds) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = title,
                onValueChange = { title = it },
                label = "事项"
            )
            FormTextField(
                value = issueType,
                onValueChange = { issueType = it },
                label = "类型"
            )
            FormTextField(
                value = owner,
                onValueChange = { owner = it },
                label = "负责人"
            )
            FormTextField(
                value = dueDate,
                onValueChange = { dueDate = it },
                label = "截止日期"
            )
            FormTextField(
                value = priority,
                onValueChange = { priority = it },
                label = "优先级"
            )
            ConstructionMethodPicker(
                methods = availableMethods,
                selectedIds = linkedMethodIds,
                onSelectedIdsChange = { linkedMethodIds = it }
            )
            FormActionRow(
                enabled = title.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(title, owner, dueDate, priority, issueType, linkedMethodIds)
                }
            )
        }
    }
}

@Composable
internal fun QuoteItemFormCard(
    formKey: String = "new-quote-item",
    titleText: String = "添加报价项",
    initialName: String = "",
    initialUnitPrice: String = "",
    initialQuantity: String = "",
    initialUnit: String = "项",
    initialVersionName: String = "V1",
    initialStatus: String = "草稿",
    initialCustomerConfirmedDate: String = "",
    initialContractAmount: String = "",
    initialNotes: String = "",
    onCancel: () -> Unit,
    onSave: (
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initialName) { mutableStateOf(initialName) }
    var unitPrice by rememberSaveable(formKey, initialUnitPrice) { mutableStateOf(initialUnitPrice) }
    var quantity by rememberSaveable(formKey, initialQuantity) { mutableStateOf(initialQuantity) }
    var unit by rememberSaveable(formKey, initialUnit) { mutableStateOf(initialUnit) }
    var versionName by rememberSaveable(formKey, initialVersionName) { mutableStateOf(initialVersionName) }
    var status by rememberSaveable(formKey, initialStatus) { mutableStateOf(initialStatus) }
    var customerConfirmedDate by rememberSaveable(formKey, initialCustomerConfirmedDate) {
        mutableStateOf(initialCustomerConfirmedDate)
    }
    var contractAmount by rememberSaveable(formKey, initialContractAmount) { mutableStateOf(initialContractAmount) }
    var notes by rememberSaveable(formKey, initialNotes) { mutableStateOf(initialNotes) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = name,
                onValueChange = { name = it },
                label = "项目"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = unitPrice,
                    onValueChange = { unitPrice = it },
                    label = "单价",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = "数量",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = unit,
                    onValueChange = { unit = it },
                    label = "单位",
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = versionName,
                    onValueChange = { versionName = it },
                    label = "版本",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = status,
                    onValueChange = { status = it },
                    label = "状态",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = customerConfirmedDate,
                onValueChange = { customerConfirmedDate = it },
                label = "确认日期"
            )
            FormTextField(
                value = contractAmount,
                onValueChange = { contractAmount = it },
                label = "合同金额"
            )
            FormTextField(
                value = notes,
                onValueChange = { notes = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = name.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(
                        name,
                        unitPrice,
                        quantity,
                        unit,
                        versionName,
                        status,
                        customerConfirmedDate,
                        contractAmount,
                        notes
                    )
                }
            )
        }
    }
}

@Composable
internal fun LaborRecordFormCard(
    formKey: String = "new-labor-record",
    titleText: String = "添加人工记录",
    initialDate: String? = null,
    initialWorkers: String = "",
    initialHours: String = "",
    initialUnitRate: String = "",
    initialWorkType: String = "",
    initialTeamName: String = "",
    initialIsSettled: Boolean = false,
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) -> Unit
) {
    val today = remember { todayText() }
    var date by rememberSaveable(formKey, initialDate) { mutableStateOf(initialDate ?: today) }
    var workers by rememberSaveable(formKey, initialWorkers) { mutableStateOf(initialWorkers) }
    var hours by rememberSaveable(formKey, initialHours) { mutableStateOf(initialHours) }
    var unitRate by rememberSaveable(formKey, initialUnitRate) { mutableStateOf(initialUnitRate) }
    var workType by rememberSaveable(formKey, initialWorkType) { mutableStateOf(initialWorkType) }
    var teamName by rememberSaveable(formKey, initialTeamName) { mutableStateOf(initialTeamName) }
    var isSettled by rememberSaveable(formKey, initialIsSettled) { mutableStateOf(initialIsSettled) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = date,
                onValueChange = { date = it },
                label = "日期"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = workers,
                    onValueChange = { workers = it },
                    label = "人数",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = hours,
                    onValueChange = { hours = it },
                    label = "工日",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = unitRate,
                    onValueChange = { unitRate = it },
                    label = "单价",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = workType,
                onValueChange = { workType = it },
                label = "工种"
            )
            FormTextField(
                value = teamName,
                onValueChange = { teamName = it },
                label = "班组"
            )
            FilterChip(
                selected = isSettled,
                onClick = { isSettled = !isSettled },
                label = { Text(if (isSettled) "已结算" else "未结算") }
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = workers.isNotBlank() || workType.isNotBlank() || teamName.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(date, workers, hours, unitRate, workType, teamName, isSettled, note)
                }
            )
        }
    }
}

@Composable
internal fun WarehouseMovementFormCard(
    formKey: String = "new-warehouse-movement",
    titleText: String = "添加出入库",
    initialDate: String? = null,
    initialMovementType: String = "入库",
    initialMaterialName: String = "",
    initialSpecification: String = "",
    initialUnit: String = "件",
    initialQuantity: String = "",
    initialCounterparty: String = "",
    initialHandler: String = "",
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) -> Unit
) {
    val today = remember { todayText() }
    var date by rememberSaveable(formKey, initialDate) { mutableStateOf(initialDate ?: today) }
    var movementType by rememberSaveable(formKey, initialMovementType) { mutableStateOf(initialMovementType.ifBlank { "入库" }) }
    var materialName by rememberSaveable(formKey, initialMaterialName) { mutableStateOf(initialMaterialName) }
    var specification by rememberSaveable(formKey, initialSpecification) { mutableStateOf(initialSpecification) }
    var unit by rememberSaveable(formKey, initialUnit) { mutableStateOf(initialUnit) }
    var quantity by rememberSaveable(formKey, initialQuantity) { mutableStateOf(initialQuantity) }
    var counterparty by rememberSaveable(formKey, initialCounterparty) { mutableStateOf(initialCounterparty) }
    var handler by rememberSaveable(formKey, initialHandler) { mutableStateOf(initialHandler) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = titleText,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = movementType == "入库",
                    onClick = { movementType = "入库" },
                    label = { Text("入库") }
                )
                FilterChip(
                    selected = movementType == "出库",
                    onClick = { movementType = "出库" },
                    label = { Text("出库") }
                )
            }
            FormTextField(
                value = date,
                onValueChange = { date = it },
                label = "日期"
            )
            FormTextField(
                value = materialName,
                onValueChange = { materialName = it },
                label = "材料名称"
            )
            FormTextField(
                value = specification,
                onValueChange = { specification = it },
                label = "规格"
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                FormTextField(
                    value = quantity,
                    onValueChange = { quantity = it },
                    label = "数量",
                    modifier = Modifier.weight(1f)
                )
                FormTextField(
                    value = unit,
                    onValueChange = { unit = it },
                    label = "单位",
                    modifier = Modifier.weight(1f)
                )
            }
            FormTextField(
                value = counterparty,
                onValueChange = { counterparty = it },
                label = if (movementType == "入库") "供应商/来源" else "领用班组/去向"
            )
            FormTextField(
                value = handler,
                onValueChange = { handler = it },
                label = "经手人"
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = materialName.isNotBlank() && quantity.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(
                        date,
                        movementType,
                        materialName,
                        specification,
                        unit,
                        quantity,
                        counterparty,
                        handler,
                        note
                    )
                }
            )
        }
    }
}

@Composable
internal fun FinancialRecordFormCard(
    formKey: String = "new-financial-record",
    title: String = "添加收支记录",
    initialDate: String? = null,
    initialDirection: String = "支出",
    initialCategory: String = "材料",
    initialAmount: String = "",
    initialCounterparty: String = "",
    initialStatus: String = "待处理",
    initialDueDate: String = "",
    initialNote: String = "",
    onCancel: () -> Unit,
    onSave: (
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) -> Unit
) {
    val today = remember { todayText() }
    var date by rememberSaveable(formKey, initialDate) { mutableStateOf(initialDate ?: today) }
    var direction by rememberSaveable(formKey, initialDirection) { mutableStateOf(initialDirection) }
    var category by rememberSaveable(formKey, initialCategory) { mutableStateOf(initialCategory) }
    var amount by rememberSaveable(formKey, initialAmount) { mutableStateOf(initialAmount) }
    var counterparty by rememberSaveable(formKey, initialCounterparty) { mutableStateOf(initialCounterparty) }
    var status by rememberSaveable(formKey, initialStatus) { mutableStateOf(initialStatus) }
    var dueDate by rememberSaveable(formKey, initialDueDate) { mutableStateOf(initialDueDate) }
    var note by rememberSaveable(formKey, initialNote) { mutableStateOf(initialNote) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = date,
                onValueChange = { date = it },
                label = "日期"
            )
            FormTextField(
                value = direction,
                onValueChange = { direction = it },
                label = "收支"
            )
            FormTextField(
                value = category,
                onValueChange = { category = it },
                label = "类别"
            )
            FormTextField(
                value = amount,
                onValueChange = { amount = it },
                label = "金额"
            )
            FormTextField(
                value = counterparty,
                onValueChange = { counterparty = it },
                label = "对方单位"
            )
            FormTextField(
                value = status,
                onValueChange = { status = it },
                label = "状态"
            )
            FormTextField(
                value = dueDate,
                onValueChange = { dueDate = it },
                label = "到期日"
            )
            FormTextField(
                value = note,
                onValueChange = { note = it },
                label = "备注",
                singleLine = false
            )
            FormActionRow(
                enabled = amount.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(date, direction, category, amount, counterparty, status, dueDate, note)
                }
            )
        }
    }
}

@Composable
internal fun MaterialItemFormCard(
    formKey: String = "new-material-item",
    title: String = "添加材料",
    initialName: String = "",
    initialSpecification: String = "",
    initialQuantity: String = "",
    initialUnit: String = "项",
    initialUnitPrice: String = "",
    initialSupplier: String = "",
    initialPurchaseStatus: String = "待采购",
    initialArrivalDate: String = "",
    onCancel: () -> Unit,
    onSave: (
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) -> Unit
) {
    var name by rememberSaveable(formKey, initialName) { mutableStateOf(initialName) }
    var specification by rememberSaveable(formKey, initialSpecification) { mutableStateOf(initialSpecification) }
    var quantity by rememberSaveable(formKey, initialQuantity) { mutableStateOf(initialQuantity) }
    var unit by rememberSaveable(formKey, initialUnit) { mutableStateOf(initialUnit) }
    var unitPrice by rememberSaveable(formKey, initialUnitPrice) { mutableStateOf(initialUnitPrice) }
    var supplier by rememberSaveable(formKey, initialSupplier) { mutableStateOf(initialSupplier) }
    var purchaseStatus by rememberSaveable(formKey, initialPurchaseStatus) { mutableStateOf(initialPurchaseStatus) }
    var arrivalDate by rememberSaveable(formKey, initialArrivalDate) { mutableStateOf(initialArrivalDate) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            FormTextField(
                value = name,
                onValueChange = { name = it },
                label = "材料名称"
            )
            FormTextField(
                value = specification,
                onValueChange = { specification = it },
                label = "规格"
            )
            FormTextField(
                value = quantity,
                onValueChange = { quantity = it },
                label = "数量"
            )
            FormTextField(
                value = unit,
                onValueChange = { unit = it },
                label = "单位"
            )
            FormTextField(
                value = unitPrice,
                onValueChange = { unitPrice = it },
                label = "单价"
            )
            FormTextField(
                value = supplier,
                onValueChange = { supplier = it },
                label = "供应商"
            )
            FormTextField(
                value = purchaseStatus,
                onValueChange = { purchaseStatus = it },
                label = "采购状态"
            )
            FormTextField(
                value = arrivalDate,
                onValueChange = { arrivalDate = it },
                label = "进场日期"
            )
            FormActionRow(
                enabled = name.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate)
                }
            )
        }
    }
}

@Composable
internal fun FormTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    singleLine: Boolean = true,
    modifier: Modifier = Modifier.fillMaxWidth()
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        label = { Text(label) },
        singleLine = singleLine
    )
}

@Composable
internal fun FormActionRow(
    enabled: Boolean,
    onCancel: () -> Unit,
    onSave: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
        verticalAlignment = Alignment.CenterVertically
    ) {
        TextButton(onClick = onCancel) {
            Text("取消")
        }
        Button(
            enabled = enabled,
            onClick = onSave
        ) {
            Text("保存")
        }
    }
}

@Composable
internal fun ConstructionMethodPicker(
    methods: List<ConstructionMethodSummary>,
    selectedIds: List<String>,
    onSelectedIdsChange: (List<String>) -> Unit
) {
    if (methods.isEmpty() && selectedIds.isEmpty()) {
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = "关联施工工艺",
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        if (methods.isEmpty()) {
            Text(
                text = "已关联 ${selectedIds.size} 条工艺",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                methods.forEach { method ->
                    val selected = method.id in selectedIds
                    FilterChip(
                        selected = selected,
                        onClick = {
                            onSelectedIdsChange(
                                if (selected) {
                                    selectedIds.filterNot { it == method.id }
                                } else {
                                    selectedIds + method.id
                                }
                            )
                        },
                        label = {
                            Text(
                                listOf(method.displayTitle, method.trade)
                                    .filter(String::isNotBlank)
                                    .joinToString(" · ")
                            )
                        }
                    )
                }
            }
        }
    }
}

@Composable
internal fun LinkedConstructionMethodText(titles: List<String>) {
    if (titles.isEmpty()) {
        return
    }
    Text(
        text = "关联工艺：${titles.joinToString("、")}",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.primary,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
internal fun ConfirmDeleteRow(
    label: String,
    onCancel: () -> Unit,
    onConfirm: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = label,
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onErrorContainer
            )
            TextButton(onClick = onCancel) {
                Text("取消")
            }
            Button(onClick = onConfirm) {
                Text("确认删除")
            }
        }
    }
}
