package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import com.chengjinfang.sitekeeper.database.project.ProjectSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private enum class RootModule(val title: String) {
    Dashboard("首页"),
    Projects("项目"),
    Checklist("清单"),
    Notes("随手记"),
    Profile("我的")
}

@Composable
fun SitekeeperApp(
    projectRepository: ProjectRepository,
    seedInitialData: suspend () -> Unit
) {
    var selectedModule by rememberSaveable { mutableStateOf(RootModule.Projects) }
    val projects by projectRepository.projects.collectAsStateWithLifecycle(initialValue = emptyList())

    LaunchedEffect(Unit) {
        seedInitialData()
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                RootModule.entries.forEach { module ->
                    NavigationBarItem(
                        selected = selectedModule == module,
                        onClick = { selectedModule = module },
                        icon = {},
                        label = { Text(module.title) }
                    )
                }
            }
        }
    ) { padding ->
        ModuleContent(
            projectRepository = projectRepository,
            selectedModule = selectedModule,
            projects = projects,
            padding = padding
        )
    }
}

@Composable
private fun ModuleContent(
    projectRepository: ProjectRepository,
    selectedModule: RootModule,
    projects: List<ProjectSummary>,
    padding: PaddingValues
) {
    Surface(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        color = MaterialTheme.colorScheme.background
    ) {
        when (selectedModule) {
            RootModule.Projects -> ProjectsScreen(
                projectRepository = projectRepository,
                projects = projects
            )
            else -> ModulePlaceholder(selectedModule = selectedModule)
        }
    }
}

@Composable
private fun ProjectsScreen(
    projectRepository: ProjectRepository,
    projects: List<ProjectSummary>
) {
    var selectedProjectId by rememberSaveable { mutableStateOf<String?>(null) }
    var showProjectForm by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val selectedDetail = rememberProjectDetail(
        projectRepository = projectRepository,
        selectedProjectId = selectedProjectId
    )

    if (selectedProjectId != null) {
        selectedDetail?.let { detail ->
            ProjectDetailScreen(
                detail = detail,
                onBack = { selectedProjectId = null },
                onAddDailyLog = { date, content, workers, weather ->
                    scope.launch {
                        projectRepository.addDailyLog(
                            projectId = detail.project.id,
                            date = date,
                            content = content,
                            workers = workers,
                            weather = weather
                        )
                    }
                },
                onAddSiteTodo = { title, owner, dueDate, priority, issueType ->
                    scope.launch {
                        projectRepository.addSiteTodo(
                            projectId = detail.project.id,
                            title = title,
                            owner = owner,
                            dueDate = dueDate,
                            priority = priority,
                            issueType = issueType
                        )
                    }
                }
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "项目",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    TextButton(onClick = { showProjectForm = !showProjectForm }) {
                        Text(if (showProjectForm) "收起" else "新建项目")
                    }
                }
                Text(
                    text = "正在跟进的工程项目、合同金额和收款状态。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (showProjectForm) {
            item {
                ProjectFormCard(
                    onCancel = { showProjectForm = false },
                    onSave = { name, location, managerName, contractAmount, expectedEndDate ->
                        scope.launch {
                            val projectId = projectRepository.addProject(
                                name = name,
                                location = location,
                                managerName = managerName,
                                contractAmount = contractAmount,
                                expectedEndDate = expectedEndDate
                            )
                            showProjectForm = false
                            selectedProjectId = projectId
                        }
                    }
                )
            }
        }

        if (projects.isEmpty()) {
            item {
                EmptyProjectState()
            }
        } else {
            items(
                items = projects,
                key = ProjectSummary::id
            ) { project ->
                ProjectRow(
                    project = project,
                    onClick = { selectedProjectId = project.id }
                )
            }
        }
    }
}

@Composable
private fun rememberProjectDetail(
    projectRepository: ProjectRepository,
    selectedProjectId: String?
): ProjectDetail? {
    if (selectedProjectId == null) {
        return null
    }

    val detailFlow = remember(selectedProjectId) {
        projectRepository.observeProjectDetail(selectedProjectId)
    }
    val detail by detailFlow.collectAsStateWithLifecycle(initialValue = null)
    return detail
}

@Composable
private fun ProjectRow(
    project: ProjectSummary,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
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
                        text = project.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(project.location, project.managerName)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = project.status,
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
                    label = "收款",
                    value = project.paymentStatus,
                    modifier = Modifier.weight(1f)
                )
            }

            if (project.expectedEndDate.isNotBlank()) {
                Text(
                    text = "计划完工：${project.expectedEndDate}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "日志",
                    value = "${project.dailyLogCount} 条",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "待办",
                    value = "${project.openTodoCount} 项",
                    modifier = Modifier.weight(1f)
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "收支",
                    value = "${project.financialRecordCount} 笔",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "材料",
                    value = "${project.materialItemCount} 项",
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun ProjectMetric(
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
private fun ProjectFormCard(
    onCancel: () -> Unit,
    onSave: (
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ) -> Unit
) {
    var name by rememberSaveable { mutableStateOf("") }
    var location by rememberSaveable { mutableStateOf("") }
    var managerName by rememberSaveable { mutableStateOf("") }
    var contractAmount by rememberSaveable { mutableStateOf("") }
    var expectedEndDate by rememberSaveable { mutableStateOf("") }

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
                text = "新建项目",
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
private fun DailyLogFormCard(
    onCancel: () -> Unit,
    onSave: (date: String, content: String, workers: String, weather: String) -> Unit
) {
    val today = remember { todayText() }
    var date by rememberSaveable { mutableStateOf(today) }
    var content by rememberSaveable { mutableStateOf("") }
    var workers by rememberSaveable { mutableStateOf("") }
    var weather by rememberSaveable { mutableStateOf("") }

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
                text = "添加施工日志",
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
            FormActionRow(
                enabled = content.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(date, content, workers, weather)
                }
            )
        }
    }
}

@Composable
private fun SiteTodoFormCard(
    onCancel: () -> Unit,
    onSave: (
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String
    ) -> Unit
) {
    val today = remember { todayText() }
    var title by rememberSaveable { mutableStateOf("") }
    var owner by rememberSaveable { mutableStateOf("") }
    var dueDate by rememberSaveable { mutableStateOf(today) }
    var priority by rememberSaveable { mutableStateOf("普通") }
    var issueType by rememberSaveable { mutableStateOf("现场") }

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
                text = "添加待办整改",
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
            FormActionRow(
                enabled = title.isNotBlank(),
                onCancel = onCancel,
                onSave = {
                    onSave(title, owner, dueDate, priority, issueType)
                }
            )
        }
    }
}

@Composable
private fun FormTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    singleLine: Boolean = true
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = singleLine
    )
}

@Composable
private fun FormActionRow(
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
private fun ProjectDetailScreen(
    detail: ProjectDetail,
    onBack: () -> Unit,
    onAddDailyLog: (date: String, content: String, workers: String, weather: String) -> Unit,
    onAddSiteTodo: (title: String, owner: String, dueDate: String, priority: String, issueType: String) -> Unit
) {
    var showDailyLogForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }
    var showTodoForm by rememberSaveable(detail.project.id) { mutableStateOf(false) }

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
            }
        }

        item {
            ProjectDetailMetricRow(project = detail.project)
        }

        item {
            FinanceOverviewCard(records = detail.financialRecords)
        }

        item {
            SectionTitle(title = "收支记录", count = detail.financialRecords.size)
        }

        if (detail.financialRecords.isEmpty()) {
            item {
                CompactEmptyText("暂无收支记录")
            }
        } else {
            items(
                items = detail.financialRecords,
                key = ProjectFinancialRecordSummary::id
            ) { record ->
                FinancialRecordRow(record = record)
            }
        }

        item {
            SectionTitle(title = "材料状态", count = detail.materialItems.size)
        }

        if (detail.materialItems.isEmpty()) {
            item {
                CompactEmptyText("暂无材料记录")
            }
        } else {
            items(
                items = detail.materialItems,
                key = MaterialItemSummary::id
            ) { material ->
                MaterialItemRow(material = material)
            }
        }

        item {
            SectionTitle(
                title = "施工日志",
                count = detail.dailyLogs.size,
                actionLabel = if (showDailyLogForm) "收起" else "添加日志",
                onAction = { showDailyLogForm = !showDailyLogForm }
            )
        }

        if (showDailyLogForm) {
            item {
                DailyLogFormCard(
                    onCancel = { showDailyLogForm = false },
                    onSave = { date, content, workers, weather ->
                        onAddDailyLog(date, content, workers, weather)
                        showDailyLogForm = false
                    }
                )
            }
        }

        if (detail.dailyLogs.isEmpty()) {
            item {
                CompactEmptyText("暂无施工日志")
            }
        } else {
            items(
                items = detail.dailyLogs,
                key = DailyLogSummary::id
            ) { log ->
                DailyLogRow(log = log)
            }
        }

        item {
            SectionTitle(
                title = "待办整改",
                count = detail.siteTodos.count { !it.isDone },
                actionLabel = if (showTodoForm) "收起" else "添加待办",
                onAction = { showTodoForm = !showTodoForm }
            )
        }

        if (showTodoForm) {
            item {
                SiteTodoFormCard(
                    onCancel = { showTodoForm = false },
                    onSave = { title, owner, dueDate, priority, issueType ->
                        onAddSiteTodo(title, owner, dueDate, priority, issueType)
                        showTodoForm = false
                    }
                )
            }
        }

        if (detail.siteTodos.isEmpty()) {
            item {
                CompactEmptyText("暂无待办")
            }
        } else {
            items(
                items = detail.siteTodos,
                key = SiteTodoSummary::id
            ) { todo ->
                SiteTodoRow(todo = todo)
            }
        }
    }
}

@Composable
private fun FinanceOverviewCard(records: List<ProjectFinancialRecordSummary>) {
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
private fun FinancialRecordRow(record: ProjectFinancialRecordSummary) {
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
            if (record.note.isNotBlank()) {
                Text(
                    text = record.note,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun MaterialItemRow(material: MaterialItemSummary) {
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
        }
    }
}

@Composable
private fun ProjectDetailMetricRow(project: ProjectSummary) {
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
private fun SectionTitle(
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
private fun DailyLogRow(log: DailyLogSummary) {
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
        }
    }
}

@Composable
private fun SiteTodoRow(todo: SiteTodoSummary) {
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
        }
    }
}

@Composable
private fun CompactEmptyText(text: String) {
    Text(
        text = text,
        modifier = Modifier.padding(vertical = 8.dp),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

private fun amountValue(text: String): Double =
    text
        .replace(",", "")
        .trim()
        .toDoubleOrNull()
        ?: 0.0

private fun moneyText(value: Double): String =
    if (value % 1.0 == 0.0) {
        String.format(Locale.US, "%.0f", value)
    } else {
        String.format(Locale.US, "%.2f", value)
    }

private fun todayText(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

@Composable
private fun EmptyProjectState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "暂无项目",
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = "等待导入备份或新建项目。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun ModulePlaceholder(selectedModule: RootModule) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = selectedModule.title,
            style = MaterialTheme.typography.headlineMedium
        )
        Text(
            text = "暂无记录",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(8.dp))
    }
}
