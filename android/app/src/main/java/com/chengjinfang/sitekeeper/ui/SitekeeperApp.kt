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

internal enum class RootModule(val title: String) {
    Dashboard("首页"),
    Projects("项目"),
    Calculators("计算"),
    Materials("材料库"),
    Methods("工艺库"),
    Checklist("清单"),
    Notes("随手记"),
    Profile("我的")
}
internal enum class ProjectListFilter(val title: String) {
    Active("进行中"),
    All("全部"),
    Archived("已归档")
}

internal enum class ProjectSortOption(val title: String) {
    LatestActivity("最近活动"),
    Name("名称"),
    ExpectedEnd("计划完工")
}

internal enum class ChecklistStatusFilter(val title: String) {
    Open("未完成"),
    Overdue("逾期"),
    All("全部"),
    Done("已完成")
}

internal enum class ChecklistPriorityFilter(
    val title: String,
    val priority: String?
) {
    All("全部优先级", null),
    High("高", "高"),
    Normal("普通", "普通"),
    Low("低", "低")
}

internal enum class DocumentArchiveStatus(val title: String) {
    NotLinked("未归档"),
    Checking("检查中"),
    Archived("已归档"),
    Missing("归档缺失")
}

private enum class CalculatorTool(val title: String) {
    Concrete("混凝土"),
    Wall("墙面"),
    Tile("地砖"),
    Current("电流"),
    VoltageDrop("压降"),
    Unit("换算")
}

private const val BACKUP_JSON_ENTRY_NAME = "backup.json"
private const val PROJECT_DOCUMENTS_ARCHIVE_DIR = "project-documents"

@Composable
fun SitekeeperApp(
    projectRepository: ProjectRepository,
    seedInitialData: suspend () -> Unit
) {
    var selectedModule by rememberSaveable { mutableStateOf(RootModule.Dashboard) }
    var selectedProjectId by rememberSaveable { mutableStateOf<String?>(null) }
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
                        onClick = {
                            selectedProjectId = null
                            selectedModule = module
                        },
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
            selectedProjectId = selectedProjectId,
            projects = projects,
            onSelectModule = { selectedModule = it },
            onSelectProject = { selectedProjectId = it },
            padding = padding
        )
    }
}

@Composable
private fun ModuleContent(
    projectRepository: ProjectRepository,
    selectedModule: RootModule,
    selectedProjectId: String?,
    projects: List<ProjectSummary>,
    onSelectModule: (RootModule) -> Unit,
    onSelectProject: (String?) -> Unit,
    padding: PaddingValues
) {
    Surface(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        color = MaterialTheme.colorScheme.background
    ) {
        when (selectedModule) {
            RootModule.Dashboard -> DashboardScreen(
                projects = projects,
                onOpenProjects = {
                    onSelectProject(null)
                    onSelectModule(RootModule.Projects)
                },
                onOpenProject = { projectId ->
                    onSelectProject(projectId)
                    onSelectModule(RootModule.Projects)
                }
            )
            RootModule.Projects -> ProjectsScreen(
                projectRepository = projectRepository,
                projects = projects,
                selectedProjectId = selectedProjectId,
                onSelectProject = onSelectProject
            )
            RootModule.Calculators -> CalculatorScreen()
            RootModule.Materials -> MaterialLibraryScreen(projectRepository = projectRepository)
            RootModule.Methods -> ConstructionMethodLibraryScreen(projectRepository = projectRepository)
            RootModule.Checklist -> ChecklistScreen(
                projectRepository = projectRepository,
                onOpenProject = { projectId ->
                    onSelectProject(projectId)
                    onSelectModule(RootModule.Projects)
                }
            )
            RootModule.Notes -> NotesScreen(
                projectRepository = projectRepository,
                projects = projects,
                onOpenProject = { projectId ->
                    onSelectProject(projectId)
                    onSelectModule(RootModule.Projects)
                }
            )
            RootModule.Profile -> BackupScreen(
                projectRepository = projectRepository,
                onOpenProject = { projectId ->
                    onSelectProject(projectId)
                    onSelectModule(RootModule.Projects)
                }
            )
        }
    }
}

@Composable
private fun CalculatorScreen() {
    var selectedTool by rememberSaveable { mutableStateOf(CalculatorTool.Concrete) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "计算",
                    style = MaterialTheme.typography.headlineMedium
                )
                Text(
                    text = "现场常用算量、电气估算和单位换算。",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        item {
            CalculatorToolPicker(
                selectedTool = selectedTool,
                onSelectTool = { selectedTool = it }
            )
        }
        item {
            when (selectedTool) {
                CalculatorTool.Concrete -> ConcreteCalculatorCard()
                CalculatorTool.Wall -> WallAreaCalculatorCard()
                CalculatorTool.Tile -> TileCalculatorCard()
                CalculatorTool.Current -> CurrentCalculatorCard()
                CalculatorTool.VoltageDrop -> VoltageDropCalculatorCard()
                CalculatorTool.Unit -> UnitConverterCard()
            }
        }

    }
}

@Composable
private fun CalculatorToolPicker(
    selectedTool: CalculatorTool,
    onSelectTool: (CalculatorTool) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        CalculatorTool.entries.chunked(3).forEach { rowTools ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowTools.forEach { tool ->
                    FilterChip(
                        selected = selectedTool == tool,
                        onClick = { onSelectTool(tool) },
                        label = { Text(tool.title) },
                        modifier = Modifier.weight(1f)
                    )
                }
                repeat(3 - rowTools.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun ConcreteCalculatorCard() {
    var length by rememberSaveable { mutableStateOf("10") }
    var width by rememberSaveable { mutableStateOf("8") }
    var thickness by rememberSaveable { mutableStateOf("12") }
    var waste by rememberSaveable { mutableStateOf("5") }
    var grade by rememberSaveable { mutableStateOf(ConcreteGrade.C25) }
    val result = calculateConcrete(
        lengthM = parseCalculatorNumber(length),
        widthM = parseCalculatorNumber(width),
        thicknessCm = parseCalculatorNumber(thickness),
        wastePercent = parseCalculatorNumber(waste),
        grade = grade
    )

    CalculatorInputCard(title = "混凝土算量") {
        CalculatorFieldRow(
            first = {
                FormTextField(value = length, onValueChange = { length = it }, label = "长度 m")
            },
            second = {
                FormTextField(value = width, onValueChange = { width = it }, label = "宽度 m")
            }
        )
        CalculatorFieldRow(
            first = {
                FormTextField(value = thickness, onValueChange = { thickness = it }, label = "厚度 cm")
            },
            second = {
                FormTextField(value = waste, onValueChange = { waste = it }, label = "损耗 %")
            }
        )
        CalculatorPresetRow(
            title = "标号",
            options = ConcreteGrade.entries,
            selected = grade,
            label = ConcreteGrade::title,
            onSelect = { grade = it }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun WallAreaCalculatorCard() {
    var wall1 by rememberSaveable { mutableStateOf("6") }
    var wall2 by rememberSaveable { mutableStateOf("4") }
    var wall3 by rememberSaveable { mutableStateOf("6") }
    var wall4 by rememberSaveable { mutableStateOf("4") }
    var height by rememberSaveable { mutableStateOf("2.8") }
    var doors by rememberSaveable { mutableStateOf("2") }
    var windows by rememberSaveable { mutableStateOf("3") }
    val result = calculateWallArea(
        wallLengthsM = listOf(
            parseCalculatorNumber(wall1),
            parseCalculatorNumber(wall2),
            parseCalculatorNumber(wall3),
            parseCalculatorNumber(wall4)
        ),
        heightM = parseCalculatorNumber(height),
        doorAreaM2 = parseCalculatorNumber(doors),
        windowAreaM2 = parseCalculatorNumber(windows)
    )

    CalculatorInputCard(title = "墙面面积") {
        CalculatorFieldRow(
            first = { FormTextField(value = wall1, onValueChange = { wall1 = it }, label = "墙 1 m") },
            second = { FormTextField(value = wall2, onValueChange = { wall2 = it }, label = "墙 2 m") }
        )
        CalculatorFieldRow(
            first = { FormTextField(value = wall3, onValueChange = { wall3 = it }, label = "墙 3 m") },
            second = { FormTextField(value = wall4, onValueChange = { wall4 = it }, label = "墙 4 m") }
        )
        FormTextField(value = height, onValueChange = { height = it }, label = "层高 m")
        CalculatorFieldRow(
            first = { FormTextField(value = doors, onValueChange = { doors = it }, label = "门面积 m²") },
            second = { FormTextField(value = windows, onValueChange = { windows = it }, label = "窗面积 m²") }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun TileCalculatorCard() {
    var roomLength by rememberSaveable { mutableStateOf("6") }
    var roomWidth by rememberSaveable { mutableStateOf("4") }
    var tileLength by rememberSaveable { mutableStateOf("600") }
    var tileWidth by rememberSaveable { mutableStateOf("600") }
    var waste by rememberSaveable { mutableStateOf("8") }
    var boxPieces by rememberSaveable { mutableStateOf("4") }
    val result = calculateTile(
        roomLengthM = parseCalculatorNumber(roomLength),
        roomWidthM = parseCalculatorNumber(roomWidth),
        tileLengthMm = parseCalculatorNumber(tileLength),
        tileWidthMm = parseCalculatorNumber(tileWidth),
        wastePercent = parseCalculatorNumber(waste),
        piecesPerBox = parseCalculatorNumber(boxPieces)
    )

    CalculatorInputCard(title = "地砖排料") {
        CalculatorFieldRow(
            first = { FormTextField(value = roomLength, onValueChange = { roomLength = it }, label = "房间长 m") },
            second = { FormTextField(value = roomWidth, onValueChange = { roomWidth = it }, label = "房间宽 m") }
        )
        CalculatorFieldRow(
            first = { FormTextField(value = tileLength, onValueChange = { tileLength = it }, label = "砖长 mm") },
            second = { FormTextField(value = tileWidth, onValueChange = { tileWidth = it }, label = "砖宽 mm") }
        )
        CalculatorFieldRow(
            first = { FormTextField(value = waste, onValueChange = { waste = it }, label = "损耗 %") },
            second = { FormTextField(value = boxPieces, onValueChange = { boxPieces = it }, label = "每箱片数") }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun CurrentCalculatorCard() {
    var power by rememberSaveable { mutableStateOf("10") }
    var voltage by rememberSaveable { mutableStateOf("220") }
    var powerFactor by rememberSaveable { mutableStateOf("0.85") }
    var isThreePhase by rememberSaveable { mutableStateOf(false) }
    val result = calculateCurrent(
        powerKw = parseCalculatorNumber(power),
        voltage = parseCalculatorNumber(voltage),
        powerFactor = parseCalculatorNumber(powerFactor),
        isThreePhase = isThreePhase
    )

    CalculatorInputCard(title = "电流计算") {
        CalculatorFieldRow(
            first = { FormTextField(value = power, onValueChange = { power = it }, label = "功率 kW") },
            second = { FormTextField(value = voltage, onValueChange = { voltage = it }, label = "电压 V") }
        )
        FormTextField(value = powerFactor, onValueChange = { powerFactor = it }, label = "功率因数")
        CalculatorBinaryRow(
            title = "供电",
            firstLabel = "单相",
            secondLabel = "三相",
            selectedSecond = isThreePhase,
            onSelect = { selected ->
                isThreePhase = selected
                voltage = if (selected) "380" else "220"
            }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun VoltageDropCalculatorCard() {
    var current by rememberSaveable { mutableStateOf("20") }
    var length by rememberSaveable { mutableStateOf("100") }
    var section by rememberSaveable { mutableStateOf("6") }
    var voltage by rememberSaveable { mutableStateOf("220") }
    var isLoopLength by rememberSaveable { mutableStateOf(false) }
    var material by rememberSaveable { mutableStateOf(WireMaterial.Copper) }
    val result = calculateVoltageDrop(
        currentA = parseCalculatorNumber(current),
        lengthM = parseCalculatorNumber(length),
        sectionMm2 = parseCalculatorNumber(section),
        voltage = parseCalculatorNumber(voltage),
        isLoopLength = isLoopLength,
        material = material
    )

    CalculatorInputCard(title = "电缆压降") {
        CalculatorFieldRow(
            first = { FormTextField(value = current, onValueChange = { current = it }, label = "电流 A") },
            second = { FormTextField(value = length, onValueChange = { length = it }, label = "长度 m") }
        )
        CalculatorFieldRow(
            first = { FormTextField(value = section, onValueChange = { section = it }, label = "截面 mm²") },
            second = { FormTextField(value = voltage, onValueChange = { voltage = it }, label = "电压 V") }
        )
        CalculatorPresetRow(
            title = "材质",
            options = WireMaterial.entries,
            selected = material,
            label = WireMaterial::title,
            onSelect = { material = it }
        )
        CalculatorBinaryRow(
            title = "长度口径",
            firstLabel = "单程",
            secondLabel = "回路",
            selectedSecond = isLoopLength,
            onSelect = { isLoopLength = it }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun UnitConverterCard() {
    var category by rememberSaveable { mutableStateOf(UnitCategory.Length) }
    var value by rememberSaveable { mutableStateOf("1") }
    var fromUnitName by rememberSaveable { mutableStateOf("米") }
    var toUnitName by rememberSaveable { mutableStateOf("英尺") }
    val units = category.units
    val fromUnit = units.firstOrNull { it.title == fromUnitName } ?: units.first()
    val toUnit = units.firstOrNull { it.title == toUnitName } ?: units.getOrElse(1) { units.first() }
    val result = calculateUnitConversion(
        value = parseCalculatorNumber(value),
        from = fromUnit,
        to = toUnit
    )

    CalculatorInputCard(title = "单位换算") {
        CalculatorPresetRow(
            title = "类型",
            options = UnitCategory.entries,
            selected = category,
            label = UnitCategory::title,
            onSelect = { selected ->
                category = selected
                fromUnitName = selected.units.first().title
                toUnitName = selected.units.getOrElse(1) { selected.units.first() }.title
            }
        )
        FormTextField(value = value, onValueChange = { value = it }, label = "输入值")
        CalculatorPresetRow(
            title = "从",
            options = units,
            selected = fromUnit,
            label = UnitDefinition::title,
            onSelect = { fromUnitName = it.title }
        )
        CalculatorPresetRow(
            title = "到",
            options = units,
            selected = toUnit,
            label = UnitDefinition::title,
            onSelect = { toUnitName = it.title }
        )
        CalculatorResultPanel(result = result)
    }
}

@Composable
private fun CalculatorInputCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
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
            content()
        }
    }
}

@Composable
private fun CalculatorFieldRow(
    first: @Composable () -> Unit,
    second: @Composable () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Column(modifier = Modifier.weight(1f)) {
            first()
        }
        Column(modifier = Modifier.weight(1f)) {
            second()
        }
    }
}

@Composable
private fun <T> CalculatorPresetRow(
    title: String,
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        options.chunked(3).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                rowItems.forEach { item ->
                    FilterChip(
                        selected = selected == item,
                        onClick = { onSelect(item) },
                        label = { Text(label(item)) },
                        modifier = Modifier.weight(1f)
                    )
                }
                repeat(3 - rowItems.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun CalculatorBinaryRow(
    title: String,
    firstLabel: String,
    secondLabel: String,
    selectedSecond: Boolean,
    onSelect: (Boolean) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterChip(
                selected = !selectedSecond,
                onClick = { onSelect(false) },
                label = { Text(firstLabel) },
                modifier = Modifier.weight(1f)
            )
            FilterChip(
                selected = selectedSecond,
                onClick = { onSelect(true) },
                label = { Text(secondLabel) },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun CalculatorResultPanel(result: CalculatorResult?) {
    if (result == null) {
        CompactEmptyText("输入有效参数后显示结果")
        return
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
        ),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = result.headline,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = result.formula,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            result.metrics.forEach { metric ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = metric.label,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = metric.value,
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (metric.warning) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}
