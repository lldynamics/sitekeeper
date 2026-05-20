package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodSummary
import com.chengjinfang.sitekeeper.database.project.ConstructionMethodLibraryOverview
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.launch

private val CONSTRUCTION_STATUS_FILTERS = listOf("全部", "已发布", "草稿", "已废止")

@Composable
fun ConstructionMethodLibraryScreen(projectRepository: ProjectRepository) {
    val overview by projectRepository.constructionMethodLibrary.collectAsStateWithLifecycle(
        initialValue = ConstructionMethodLibraryOverview(methods = emptyList())
    )
    val scope = rememberCoroutineScope()
    var searchText by rememberSaveable { mutableStateOf("") }
    var selectedTrade by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedStatus by rememberSaveable { mutableStateOf("全部") }
    var showForm by rememberSaveable { mutableStateOf(false) }
    var editingMethodId by rememberSaveable { mutableStateOf<String?>(null) }

    val filteredMethods = overview.methods
        .filter { method -> selectedTrade == null || method.trade == selectedTrade }
        .filter { method -> selectedStatus == "全部" || method.statusLabel == selectedStatus }
        .filter { method -> constructionMethodMatches(method, searchText) }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "工程资料库",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "沉淀施工工艺、工序步骤、质量检查和安全要点，后续可关联到日志、待办和资料。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            ConstructionMethodMetrics(overview = overview)
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CONSTRUCTION_STATUS_FILTERS.forEach { status ->
                    FilterChip(
                        selected = selectedStatus == status,
                        onClick = { selectedStatus = status },
                        label = { Text(status) }
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                TextButton(
                    onClick = {
                        scope.launch { projectRepository.importDefaultConstructionMethods() }
                    }
                ) {
                    Text("补充预置")
                }
            }
        }

        item {
            ConstructionTradeFilterRow(
                trades = overview.trades,
                selectedTrade = selectedTrade,
                onSelectTrade = { selectedTrade = it }
            )
        }

        item {
            OutlinedTextField(
                value = searchText,
                onValueChange = { searchText = it },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text("搜索工艺、专业、教程、质量、安全") }
            )
        }

        item {
            Button(
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    showForm = !showForm
                    editingMethodId = null
                }
            ) {
                Text(if (showForm) "收起工艺录入" else "添加施工工艺")
            }
        }

        if (showForm) {
            item {
                ConstructionMethodFormCard(
                    formKey = "new-method",
                    onCancel = { showForm = false },
                    onSubmit = { title, trade, versionName, publishStatus, tutorialBody, steps, quality, safety ->
                        scope.launch {
                            projectRepository.addConstructionMethod(
                                title = title,
                                trade = trade,
                                versionName = versionName,
                                publishStatus = publishStatus,
                                tutorialBody = tutorialBody,
                                procedureSteps = steps,
                                qualityChecklist = quality,
                                safetyChecklist = safety
                            )
                            showForm = false
                        }
                    }
                )
            }
        }

        if (filteredMethods.isEmpty()) {
            item { ConstructionMethodEmptyText("没有匹配的施工工艺") }
        }

        items(filteredMethods, key = ConstructionMethodSummary::id) { method ->
            ConstructionMethodRow(
                method = method,
                onEdit = {
                    editingMethodId = if (editingMethodId == method.id) null else method.id
                    showForm = false
                },
                onDelete = {
                    scope.launch { projectRepository.deleteConstructionMethod(method.id) }
                }
            )
            if (editingMethodId == method.id) {
                Spacer(modifier = Modifier.height(8.dp))
                ConstructionMethodFormCard(
                    formKey = method.id,
                    initial = method,
                    onCancel = { editingMethodId = null },
                    onSubmit = { title, trade, versionName, publishStatus, tutorialBody, steps, quality, safety ->
                        scope.launch {
                            projectRepository.updateConstructionMethod(
                                methodId = method.id,
                                title = title,
                                trade = trade,
                                versionName = versionName,
                                publishStatus = publishStatus,
                                tutorialBody = tutorialBody,
                                procedureSteps = steps,
                                qualityChecklist = quality,
                                safetyChecklist = safety
                            )
                            editingMethodId = null
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun ConstructionMethodMetrics(overview: ConstructionMethodLibraryOverview) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ConstructionMetric("工艺", overview.methods.size.toString(), Modifier.weight(1f))
        ConstructionMetric("已发布", overview.publishedCount.toString(), Modifier.weight(1f))
        ConstructionMetric("草稿", overview.draftCount.toString(), Modifier.weight(1f))
        ConstructionMetric("废止", overview.deprecatedCount.toString(), Modifier.weight(1f))
    }
}

@Composable
private fun ConstructionMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun ConstructionTradeFilterRow(
    trades: List<String>,
    selectedTrade: String?,
    onSelectTrade: (String?) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        FilterChip(
            selected = selectedTrade == null,
            onClick = { onSelectTrade(null) },
            label = { Text("全部专业") }
        )
        trades.forEach { trade ->
            FilterChip(
                selected = selectedTrade == trade,
                onClick = { onSelectTrade(trade) },
                label = { Text(trade) }
            )
        }
    }
}

@Composable
private fun ConstructionMethodRow(
    method: ConstructionMethodSummary,
    onEdit: () -> Unit,
    onDelete: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = method.displayTitle,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = listOf(method.trade, method.versionName, method.statusLabel)
                            .filter(String::isNotBlank)
                            .joinToString(" · "),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    text = "${method.procedureSteps.size}/${method.qualityChecklist.size}/${method.safetyChecklist.size}",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            if (method.tutorialBody.isNotBlank()) {
                Text(
                    text = method.tutorialBody,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 3
                )
            }
            ConstructionChecklistPreview("工序", method.procedureSteps)
            ConstructionChecklistPreview("质检", method.qualityChecklist)
            ConstructionChecklistPreview("安全", method.safetyChecklist)
            if (method.attachmentCount + method.tutorialAttachmentCount > 0) {
                Text(
                    text = "附件 ${method.attachmentCount + method.tutorialAttachmentCount} 个",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onEdit) { Text("编辑") }
                TextButton(onClick = onDelete) { Text("删除") }
            }
        }
    }
}

@Composable
private fun ConstructionChecklistPreview(
    label: String,
    items: List<String>
) {
    if (items.isEmpty()) {
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = "$label ${items.size} 项",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        items.take(3).forEach { item ->
            Text(
                text = "- $item",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun ConstructionMethodFormCard(
    formKey: String,
    initial: ConstructionMethodSummary? = null,
    onCancel: () -> Unit,
    onSubmit: (
        title: String,
        trade: String,
        versionName: String,
        publishStatus: String,
        tutorialBody: String,
        steps: String,
        quality: String,
        safety: String
    ) -> Unit
) {
    var title by rememberSaveable(formKey, initial?.title) { mutableStateOf(initial?.title.orEmpty()) }
    var trade by rememberSaveable(formKey, initial?.trade) { mutableStateOf(initial?.trade ?: "电气") }
    var versionName by rememberSaveable(formKey, initial?.versionName) { mutableStateOf(initial?.versionName ?: "V1") }
    var publishStatus by rememberSaveable(formKey, initial?.publishStatus) { mutableStateOf(initial?.publishStatus ?: "草稿") }
    var tutorialBody by rememberSaveable(formKey, initial?.tutorialBody) { mutableStateOf(initial?.tutorialBody.orEmpty()) }
    var steps by rememberSaveable(formKey, initial?.procedureSteps) { mutableStateOf(initial?.procedureSteps?.joinToString("\n").orEmpty()) }
    var quality by rememberSaveable(formKey, initial?.qualityChecklist) { mutableStateOf(initial?.qualityChecklist?.joinToString("\n").orEmpty()) }
    var safety by rememberSaveable(formKey, initial?.safetyChecklist) { mutableStateOf(initial?.safetyChecklist?.joinToString("\n").orEmpty()) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = if (initial == null) "添加施工工艺" else "编辑施工工艺",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            ConstructionField(title, { title = it }, "工艺名称")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ConstructionField(trade, { trade = it }, "专业", Modifier.weight(1f))
                ConstructionField(versionName, { versionName = it }, "版本", Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("草稿", "已发布", "已废止").forEach { status ->
                    FilterChip(
                        selected = publishStatus == status,
                        onClick = { publishStatus = status },
                        label = { Text(status) }
                    )
                }
            }
            ConstructionField(
                value = tutorialBody,
                onValueChange = { tutorialBody = it },
                label = "教程说明",
                singleLine = false,
                minLines = 3
            )
            ConstructionField(
                value = steps,
                onValueChange = { steps = it },
                label = "工序步骤（一行一项）",
                singleLine = false,
                minLines = 4
            )
            ConstructionField(
                value = quality,
                onValueChange = { quality = it },
                label = "质量检查（一行一项）",
                singleLine = false,
                minLines = 3
            )
            ConstructionField(
                value = safety,
                onValueChange = { safety = it },
                label = "安全要点（一行一项）",
                singleLine = false,
                minLines = 3
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End
            ) {
                TextButton(onClick = onCancel) { Text("取消") }
                Button(
                    enabled = title.trim().isNotBlank(),
                    onClick = {
                        onSubmit(title, trade, versionName, publishStatus, tutorialBody, steps, quality, safety)
                    }
                ) {
                    Text("保存")
                }
            }
        }
    }
}

@Composable
private fun ConstructionField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    singleLine: Boolean = true,
    minLines: Int = 1
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = singleLine,
        minLines = minLines
    )
}

@Composable
private fun ConstructionMethodEmptyText(text: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(14.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun constructionMethodMatches(
    method: ConstructionMethodSummary,
    keyword: String
): Boolean {
    val normalized = keyword.trim()
    if (normalized.isBlank()) return true
    return listOf(
        method.title,
        method.trade,
        method.versionName,
        method.publishStatus,
        method.tutorialBody
    ).any { value -> value.contains(normalized, ignoreCase = true) } ||
        method.procedureSteps.any { value -> value.contains(normalized, ignoreCase = true) } ||
        method.qualityChecklist.any { value -> value.contains(normalized, ignoreCase = true) } ||
        method.safetyChecklist.any { value -> value.contains(normalized, ignoreCase = true) }
}
