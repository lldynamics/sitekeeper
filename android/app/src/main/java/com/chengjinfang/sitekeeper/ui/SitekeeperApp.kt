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
import com.chengjinfang.sitekeeper.backup.cleanupOrphanProjectDocumentArchives
import com.chengjinfang.sitekeeper.backup.defaultBackupPackageFileName
import com.chengjinfang.sitekeeper.backup.deleteDrawingArchive
import com.chengjinfang.sitekeeper.backup.deletePhotoArchive
import com.chengjinfang.sitekeeper.backup.deleteProjectDocumentArchive
import com.chengjinfang.sitekeeper.backup.deleteQuickNoteAttachmentArchive
import com.chengjinfang.sitekeeper.backup.documentArchiveUsageText
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

private enum class RootModule(val title: String) {
    Dashboard("首页"),
    Projects("项目"),
    Calculators("计算"),
    Materials("材料库"),
    Methods("工艺库"),
    Checklist("清单"),
    Notes("随手记"),
    Profile("我的")
}

private enum class ProjectListFilter(val title: String) {
    Active("进行中"),
    All("全部"),
    Archived("已归档")
}

private enum class ProjectSortOption(val title: String) {
    LatestActivity("最近活动"),
    Name("名称"),
    ExpectedEnd("计划完工")
}

private enum class ChecklistStatusFilter(val title: String) {
    Open("未完成"),
    Overdue("逾期"),
    All("全部"),
    Done("已完成")
}

private enum class ChecklistPriorityFilter(
    val title: String,
    val priority: String?
) {
    All("全部优先级", null),
    High("高", "高"),
    Normal("普通", "普通"),
    Low("低", "低")
}

private enum class DocumentArchiveStatus(val title: String) {
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
            RootModule.Profile -> BackupScreen(projectRepository = projectRepository)
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

@Composable
private fun ProjectsScreen(
    projectRepository: ProjectRepository,
    projects: List<ProjectSummary>,
    selectedProjectId: String?,
    onSelectProject: (String?) -> Unit
) {
    var showProjectForm by rememberSaveable { mutableStateOf(false) }
    var selectedFilter by rememberSaveable { mutableStateOf(ProjectListFilter.Active) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var sortOption by rememberSaveable { mutableStateOf(ProjectSortOption.LatestActivity) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val selectedDetail = rememberProjectDetail(
        projectRepository = projectRepository,
        selectedProjectId = selectedProjectId
    )
    val visibleProjects = remember(projects, selectedFilter, searchQuery, sortOption) {
        projects
            .filterBy(selectedFilter)
            .searchBy(searchQuery)
            .sortBy(sortOption)
    }

    if (selectedProjectId != null) {
        if (selectedDetail == null) {
            ProjectDetailLoading(onBack = { onSelectProject(null) })
        } else {
            ProjectDetailScreen(
                detail = selectedDetail,
                onBack = { onSelectProject(null) },
                onUpdateProject = { name, location, managerName, contractAmount, expectedEndDate ->
                    scope.launch {
                        projectRepository.updateProject(
                            projectId = selectedDetail.project.id,
                            name = name,
                            location = location,
                            managerName = managerName,
                            contractAmount = contractAmount,
                            expectedEndDate = expectedEndDate
                        )
                    }
                },
                onSetProjectArchived = { archived ->
                    scope.launch {
                        projectRepository.setProjectArchived(
                            projectId = selectedDetail.project.id,
                            archived = archived
                        )
                    }
                },
                onAddDailyLog = { date, content, workers, weather, linkedMethodIds ->
                    scope.launch {
                        projectRepository.addDailyLog(
                            projectId = selectedDetail.project.id,
                            date = date,
                            content = content,
                            workers = workers,
                            weather = weather,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onUpdateDailyLog = { dailyLogId, date, content, workers, weather, linkedMethodIds ->
                    scope.launch {
                        projectRepository.updateDailyLog(
                            dailyLogId = dailyLogId,
                            date = date,
                            content = content,
                            workers = workers,
                            weather = weather,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onDeleteDailyLog = { dailyLogId ->
                    scope.launch {
                        projectRepository.deleteDailyLog(dailyLogId)
                    }
                },
                onAttachDailyLogPhoto = { dailyLogId, fileName ->
                    scope.launch {
                        projectRepository.attachDailyLogPhoto(dailyLogId, fileName)
                    }
                },
                onDeleteDailyLogPhoto = { dailyLogId, fileName ->
                    scope.launch {
                        projectRepository.deleteDailyLogPhoto(dailyLogId, fileName)
                    }
                },
                onAddProgressTask = { title, startDate, dueDate, completion, note ->
                    scope.launch {
                        projectRepository.addProgressTask(
                            projectId = selectedDetail.project.id,
                            title = title,
                            startDate = startDate,
                            dueDate = dueDate,
                            completion = completion,
                            note = note
                        )
                    }
                },
                onUpdateProgressTask = { taskId, title, startDate, dueDate, completion, note ->
                    scope.launch {
                        projectRepository.updateProgressTask(
                            taskId = taskId,
                            title = title,
                            startDate = startDate,
                            dueDate = dueDate,
                            completion = completion,
                            note = note
                        )
                    }
                },
                onSetProgressTaskCompletion = { taskId, completion ->
                    scope.launch {
                        projectRepository.setProgressTaskCompletion(
                            taskId = taskId,
                            completion = completion
                        )
                    }
                },
                onDeleteProgressTask = { taskId ->
                    scope.launch {
                        projectRepository.deleteProgressTask(taskId)
                    }
                },
                onAddSiteTodo = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                    scope.launch {
                        projectRepository.addSiteTodo(
                            projectId = selectedDetail.project.id,
                            title = title,
                            owner = owner,
                            dueDate = dueDate,
                            priority = priority,
                            issueType = issueType,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onUpdateSiteTodo = { todoId, title, owner, dueDate, priority, issueType, linkedMethodIds ->
                    scope.launch {
                        projectRepository.updateSiteTodo(
                            todoId = todoId,
                            title = title,
                            owner = owner,
                            dueDate = dueDate,
                            priority = priority,
                            issueType = issueType,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onDeleteSiteTodo = { todoId ->
                    scope.launch {
                        projectRepository.deleteSiteTodo(todoId)
                    }
                },
                onAttachSiteTodoPhoto = { todoId, target, fileName ->
                    scope.launch {
                        projectRepository.attachSiteTodoPhoto(todoId, target, fileName)
                    }
                },
                onDeleteSiteTodoPhoto = { todoId, target ->
                    scope.launch {
                        projectRepository.deleteSiteTodoPhoto(todoId, target)
                    }
                },
                onAddFinancialRecord = { date, direction, category, amount, counterparty, status, dueDate, note ->
                    scope.launch {
                        projectRepository.addFinancialRecord(
                            projectId = selectedDetail.project.id,
                            date = date,
                            direction = direction,
                            category = category,
                            amount = amount,
                            counterparty = counterparty,
                            status = status,
                            dueDate = dueDate,
                            note = note
                        )
                    }
                },
                onUpdateFinancialRecord = { recordId, date, direction, category, amount, counterparty, status, dueDate, note ->
                    scope.launch {
                        projectRepository.updateFinancialRecord(
                            recordId = recordId,
                            date = date,
                            direction = direction,
                            category = category,
                            amount = amount,
                            counterparty = counterparty,
                            status = status,
                            dueDate = dueDate,
                            note = note
                        )
                    }
                },
                onDeleteFinancialRecord = { recordId ->
                    scope.launch {
                        projectRepository.deleteFinancialRecord(recordId)
                    }
                },
                onAddMaterialItem = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                    scope.launch {
                        projectRepository.addMaterialItem(
                            projectId = selectedDetail.project.id,
                            name = name,
                            specification = specification,
                            quantity = quantity,
                            unit = unit,
                            unitPrice = unitPrice,
                            supplier = supplier,
                            purchaseStatus = purchaseStatus,
                            arrivalDate = arrivalDate
                        )
                    }
                },
                onUpdateMaterialItem = { materialId, name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                    scope.launch {
                        projectRepository.updateMaterialItem(
                            materialId = materialId,
                            name = name,
                            specification = specification,
                            quantity = quantity,
                            unit = unit,
                            unitPrice = unitPrice,
                            supplier = supplier,
                            purchaseStatus = purchaseStatus,
                            arrivalDate = arrivalDate
                        )
                    }
                },
                onDeleteMaterialItem = { materialId ->
                    scope.launch {
                        projectRepository.deleteMaterialItem(materialId)
                    }
                },
                onAddProjectContact = { name, role, company, phone, note ->
                    scope.launch {
                        projectRepository.addProjectContact(
                            projectId = selectedDetail.project.id,
                            name = name,
                            role = role,
                            company = company,
                            phone = phone,
                            note = note
                        )
                    }
                },
                onUpdateProjectContact = { contactId, name, role, company, phone, note ->
                    scope.launch {
                        projectRepository.updateProjectContact(
                            contactId = contactId,
                            name = name,
                            role = role,
                            company = company,
                            phone = phone,
                            note = note
                        )
                    }
                },
                onDeleteProjectContact = { contactId ->
                    scope.launch {
                        projectRepository.deleteProjectContact(contactId)
                    }
                },
                onAddProjectDocument = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                    scope.launch {
                        projectRepository.addProjectDocument(
                            projectId = selectedDetail.project.id,
                            title = title,
                            category = category,
                            fileName = fileName,
                            fileType = fileType,
                            pageCount = pageCount,
                            amount = amount,
                            note = note,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onUpdateProjectDocument = { documentId, title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                    scope.launch {
                        projectRepository.updateProjectDocument(
                            documentId = documentId,
                            title = title,
                            category = category,
                            fileName = fileName,
                            fileType = fileType,
                            pageCount = pageCount,
                            amount = amount,
                            note = note,
                            linkedConstructionMethodIds = linkedMethodIds
                        )
                    }
                },
                onDeleteProjectDocument = { documentId ->
                    scope.launch {
                        projectRepository.deleteProjectDocument(documentId)
                        deleteProjectDocumentArchive(
                            context = context,
                            documentId = documentId
                        )
                    }
                },
                onAttachProjectDocumentFile = { documentId, fileName, fileType, localUri ->
                    scope.launch {
                        projectRepository.attachProjectDocumentFile(
                            documentId = documentId,
                            fileName = fileName,
                            fileType = fileType,
                            localUri = localUri
                        )
                    }
                },
                onAddProjectDrawing = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                    scope.launch {
                        projectRepository.addProjectDrawing(
                            projectId = selectedDetail.project.id,
                            name = name,
                            fileName = fileName,
                            fileType = fileType,
                            version = version,
                            relatedLogDate = relatedLogDate,
                            issueStatus = issueStatus,
                            issueNote = issueNote,
                            note = note
                        )
                    }
                },
                onUpdateProjectDrawing = { drawingId, name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                    scope.launch {
                        projectRepository.updateProjectDrawing(
                            drawingId = drawingId,
                            name = name,
                            fileName = fileName,
                            fileType = fileType,
                            version = version,
                            relatedLogDate = relatedLogDate,
                            issueStatus = issueStatus,
                            issueNote = issueNote,
                            note = note
                        )
                    }
                },
                onDeleteProjectDrawing = { drawingId ->
                    scope.launch {
                        projectRepository.deleteProjectDrawing(drawingId)
                    }
                },
                onAttachProjectDrawingFile = { drawingId, fileName, fileType, localUri ->
                    scope.launch {
                        projectRepository.attachProjectDrawingFile(
                            drawingId = drawingId,
                            fileName = fileName,
                            fileType = fileType,
                            localUri = localUri
                        )
                    }
                },
                onAddQuoteItem = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                    scope.launch {
                        projectRepository.addQuoteItem(
                            projectId = selectedDetail.project.id,
                            name = name,
                            unitPrice = unitPrice,
                            quantity = quantity,
                            unit = unit,
                            versionName = versionName,
                            status = status,
                            customerConfirmedDate = customerConfirmedDate,
                            contractAmount = contractAmount,
                            notes = notes
                        )
                    }
                },
                onUpdateQuoteItem = { quoteItemId, name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                    scope.launch {
                        projectRepository.updateQuoteItem(
                            quoteItemId = quoteItemId,
                            name = name,
                            unitPrice = unitPrice,
                            quantity = quantity,
                            unit = unit,
                            versionName = versionName,
                            status = status,
                            customerConfirmedDate = customerConfirmedDate,
                            contractAmount = contractAmount,
                            notes = notes
                        )
                    }
                },
                onDeleteQuoteItem = { quoteItemId ->
                    scope.launch {
                        projectRepository.deleteQuoteItem(quoteItemId)
                    }
                },
                onAddLaborRecord = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                    scope.launch {
                        projectRepository.addLaborRecord(
                            projectId = selectedDetail.project.id,
                            date = date,
                            workers = workers,
                            hours = hours,
                            unitRate = unitRate,
                            workType = workType,
                            teamName = teamName,
                            isSettled = isSettled,
                            note = note
                        )
                    }
                },
                onUpdateLaborRecord = { recordId, date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                    scope.launch {
                        projectRepository.updateLaborRecord(
                            recordId = recordId,
                            date = date,
                            workers = workers,
                            hours = hours,
                            unitRate = unitRate,
                            workType = workType,
                            teamName = teamName,
                            isSettled = isSettled,
                            note = note
                        )
                    }
                },
                onSetLaborRecordSettled = { recordId, isSettled ->
                    scope.launch {
                        projectRepository.setLaborRecordSettled(
                            recordId = recordId,
                            isSettled = isSettled
                        )
                    }
                },
                onDeleteLaborRecord = { recordId ->
                    scope.launch {
                        projectRepository.deleteLaborRecord(recordId)
                    }
                },
                onAddWarehouseMovement = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                    scope.launch {
                        projectRepository.addProjectWarehouseMovement(
                            projectId = selectedDetail.project.id,
                            date = date,
                            movementType = movementType,
                            materialName = materialName,
                            specification = specification,
                            unit = unit,
                            quantity = quantity,
                            counterparty = counterparty,
                            handler = handler,
                            note = note
                        )
                    }
                },
                onUpdateWarehouseMovement = { movementId, date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                    scope.launch {
                        projectRepository.updateProjectWarehouseMovement(
                            movementId = movementId,
                            date = date,
                            movementType = movementType,
                            materialName = materialName,
                            specification = specification,
                            unit = unit,
                            quantity = quantity,
                            counterparty = counterparty,
                            handler = handler,
                            note = note
                        )
                    }
                },
                onDeleteWarehouseMovement = { movementId ->
                    scope.launch {
                        projectRepository.deleteProjectWarehouseMovement(movementId)
                    }
                },
                onSetSiteTodoDone = { todoId, isDone ->
                    scope.launch {
                        projectRepository.setSiteTodoDone(
                            todoId = todoId,
                            isDone = isDone
                        )
                    }
                },
                onUpdateFinancialRecordStatus = { recordId, status ->
                    scope.launch {
                        projectRepository.updateFinancialRecordStatus(
                            recordId = recordId,
                            status = status
                        )
                    }
                },
                onUpdateMaterialPurchaseStatus = { materialId, purchaseStatus ->
                    scope.launch {
                        projectRepository.updateMaterialPurchaseStatus(
                            materialId = materialId,
                            purchaseStatus = purchaseStatus
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
                ProjectFilterRow(
                    selectedFilter = selectedFilter,
                    onSelectFilter = { selectedFilter = it }
                )
                ProjectSearchAndSortControls(
                    searchQuery = searchQuery,
                    onSearchQueryChange = { searchQuery = it },
                    sortOption = sortOption,
                    onSortOptionChange = { sortOption = it }
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
                            onSelectProject(projectId)
                        }
                    }
                )
            }
        }

        if (visibleProjects.isEmpty()) {
            item {
                EmptyProjectState(
                    filter = selectedFilter,
                    searchQuery = searchQuery
                )
            }
        } else {
            items(
                items = visibleProjects,
                key = ProjectSummary::id
            ) { project ->
                ProjectRow(
                    project = project,
                    onClick = { onSelectProject(project.id) }
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
private fun DashboardScreen(
    projects: List<ProjectSummary>,
    onOpenProjects: () -> Unit,
    onOpenProject: (String) -> Unit
) {
    val activeProjects = remember(projects) {
        projects.filterBy(ProjectListFilter.Active)
    }
    val riskProjects = remember(activeProjects) {
        activeProjects
            .filter { project -> project.totalRiskCount() > 0 }
            .sortByRiskPriority()
            .take(6)
    }
    val recentProjects = remember(activeProjects) {
        activeProjects
            .sortBy(ProjectSortOption.LatestActivity)
            .take(3)
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
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        text = "今日工作台",
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = todayText(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = onOpenProjects) {
                    Text("项目")
                }
            }
        }

        item {
            DashboardSummaryCard(projects = activeProjects)
        }

        item {
            DashboardSectionHeader(
                title = "风险项目",
                actionLabel = "全部项目",
                onAction = onOpenProjects
            )
        }

        if (riskProjects.isEmpty()) {
            item {
                DashboardEmptyCard(
                    title = "暂无风险项目",
                    message = "进行中项目 ${activeProjects.size} 个"
                )
            }
        } else {
            items(
                items = riskProjects,
                key = { project -> "risk-${project.id}" }
            ) { project ->
                DashboardRiskProjectRow(
                    project = project,
                    onClick = { onOpenProject(project.id) }
                )
            }
        }

        item {
            DashboardSectionHeader(
                title = "最近项目",
                actionLabel = "查看列表",
                onAction = onOpenProjects
            )
        }

        if (recentProjects.isEmpty()) {
            item {
                DashboardEmptyCard(
                    title = "暂无进行中项目",
                    message = "可从项目页新建或导入备份"
                )
            }
        } else {
            items(
                items = recentProjects,
                key = { project -> "recent-${project.id}" }
            ) { project ->
                DashboardRecentProjectRow(
                    project = project,
                    onClick = { onOpenProject(project.id) }
                )
            }
        }
    }
}

@Composable
private fun DashboardSummaryCard(projects: List<ProjectSummary>) {
    val overdueTodoCount = projects.sumOf { project -> project.overdueTodoCount }
    val dueIncomeCount = projects.sumOf { project -> project.dueIncomeCount }
    val unarrivedMaterialCount = projects.sumOf { project -> project.unarrivedMaterialCount }
    val openTodoCount = projects.sumOf { project -> project.openTodoCount }

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
                text = "风险汇总",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "进行中",
                    value = "${projects.size} 个",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "待办",
                    value = "$openTodoCount 项",
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProjectMetric(
                    label = "逾期",
                    value = "$overdueTodoCount 项",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "收款",
                    value = "$dueIncomeCount 笔",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "材料",
                    value = "$unarrivedMaterialCount 项",
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun DashboardSectionHeader(
    title: String,
    actionLabel: String,
    onAction: () -> Unit
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
        TextButton(onClick = onAction) {
            Text(actionLabel)
        }
    }
}

@Composable
private fun DashboardRiskProjectRow(
    project: ProjectSummary,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            DashboardProjectTitle(project = project)
            Text(
                text = projectRiskText(project),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.error,
                fontWeight = FontWeight.SemiBold
            )
            DashboardProjectSubline(project = project)
        }
    }
}

@Composable
private fun DashboardRecentProjectRow(
    project: ProjectSummary,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(8.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            DashboardProjectTitle(project = project)
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
                ProjectMetric(
                    label = "最近",
                    value = project.latestActivityDate.ifBlank { "-" },
                    modifier = Modifier.weight(1f)
                )
            }
            DashboardProjectSubline(project = project)
        }
    }
}

@Composable
private fun DashboardProjectTitle(project: ProjectSummary) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = project.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = listOf(project.location, project.managerName)
                    .filter(String::isNotBlank)
                    .joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
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
}

@Composable
private fun DashboardProjectSubline(project: ProjectSummary) {
    Text(
        text = dashboardProjectSublineText(project),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun DashboardEmptyCard(
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

@Composable
private fun ProjectDetailLoading(onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = "正在打开项目",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold
        )
        TextButton(onClick = onBack) {
            Text("返回")
        }
    }
}

@Composable
private fun ChecklistScreen(
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

@Composable
private fun NotesScreen(
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
private fun QuickNoteFormCard(
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
private fun QuickNoteProjectPicker(
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

@Composable
private fun ProjectFilterRow(
    selectedFilter: ProjectListFilter,
    onSelectFilter: (ProjectListFilter) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ProjectListFilter.entries.forEach { filter ->
            FilterChip(
                selected = selectedFilter == filter,
                onClick = { onSelectFilter(filter) },
                label = { Text(filter.title) }
            )
        }
    }
}

@Composable
private fun ProjectSearchAndSortControls(
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    sortOption: ProjectSortOption,
    onSortOptionChange: (ProjectSortOption) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchQueryChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("搜索项目、地点、负责人") },
            singleLine = true
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ProjectSortOption.entries.forEach { option ->
                FilterChip(
                    selected = sortOption == option,
                    onClick = { onSortOptionChange(option) },
                    label = { Text(option.title) }
                )
            }
        }
    }
}

@Composable
private fun BackupScreen(projectRepository: ProjectRepository) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var statusText by rememberSaveable { mutableStateOf("本机数据") }
    var pendingExportJson by remember { mutableStateOf<String?>(null) }
    var pendingImport by remember { mutableStateOf<PendingBackupImport?>(null) }
    var archiveUsage by remember { mutableStateOf<DocumentArchiveUsage?>(null) }

    fun refreshArchiveUsage() {
        scope.launch {
            runCatching {
                projectDocumentArchiveUsage(
                    context = context,
                    rawJson = projectRepository.exportBackupJson()
                )
            }.onSuccess { usage ->
                archiveUsage = usage
            }
        }
    }

    LaunchedEffect(projectRepository) {
        runCatching {
            projectDocumentArchiveUsage(
                context = context,
                rawJson = projectRepository.exportBackupJson()
            )
        }.onSuccess { usage ->
            archiveUsage = usage
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
                refreshArchiveUsage()
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
                                            refreshArchiveUsage()
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

            ProjectRiskLine(project = project)

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
                ProjectMetric(
                    label = "最近",
                    value = project.latestActivityDate.ifBlank { "-" },
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
private fun ProjectRiskLine(project: ProjectSummary) {
    val riskText = projectRiskText(project)
    if (riskText.isBlank()) {
        return
    }

    Text(
        text = riskText,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.error,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
private fun ProjectFormCard(
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
private fun DailyLogFormCard(
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
private fun ProgressTaskFormCard(
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
private fun ProjectContactFormCard(
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
private fun ProjectDocumentFormCard(
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
private fun ProjectDrawingFormCard(
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
private fun SiteTodoFormCard(
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
private fun QuoteItemFormCard(
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
private fun LaborRecordFormCard(
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
private fun WarehouseMovementFormCard(
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
private fun FinancialRecordFormCard(
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
private fun MaterialItemFormCard(
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
private fun FormTextField(
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
private fun ConstructionMethodPicker(
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
private fun LinkedConstructionMethodText(titles: List<String>) {
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
private fun ConfirmDeleteRow(
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

@Composable
private fun ProjectDetailScreen(
    detail: ProjectDetail,
    onBack: () -> Unit,
    onUpdateProject: (
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ) -> Unit,
    onSetProjectArchived: (archived: Boolean) -> Unit,
    onAddDailyLog: (date: String, content: String, workers: String, weather: String, linkedMethodIds: List<String>) -> Unit,
    onUpdateDailyLog: (dailyLogId: String, date: String, content: String, workers: String, weather: String, linkedMethodIds: List<String>) -> Unit,
    onDeleteDailyLog: (dailyLogId: String) -> Unit,
    onAttachDailyLogPhoto: (dailyLogId: String, fileName: String) -> Unit,
    onDeleteDailyLogPhoto: (dailyLogId: String, fileName: String) -> Unit,
    onAddProgressTask: (title: String, startDate: String, dueDate: String, completion: String, note: String) -> Unit,
    onUpdateProgressTask: (taskId: String, title: String, startDate: String, dueDate: String, completion: String, note: String) -> Unit,
    onSetProgressTaskCompletion: (taskId: String, completion: Double) -> Unit,
    onDeleteProgressTask: (taskId: String) -> Unit,
    onAddSiteTodo: (title: String, owner: String, dueDate: String, priority: String, issueType: String, linkedMethodIds: List<String>) -> Unit,
    onUpdateSiteTodo: (todoId: String, title: String, owner: String, dueDate: String, priority: String, issueType: String, linkedMethodIds: List<String>) -> Unit,
    onDeleteSiteTodo: (todoId: String) -> Unit,
    onAttachSiteTodoPhoto: (todoId: String, target: SiteTodoPhotoTarget, fileName: String) -> Unit,
    onDeleteSiteTodoPhoto: (todoId: String, target: SiteTodoPhotoTarget) -> Unit,
    onAddFinancialRecord: (
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) -> Unit,
    onUpdateFinancialRecord: (
        recordId: String,
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) -> Unit,
    onDeleteFinancialRecord: (recordId: String) -> Unit,
    onAddMaterialItem: (
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) -> Unit,
    onUpdateMaterialItem: (
        materialId: String,
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) -> Unit,
    onDeleteMaterialItem: (materialId: String) -> Unit,
    onAddProjectContact: (
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) -> Unit,
    onUpdateProjectContact: (
        contactId: String,
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) -> Unit,
    onDeleteProjectContact: (contactId: String) -> Unit,
    onAddProjectDocument: (
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedMethodIds: List<String>
    ) -> Unit,
    onUpdateProjectDocument: (
        documentId: String,
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedMethodIds: List<String>
    ) -> Unit,
    onDeleteProjectDocument: (documentId: String) -> Unit,
    onAttachProjectDocumentFile: (
        documentId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit,
    onAddProjectDrawing: (
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) -> Unit,
    onUpdateProjectDrawing: (
        drawingId: String,
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) -> Unit,
    onDeleteProjectDrawing: (drawingId: String) -> Unit,
    onAttachProjectDrawingFile: (
        drawingId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit,
    onAddQuoteItem: (
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) -> Unit,
    onUpdateQuoteItem: (
        quoteItemId: String,
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) -> Unit,
    onDeleteQuoteItem: (quoteItemId: String) -> Unit,
    onAddLaborRecord: (
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) -> Unit,
    onUpdateLaborRecord: (
        recordId: String,
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) -> Unit,
    onSetLaborRecordSettled: (recordId: String, isSettled: Boolean) -> Unit,
    onDeleteLaborRecord: (recordId: String) -> Unit,
    onAddWarehouseMovement: (
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) -> Unit,
    onUpdateWarehouseMovement: (
        movementId: String,
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) -> Unit,
    onDeleteWarehouseMovement: (movementId: String) -> Unit,
    onSetSiteTodoDone: (todoId: String, isDone: Boolean) -> Unit,
    onUpdateFinancialRecordStatus: (recordId: String, status: String) -> Unit,
    onUpdateMaterialPurchaseStatus: (materialId: String, purchaseStatus: String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
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
    var documentPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var drawingPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var photoPickerTargetKind by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var photoPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var deliveryExportStatus by rememberSaveable(detail.project.id) { mutableStateOf("") }
    val deliveryExportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip")
    ) { uri ->
        if (uri == null) {
            deliveryExportStatus = "已取消导出"
            return@rememberLauncherForActivityResult
        }

        scope.launch {
            deliveryExportStatus = "正在导出交付包"
            runCatching {
                writeProjectDeliveryPackageToUri(
                    context = context,
                    uri = uri,
                    detail = detail
                )
            }.onSuccess { result ->
                deliveryExportStatus = "已导出交付包，含 ${result.documentFileCount} 份资料、${result.drawingFileCount} 份图纸、${result.photoFileCount} 张照片，缺失 ${result.missingFileCount} 个文件"
            }.onFailure { error ->
                deliveryExportStatus = "导出失败：${error.message ?: "无法写入文件"}"
            }
        }
    }
    val documentFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val documentId = documentPickerTargetId
        if (uri != null && documentId != null) {
            runCatching {
                archiveDocumentFile(
                    context = context,
                    sourceUri = uri,
                    documentId = documentId
                )
            }.onSuccess { fileInfo ->
                onAttachProjectDocumentFile(
                    documentId,
                    fileInfo.name,
                    fileInfo.type,
                    fileInfo.localUri
                )
            }
        }
        documentPickerTargetId = null
    }
    val drawingFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val drawingId = drawingPickerTargetId
        if (uri != null && drawingId != null) {
            runCatching {
                archiveDrawingFile(
                    context = context,
                    sourceUri = uri
                )
            }.onSuccess { fileInfo ->
                onAttachProjectDrawingFile(
                    drawingId,
                    fileInfo.name,
                    fileInfo.type,
                    fileInfo.localUri
                )
            }
        }
        drawingPickerTargetId = null
    }
    val photoFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val targetKind = photoPickerTargetKind
        val targetId = photoPickerTargetId
        if (uri != null && targetKind != null && targetId != null) {
            runCatching {
                archivePhotoFile(
                    context = context,
                    sourceUri = uri
                )
            }.onSuccess { fileInfo ->
                when (targetKind) {
                    "daily" -> onAttachDailyLogPhoto(targetId, fileInfo.name)
                    "todo-before" -> onAttachSiteTodoPhoto(targetId, SiteTodoPhotoTarget.Before, fileInfo.name)
                    "todo-after" -> onAttachSiteTodoPhoto(targetId, SiteTodoPhotoTarget.After, fileInfo.name)
                }
            }
        }
        photoPickerTargetKind = null
        photoPickerTargetId = null
    }

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
                statusText = deliveryExportStatus,
                onExport = {
                    deliveryExportLauncher.launch(defaultProjectDeliveryPackageFileName(detail.project.name))
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

        item {
            SectionTitle(
                title = "项目资料",
                count = detail.documents.size,
                actionLabel = if (showDocumentForm) "收起" else "添加资料",
                onAction = { showDocumentForm = !showDocumentForm }
            )
        }

        if (showDocumentForm) {
            item {
                ProjectDocumentFormCard(
                    availableMethods = detail.constructionMethods,
                    onCancel = { showDocumentForm = false },
                    onSave = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                        onAddProjectDocument(title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds)
                        showDocumentForm = false
                    }
                )
            }
        }

        if (detail.documents.isEmpty()) {
            item {
                CompactEmptyText("暂无项目资料")
            }
        } else {
            items(
                items = detail.documents,
                key = ProjectDocumentSummary::id
            ) { document ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ProjectDocumentRow(
                        document = document,
                        linkedMethodTitles = linkedMethodTitles(detail.constructionMethods, document.linkedConstructionMethodIds),
                        onOpenFile = {
                            openLocalDocument(
                                context = context,
                                localUri = document.localUri
                            )
                        },
                        onPickFile = {
                            documentPickerTargetId = document.id
                            documentFilePicker.launch(arrayOf("*/*"))
                        },
                        onEdit = {
                            editingDocumentId = if (editingDocumentId == document.id) {
                                null
                            } else {
                                document.id
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "document-${document.id}"
                        }
                    )
                    if (confirmingDeleteKey == "document-${document.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条项目资料？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteProjectDocument(document.id)
                                confirmingDeleteKey = null
                                editingDocumentId = null
                            }
                        )
                    }
                    if (editingDocumentId == document.id) {
                        ProjectDocumentFormCard(
                            formKey = "edit-document-${document.id}",
                            titleText = "编辑项目资料",
                            availableMethods = detail.constructionMethods,
                            initialTitle = document.title,
                            initialCategory = document.category,
                            initialFileName = document.fileName,
                            initialFileType = document.fileType,
                            initialPageCount = document.pageCount.toString(),
                            initialAmount = document.amount,
                            initialNote = document.note,
                            initialLinkedMethodIds = document.linkedConstructionMethodIds,
                            onCancel = { editingDocumentId = null },
                            onSave = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                                onUpdateProjectDocument(
                                    document.id,
                                    title,
                                    category,
                                    fileName,
                                    fileType,
                                    pageCount,
                                    amount,
                                    note,
                                    linkedMethodIds
                                )
                                editingDocumentId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "项目图纸",
                count = detail.drawings.size,
                actionLabel = if (showDrawingForm) "收起" else "添加图纸",
                onAction = { showDrawingForm = !showDrawingForm }
            )
        }

        if (showDrawingForm) {
            item {
                ProjectDrawingFormCard(
                    onCancel = { showDrawingForm = false },
                    onSave = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                        onAddProjectDrawing(
                            name,
                            fileName,
                            fileType,
                            version,
                            relatedLogDate,
                            issueStatus,
                            issueNote,
                            note
                        )
                        showDrawingForm = false
                    }
                )
            }
        }

        if (detail.drawings.isEmpty()) {
            item {
                CompactEmptyText("暂无项目图纸")
            }
        } else {
            items(
                items = detail.drawings,
                key = ProjectDrawingSummary::id
            ) { drawing ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    ProjectDrawingRow(
                        drawing = drawing,
                        onOpenFile = {
                            openLocalDocument(context, drawing.localUri)
                        },
                        onPickFile = {
                            drawingPickerTargetId = drawing.id
                            drawingFilePicker.launch(
                                arrayOf(
                                    "application/pdf",
                                    "image/*",
                                    "application/dxf",
                                    "application/dwg",
                                    "application/octet-stream",
                                    "*/*"
                                )
                            )
                        },
                        onEdit = {
                            editingDrawingId = if (editingDrawingId == drawing.id) {
                                null
                            } else {
                                drawing.id
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "drawing-${drawing.id}"
                        }
                    )
                    if (confirmingDeleteKey == "drawing-${drawing.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条项目图纸？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                if (drawing.localUri.isNotBlank() && drawing.fileName.isNotBlank()) {
                                    deleteDrawingArchive(context, drawing.fileName)
                                }
                                onDeleteProjectDrawing(drawing.id)
                                confirmingDeleteKey = null
                                editingDrawingId = null
                            }
                        )
                    }
                    if (editingDrawingId == drawing.id) {
                        ProjectDrawingFormCard(
                            formKey = "edit-drawing-${drawing.id}",
                            titleText = "编辑项目图纸",
                            initialName = drawing.name,
                            initialFileName = drawing.fileName,
                            initialFileType = drawing.fileType,
                            initialVersion = drawing.version,
                            initialRelatedLogDate = drawing.relatedLogDate,
                            initialIssueStatus = drawing.issueStatus,
                            initialIssueNote = drawing.issueNote,
                            initialNote = drawing.note,
                            onCancel = { editingDrawingId = null },
                            onSave = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                                onUpdateProjectDrawing(
                                    drawing.id,
                                    name,
                                    fileName,
                                    fileType,
                                    version,
                                    relatedLogDate,
                                    issueStatus,
                                    issueNote,
                                    note
                                )
                                editingDrawingId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            FinanceOverviewCard(records = detail.financialRecords)
        }

        item {
            SectionTitle(
                title = "报价项",
                count = detail.quoteItems.size,
                actionLabel = if (showQuoteForm) "收起" else "添加报价",
                onAction = { showQuoteForm = !showQuoteForm }
            )
        }

        if (showQuoteForm) {
            item {
                QuoteItemFormCard(
                    onCancel = { showQuoteForm = false },
                    onSave = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                        onAddQuoteItem(
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
                        showQuoteForm = false
                    }
                )
            }
        }

        if (detail.quoteItems.isEmpty()) {
            item {
                CompactEmptyText("暂无报价项")
            }
        } else {
            items(
                items = detail.quoteItems,
                key = QuoteItemSummary::id
            ) { quote ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    QuoteItemRow(
                        quote = quote,
                        onEdit = {
                            editingQuoteItemId = if (editingQuoteItemId == quote.id) {
                                null
                            } else {
                                quote.id
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "quote-${quote.id}"
                        }
                    )
                    if (confirmingDeleteKey == "quote-${quote.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条报价项？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteQuoteItem(quote.id)
                                confirmingDeleteKey = null
                                editingQuoteItemId = null
                            }
                        )
                    }
                    if (editingQuoteItemId == quote.id) {
                        QuoteItemFormCard(
                            formKey = "edit-quote-${quote.id}",
                            titleText = "编辑报价项",
                            initialName = quote.name,
                            initialUnitPrice = quote.unitPrice,
                            initialQuantity = quote.quantity,
                            initialUnit = quote.unit,
                            initialVersionName = quote.versionName,
                            initialStatus = quote.status,
                            initialCustomerConfirmedDate = quote.customerConfirmedDate,
                            initialContractAmount = quote.contractAmount,
                            initialNotes = quote.notes,
                            onCancel = { editingQuoteItemId = null },
                            onSave = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                                onUpdateQuoteItem(
                                    quote.id,
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
                                editingQuoteItemId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "人工记录",
                count = detail.laborRecords.size,
                actionLabel = if (showLaborForm) "收起" else "添加人工",
                onAction = { showLaborForm = !showLaborForm }
            )
        }

        if (showLaborForm) {
            item {
                LaborRecordFormCard(
                    onCancel = { showLaborForm = false },
                    onSave = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                        onAddLaborRecord(date, workers, hours, unitRate, workType, teamName, isSettled, note)
                        showLaborForm = false
                    }
                )
            }
        }

        if (detail.laborRecords.isEmpty()) {
            item {
                CompactEmptyText("暂无人工记录")
            }
        } else {
            items(
                items = detail.laborRecords,
                key = LaborRecordSummary::id
            ) { labor ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    LaborRecordRow(
                        labor = labor,
                        onEdit = {
                            editingLaborRecordId = if (editingLaborRecordId == labor.id) {
                                null
                            } else {
                                labor.id
                            }
                        },
                        onToggleSettled = {
                            onSetLaborRecordSettled(labor.id, !labor.isSettled)
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "labor-${labor.id}"
                        }
                    )
                    if (confirmingDeleteKey == "labor-${labor.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条人工记录？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteLaborRecord(labor.id)
                                confirmingDeleteKey = null
                                editingLaborRecordId = null
                            }
                        )
                    }
                    if (editingLaborRecordId == labor.id) {
                        LaborRecordFormCard(
                            formKey = "edit-labor-${labor.id}",
                            titleText = "编辑人工记录",
                            initialDate = labor.date,
                            initialWorkers = labor.workers,
                            initialHours = labor.hours,
                            initialUnitRate = labor.unitRate,
                            initialWorkType = labor.workType,
                            initialTeamName = labor.teamName,
                            initialIsSettled = labor.isSettled,
                            initialNote = labor.note,
                            onCancel = { editingLaborRecordId = null },
                            onSave = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                                onUpdateLaborRecord(
                                    labor.id,
                                    date,
                                    workers,
                                    hours,
                                    unitRate,
                                    workType,
                                    teamName,
                                    isSettled,
                                    note
                                )
                                editingLaborRecordId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "项目仓库",
                count = detail.warehouseMovements.size,
                actionLabel = if (showWarehouseForm) "收起" else "添加出入库",
                onAction = { showWarehouseForm = !showWarehouseForm }
            )
        }

        if (detail.warehouseMovements.isNotEmpty()) {
            item {
                WarehouseStockSummaryCard(movements = detail.warehouseMovements)
            }
        }

        if (showWarehouseForm) {
            item {
                WarehouseMovementFormCard(
                    onCancel = { showWarehouseForm = false },
                    onSave = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                        onAddWarehouseMovement(
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
                        showWarehouseForm = false
                    }
                )
            }
        }

        if (detail.warehouseMovements.isEmpty()) {
            item {
                CompactEmptyText("暂无出入库记录")
            }
        } else {
            items(
                items = detail.warehouseMovements,
                key = ProjectWarehouseMovementSummary::id
            ) { movement ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    WarehouseMovementRow(
                        movement = movement,
                        onEdit = {
                            editingWarehouseMovementId = if (editingWarehouseMovementId == movement.id) {
                                null
                            } else {
                                movement.id
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "warehouse-${movement.id}"
                        }
                    )
                    if (confirmingDeleteKey == "warehouse-${movement.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条出入库记录？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteWarehouseMovement(movement.id)
                                confirmingDeleteKey = null
                                editingWarehouseMovementId = null
                            }
                        )
                    }
                    if (editingWarehouseMovementId == movement.id) {
                        WarehouseMovementFormCard(
                            formKey = "edit-warehouse-${movement.id}",
                            titleText = "编辑出入库",
                            initialDate = movement.date,
                            initialMovementType = movement.movementType,
                            initialMaterialName = movement.materialName,
                            initialSpecification = movement.specification,
                            initialUnit = movement.unit,
                            initialQuantity = movement.quantity,
                            initialCounterparty = movement.counterparty,
                            initialHandler = movement.handler,
                            initialNote = movement.note,
                            onCancel = { editingWarehouseMovementId = null },
                            onSave = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                                onUpdateWarehouseMovement(
                                    movement.id,
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
                                editingWarehouseMovementId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "收支记录",
                count = detail.financialRecords.size,
                actionLabel = if (showFinancialRecordForm) "收起" else "添加收支",
                onAction = { showFinancialRecordForm = !showFinancialRecordForm }
            )
        }

        if (showFinancialRecordForm) {
            item {
                FinancialRecordFormCard(
                    onCancel = { showFinancialRecordForm = false },
                    onSave = { date, direction, category, amount, counterparty, status, dueDate, note ->
                        onAddFinancialRecord(date, direction, category, amount, counterparty, status, dueDate, note)
                        showFinancialRecordForm = false
                    }
                )
            }
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
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    FinancialRecordRow(
                        record = record,
                        onEdit = {
                            editingFinancialRecordId = if (editingFinancialRecordId == record.id) {
                                null
                            } else {
                                record.id
                            }
                        },
                        onUpdateStatus = { status ->
                            onUpdateFinancialRecordStatus(record.id, status)
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "financial-${record.id}"
                        }
                    )
                    if (confirmingDeleteKey == "financial-${record.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条收支记录？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteFinancialRecord(record.id)
                                confirmingDeleteKey = null
                                editingFinancialRecordId = null
                            }
                        )
                    }
                    if (editingFinancialRecordId == record.id) {
                        FinancialRecordFormCard(
                            formKey = "edit-financial-${record.id}",
                            title = "编辑收支记录",
                            initialDate = record.date,
                            initialDirection = record.direction,
                            initialCategory = record.category,
                            initialAmount = record.amount,
                            initialCounterparty = record.counterparty,
                            initialStatus = record.status,
                            initialDueDate = record.dueDate,
                            initialNote = record.note,
                            onCancel = { editingFinancialRecordId = null },
                            onSave = { date, direction, category, amount, counterparty, status, dueDate, note ->
                                onUpdateFinancialRecord(
                                    record.id,
                                    date,
                                    direction,
                                    category,
                                    amount,
                                    counterparty,
                                    status,
                                    dueDate,
                                    note
                                )
                                editingFinancialRecordId = null
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionTitle(
                title = "材料状态",
                count = detail.materialItems.size,
                actionLabel = if (showMaterialItemForm) "收起" else "添加材料",
                onAction = { showMaterialItemForm = !showMaterialItemForm }
            )
        }

        if (showMaterialItemForm) {
            item {
                MaterialItemFormCard(
                    onCancel = { showMaterialItemForm = false },
                    onSave = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                        onAddMaterialItem(name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate)
                        showMaterialItemForm = false
                    }
                )
            }
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
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    MaterialItemRow(
                        material = material,
                        onEdit = {
                            editingMaterialItemId = if (editingMaterialItemId == material.id) {
                                null
                            } else {
                                material.id
                            }
                        },
                        onUpdateStatus = { purchaseStatus ->
                            onUpdateMaterialPurchaseStatus(material.id, purchaseStatus)
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "material-${material.id}"
                        }
                    )
                    if (confirmingDeleteKey == "material-${material.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条材料记录？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteMaterialItem(material.id)
                                confirmingDeleteKey = null
                                editingMaterialItemId = null
                            }
                        )
                    }
                    if (editingMaterialItemId == material.id) {
                        MaterialItemFormCard(
                            formKey = "edit-material-${material.id}",
                            title = "编辑材料",
                            initialName = material.name,
                            initialSpecification = material.specification,
                            initialQuantity = material.quantity,
                            initialUnit = material.unit,
                            initialUnitPrice = material.unitPrice,
                            initialSupplier = material.supplier,
                            initialPurchaseStatus = material.purchaseStatus,
                            initialArrivalDate = material.arrivalDate,
                            onCancel = { editingMaterialItemId = null },
                            onSave = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                                onUpdateMaterialItem(
                                    material.id,
                                    name,
                                    specification,
                                    quantity,
                                    unit,
                                    unitPrice,
                                    supplier,
                                    purchaseStatus,
                                    arrivalDate
                                )
                                editingMaterialItemId = null
                            }
                        )
                    }
                }
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
                    availableMethods = detail.constructionMethods,
                    onCancel = { showDailyLogForm = false },
                    onSave = { date, content, workers, weather, linkedMethodIds ->
                        onAddDailyLog(date, content, workers, weather, linkedMethodIds)
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
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    DailyLogRow(
                        log = log,
                        linkedMethodTitles = linkedMethodTitles(detail.constructionMethods, log.linkedConstructionMethodIds),
                        onEdit = {
                            editingDailyLogId = if (editingDailyLogId == log.id) {
                                null
                            } else {
                                log.id
                            }
                        },
                        onAddPhoto = {
                            photoPickerTargetKind = "daily"
                            photoPickerTargetId = log.id
                            photoFilePicker.launch(arrayOf("image/*"))
                        },
                        onOpenPhoto = { fileName ->
                            openLocalPhoto(context, fileName)
                        },
                        onDeletePhoto = { fileName ->
                            deletePhotoArchive(context, fileName)
                            onDeleteDailyLogPhoto(log.id, fileName)
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "daily-${log.id}"
                        }
                    )
                    if (confirmingDeleteKey == "daily-${log.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条施工日志？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteDailyLog(log.id)
                                confirmingDeleteKey = null
                                editingDailyLogId = null
                            }
                        )
                    }
                    if (editingDailyLogId == log.id) {
                        DailyLogFormCard(
                            formKey = "edit-daily-log-${log.id}",
                            title = "编辑施工日志",
                            availableMethods = detail.constructionMethods,
                            initialDate = log.date,
                            initialContent = log.content,
                            initialWorkers = log.workers,
                            initialWeather = log.weather,
                            initialLinkedMethodIds = log.linkedConstructionMethodIds,
                            onCancel = { editingDailyLogId = null },
                            onSave = { date, content, workers, weather, linkedMethodIds ->
                                onUpdateDailyLog(log.id, date, content, workers, weather, linkedMethodIds)
                                editingDailyLogId = null
                            }
                        )
                    }
                }
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
                    availableMethods = detail.constructionMethods,
                    onCancel = { showTodoForm = false },
                    onSave = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                        onAddSiteTodo(title, owner, dueDate, priority, issueType, linkedMethodIds)
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
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    SiteTodoRow(
                        todo = todo,
                        linkedMethodTitles = linkedMethodTitles(detail.constructionMethods, todo.linkedConstructionMethodIds),
                        onEdit = {
                            editingTodoId = if (editingTodoId == todo.id) {
                                null
                            } else {
                                todo.id
                            }
                        },
                        onToggleDone = {
                            onSetSiteTodoDone(todo.id, !todo.isDone)
                        },
                        onAttachBeforePhoto = {
                            photoPickerTargetKind = "todo-before"
                            photoPickerTargetId = todo.id
                            photoFilePicker.launch(arrayOf("image/*"))
                        },
                        onAttachAfterPhoto = {
                            photoPickerTargetKind = "todo-after"
                            photoPickerTargetId = todo.id
                            photoFilePicker.launch(arrayOf("image/*"))
                        },
                        onOpenPhoto = { fileName ->
                            openLocalPhoto(context, fileName)
                        },
                        onDeleteBeforePhoto = {
                            todo.rectificationBeforePhotoFileName?.let { fileName ->
                                deletePhotoArchive(context, fileName)
                                onDeleteSiteTodoPhoto(todo.id, SiteTodoPhotoTarget.Before)
                            }
                        },
                        onDeleteAfterPhoto = {
                            todo.rectificationAfterPhotoFileName?.let { fileName ->
                                deletePhotoArchive(context, fileName)
                                onDeleteSiteTodoPhoto(todo.id, SiteTodoPhotoTarget.After)
                            }
                        },
                        onDeleteRequest = {
                            confirmingDeleteKey = "todo-${todo.id}"
                        }
                    )
                    if (confirmingDeleteKey == "todo-${todo.id}") {
                        ConfirmDeleteRow(
                            label = "删除这条待办？",
                            onCancel = { confirmingDeleteKey = null },
                            onConfirm = {
                                onDeleteSiteTodo(todo.id)
                                confirmingDeleteKey = null
                                editingTodoId = null
                            }
                        )
                    }
                    if (editingTodoId == todo.id) {
                        SiteTodoFormCard(
                            formKey = "edit-todo-${todo.id}",
                            titleText = "编辑待办整改",
                            availableMethods = detail.constructionMethods,
                            initialTitle = todo.title,
                            initialOwner = todo.owner,
                            initialDueDate = todo.dueDate,
                            initialPriority = todo.priority,
                            initialIssueType = todo.issueType,
                            initialLinkedMethodIds = todo.linkedConstructionMethodIds,
                            onCancel = { editingTodoId = null },
                            onSave = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                                onUpdateSiteTodo(todo.id, title, owner, dueDate, priority, issueType, linkedMethodIds)
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
private fun FinancialRecordRow(
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
private fun QuoteItemRow(
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
private fun LaborRecordRow(
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
private fun WarehouseStockSummaryCard(
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
private fun WarehouseMovementRow(
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
private fun MaterialItemRow(
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
private fun ProgressTaskRow(
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
private fun ProjectDeliveryExportCard(
    detail: ProjectDetail,
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
    val attachmentCount = detail.documents.count { it.localUri.isNotBlank() } +
        detail.drawings.count { it.localUri.isNotBlank() }
    val photoCount = detail.dailyLogs.sumOf { it.photoCount } +
        detail.siteTodos.sumOf { todo ->
            listOf(todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName)
                .count { !it.isNullOrBlank() }
        }

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
                    label = "附件",
                    value = "$attachmentCount",
                    modifier = Modifier.weight(1f)
                )
                ProjectMetric(
                    label = "照片",
                    value = "$photoCount",
                    modifier = Modifier.weight(1f)
                )
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
private fun DailyLogRow(
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
private fun ProjectContactRow(
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
private fun ProjectDocumentRow(
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
private fun ProjectDrawingRow(
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
private fun rememberDocumentArchiveStatus(localUri: String): DocumentArchiveStatus {
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
private fun SiteTodoRow(
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
private fun PhotoAttachmentLine(
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
private fun TodoPhotoLine(
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

private fun progressPercentText(completion: Double): String =
    "${(completion.coerceIn(0.0, 1.0) * 100).toInt()}%"

private fun quoteLineAmountText(quote: QuoteItemSummary): String {
    val amount = amountValue(quote.unitPrice) * amountValue(quote.quantity)
    return if (amount > 0.0) moneyText(amount) else "-"
}

private fun quoteMetaText(quote: QuoteItemSummary): String =
    listOfNotNull(
        quote.versionName.takeIf(String::isNotBlank),
        quote.status.takeIf(String::isNotBlank),
        "${quote.quantity} ${quote.unit}".trim().takeIf(String::isNotBlank),
        quote.unitPrice.takeIf(String::isNotBlank)?.let { "单价 $it" },
        quote.customerConfirmedDate.takeIf(String::isNotBlank)?.let { "确认 $it" }
    ).joinToString(" · ")

private fun laborTitleText(labor: LaborRecordSummary): String =
    listOf(labor.workType, labor.teamName)
        .filter(String::isNotBlank)
        .joinToString(" · ")
        .ifBlank { "人工记录" }

private fun laborMetaText(labor: LaborRecordSummary): String =
    listOfNotNull(
        labor.date.takeIf(String::isNotBlank),
        labor.workers.takeIf(String::isNotBlank)?.let { "$it 人" },
        labor.hours.takeIf(String::isNotBlank)?.let { "$it 工日" },
        labor.unitRate.takeIf(String::isNotBlank)?.let { "单价 $it" }
    ).joinToString(" · ")

private data class WarehouseStockLine(
    val name: String,
    val specification: String,
    val unit: String,
    val quantity: Double
)

private fun warehouseStockLines(
    movements: List<ProjectWarehouseMovementSummary>
): List<WarehouseStockLine> =
    movements
        .groupBy { movement ->
            listOf(
                movement.materialName.trim(),
                movement.specification.trim(),
                movement.unit.trim()
            ).joinToString("|")
        }
        .map { (_, items) ->
            val first = items.first()
            val quantity = items.sumOf { movement ->
                val sign = if (movement.movementType == "出库") -1.0 else 1.0
                amountValue(movement.quantity) * sign
            }
            WarehouseStockLine(
                name = first.materialName.ifBlank { "未命名材料" },
                specification = first.specification,
                unit = first.unit.ifBlank { "件" },
                quantity = quantity
            )
        }
        .sortedWith(
            compareByDescending<WarehouseStockLine> { it.quantity < 0.0 }
                .thenBy { it.name }
        )

private fun warehouseSignedQuantityText(movement: ProjectWarehouseMovementSummary): String {
    val prefix = if (movement.movementType == "出库") "-" else "+"
    return "$prefix${movement.quantity} ${movement.unit}".trim()
}

private fun warehouseMetaText(movement: ProjectWarehouseMovementSummary): String =
    listOfNotNull(
        movement.movementType.takeIf(String::isNotBlank),
        movement.date.takeIf(String::isNotBlank),
        movement.specification.takeIf(String::isNotBlank),
        movement.counterparty.takeIf(String::isNotBlank),
        movement.handler.takeIf(String::isNotBlank)?.let { "经手 $it" },
        movement.linkedDocumentCount.takeIf { it > 0 }?.let { "$it 个单据" }
    ).joinToString(" · ")

private fun nextMaterialPurchaseStatus(status: String): String =
    when (status) {
        "待采购" -> "已采购"
        "已采购" -> "已进场"
        "已进场" -> "待采购"
        else -> "已采购"
    }

private fun importPreviewText(preview: BackupImportPreview): String =
    listOf(
        "项目 ${preview.projectCount}",
        "日志 ${preview.dailyLogCount}",
        "待办 ${preview.siteTodoCount}",
        "收支 ${preview.financialRecordCount}",
        "材料 ${preview.materialItemCount}",
        "随手记 ${preview.quickNoteCount}",
        "联系人 ${preview.projectContactCount}",
        "资料 ${preview.projectDocumentCount}",
        "进度 ${preview.progressTaskCount}",
        "图纸 ${preview.projectDrawingCount}",
        "报价 ${preview.quoteItemCount}",
        "人工 ${preview.laborRecordCount}",
        "仓库 ${preview.projectWarehouseMovementCount}",
        "价格库 ${preview.materialPriceEntryCount}",
        "供应商 ${preview.supplierProfileCount}",
        "工艺 ${preview.constructionMethodCount}"
    ).joinToString(" · ")

private fun linkedMethodTitles(
    methods: List<ConstructionMethodSummary>,
    linkedIds: List<String>
): List<String> {
    if (linkedIds.isEmpty()) {
        return emptyList()
    }
    val methodsById = methods.associateBy { method -> method.id }
    return linkedIds.mapNotNull { methodId ->
        methodsById[methodId]?.displayTitle ?: methodId.takeIf(String::isNotBlank)
    }
}

private fun projectRiskText(project: ProjectSummary): String =
    listOfNotNull(
        riskItemText(
            label = "逾期待办",
            count = project.overdueTodoCount
        ),
        riskItemText(
            label = "到期收款",
            count = project.dueIncomeCount
        ),
        riskItemText(
            label = "未进场材料",
            count = project.unarrivedMaterialCount
        )
    ).joinToString(" · ")

private fun riskItemText(
    label: String,
    count: Int
): String? =
    if (count > 0) {
        "$label $count"
    } else {
        null
    }

private fun ProjectSummary.totalRiskCount(): Int =
    overdueTodoCount + dueIncomeCount + unarrivedMaterialCount

private fun List<ProjectSummary>.sortByRiskPriority(): List<ProjectSummary> =
    sortedWith(
        compareByDescending<ProjectSummary> { it.overdueTodoCount }
            .thenByDescending { it.dueIncomeCount }
            .thenByDescending { it.unarrivedMaterialCount }
            .thenByDescending { it.latestActivityDate.ifBlank { "0000-00-00" } }
            .thenBy { it.name.lowercase(Locale.ROOT) }
    )

private fun dashboardProjectSublineText(project: ProjectSummary): String =
    listOfNotNull(
        project.expectedEndDate
            .takeIf(String::isNotBlank)
            ?.let { "计划完工 $it" },
        project.latestActivityDate
            .takeIf(String::isNotBlank)
            ?.let { "最近 $it" }
    ).joinToString(" · ").ifBlank { "暂无日期" }

private fun List<ChecklistTodoSummary>.filterChecklistBy(
    statusFilter: ChecklistStatusFilter,
    priorityFilter: ChecklistPriorityFilter,
    ownerQuery: String
): List<ChecklistTodoSummary> {
    val keyword = ownerQuery.trim().lowercase(Locale.ROOT)

    return filter { todo ->
        todo.matchesStatusFilter(statusFilter) &&
            todo.matchesPriorityFilter(priorityFilter) &&
            todo.matchesChecklistKeyword(keyword)
    }
}

private fun ChecklistTodoSummary.matchesStatusFilter(filter: ChecklistStatusFilter): Boolean =
    when (filter) {
        ChecklistStatusFilter.Open -> !isDone && !isProjectArchived
        ChecklistStatusFilter.Overdue -> isOverdue && !isProjectArchived
        ChecklistStatusFilter.All -> true
        ChecklistStatusFilter.Done -> isDone
    }

private fun ChecklistTodoSummary.matchesPriorityFilter(filter: ChecklistPriorityFilter): Boolean =
    filter.priority == null || priority == filter.priority

private fun ChecklistTodoSummary.matchesChecklistKeyword(keyword: String): Boolean =
    keyword.isBlank() ||
        listOf(title, owner, projectName, projectLocation, issueType)
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }

private fun List<ChecklistTodoSummary>.sortForChecklist(): List<ChecklistTodoSummary> =
    sortedWith(
        compareBy<ChecklistTodoSummary> { it.isDone }
            .thenBy { !it.isOverdue }
            .thenByDescending { priorityWeight(it.priority) }
            .thenBy { it.dueDate.ifBlank { "9999-99-99" } }
            .thenBy { it.projectName.lowercase(Locale.ROOT) }
            .thenBy { it.title.lowercase(Locale.ROOT) }
    )

private fun priorityWeight(priority: String): Int =
    when (priority) {
        "高" -> 3
        "普通" -> 2
        "低" -> 1
        else -> 2
    }

private fun checklistTodoStateText(todo: ChecklistTodoSummary): String =
    when {
        todo.isDone -> "已完成"
        todo.isProjectArchived -> "归档项目"
        todo.isOverdue -> "逾期"
        else -> "未完成"
    }

private fun checklistEmptyTitle(filter: ChecklistStatusFilter): String =
    when (filter) {
        ChecklistStatusFilter.Open -> "暂无未完成待办"
        ChecklistStatusFilter.Overdue -> "暂无逾期待办"
        ChecklistStatusFilter.All -> "暂无待办"
        ChecklistStatusFilter.Done -> "暂无已完成待办"
    }

private fun List<QuickNoteSummary>.filterNotesBy(
    query: String,
    projectId: String?
): List<QuickNoteSummary> {
    val keyword = query.trim().lowercase(Locale.ROOT)

    return filter { note ->
        (projectId == null || note.projectId == projectId) &&
            note.matchesNoteKeyword(keyword)
    }
}

private fun QuickNoteSummary.matchesNoteKeyword(keyword: String): Boolean =
    keyword.isBlank() ||
        (
            listOf(title, content, projectName, projectLocation) +
                attachments.flatMap { attachment ->
                    listOf(
                        attachment.originalName,
                        attachment.fileName,
                        quickNoteAttachmentKindText(attachment.kind)
                    )
                }
            )
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }

private fun List<QuickNoteSummary>.sortForNotes(): List<QuickNoteSummary> =
    sortedWith(
        compareByDescending<QuickNoteSummary> { it.updatedAt.ifBlank { it.createdAt } }
            .thenBy { it.title.lowercase(Locale.ROOT) }
    )

private fun noteMetaText(note: QuickNoteSummary): String =
    listOfNotNull(
        note.projectName
            .takeIf(String::isNotBlank)
            ?.let { projectName ->
                if (note.isProjectArchived) {
                    "$projectName · 已归档"
                } else {
                    projectName
                }
            }
            ?: "未关联项目",
        note.attachmentCount
            .takeIf { it > 0 }
            ?.let { "附件 $it" }
    ).joinToString(" · ")

private fun quickNoteAttachmentMetaText(attachment: QuickNoteAttachmentSummary): String =
    listOfNotNull(
        quickNoteAttachmentKindText(attachment.kind),
        attachment.createdAt.takeIf(String::isNotBlank),
        attachment.durationSeconds
            ?.takeIf { it > 0.0 }
            ?.let { seconds -> "${seconds.toInt()} 秒" }
    ).joinToString(" · ")

private fun quickNoteAttachmentKindText(kind: String): String =
    when (kind.lowercase(Locale.ROOT)) {
        "photo", "image" -> "照片"
        "audio", "voice" -> "录音"
        "video" -> "视频"
        else -> "文件"
    }

private fun projectDocumentMetaText(document: ProjectDocumentSummary): String =
    listOfNotNull(
        document.category.takeIf(String::isNotBlank),
        "${document.pageCount.coerceAtLeast(1)} 页",
        document.amount.takeIf(String::isNotBlank)?.let { "金额 $it" },
        document.createdAt.takeIf(String::isNotBlank)
    ).joinToString(" · ")

private fun projectDrawingMetaText(drawing: ProjectDrawingSummary): String =
    listOfNotNull(
        drawing.fileType.takeIf(String::isNotBlank),
        drawing.version.takeIf(String::isNotBlank),
        if (drawing.isCurrentVersion) "当前版本" else "历史版本",
        drawing.relatedLogDate.takeIf(String::isNotBlank)?.let { "关联 $it" },
        drawing.importedAt.takeIf(String::isNotBlank)
    ).joinToString(" · ")

private fun projectDocumentPickActionText(status: DocumentArchiveStatus): String =
    when (status) {
        DocumentArchiveStatus.NotLinked -> "选择文件"
        DocumentArchiveStatus.Checking -> "更换文件"
        DocumentArchiveStatus.Archived -> "更换文件"
        DocumentArchiveStatus.Missing -> "重新选择"
    }

private fun List<ProjectSummary>.filterBy(filter: ProjectListFilter): List<ProjectSummary> =
    when (filter) {
        ProjectListFilter.Active -> filter { it.status != "已归档" }
        ProjectListFilter.All -> this
        ProjectListFilter.Archived -> filter { it.status == "已归档" }
    }

private fun List<ProjectSummary>.searchBy(query: String): List<ProjectSummary> {
    val keyword = query.trim().lowercase(Locale.ROOT)
    if (keyword.isBlank()) {
        return this
    }

    return filter { project ->
        listOf(project.name, project.location, project.managerName)
            .any { value -> value.lowercase(Locale.ROOT).contains(keyword) }
    }
}

private fun List<ProjectSummary>.sortBy(option: ProjectSortOption): List<ProjectSummary> =
    when (option) {
        ProjectSortOption.LatestActivity -> sortedWith(
            compareByDescending<ProjectSummary> { it.latestActivityDate.ifBlank { "0000-00-00" } }
                .thenBy { it.name.lowercase(Locale.ROOT) }
        )
        ProjectSortOption.Name -> sortedBy { it.name.lowercase(Locale.ROOT) }
        ProjectSortOption.ExpectedEnd -> sortedWith(
            compareBy<ProjectSummary> { it.expectedEndDate.ifBlank { "9999-99-99" } }
                .thenBy { it.name.lowercase(Locale.ROOT) }
        )
    }

private fun emptyProjectTitle(
    filter: ProjectListFilter,
    searchQuery: String
): String =
    if (searchQuery.isNotBlank()) {
        "未找到匹配项目"
    } else when (filter) {
        ProjectListFilter.Active -> "暂无进行中项目"
        ProjectListFilter.All -> "暂无项目"
        ProjectListFilter.Archived -> "暂无已归档项目"
    }

private fun emptyProjectMessage(
    filter: ProjectListFilter,
    searchQuery: String
): String =
    if (searchQuery.isNotBlank()) {
        "换个关键词或切换筛选条件。"
    } else when (filter) {
        ProjectListFilter.Active -> "可新建项目或切到全部查看归档项目。"
        ProjectListFilter.All -> "等待导入备份或新建项目。"
        ProjectListFilter.Archived -> "归档项目会显示在这里。"
    }

private fun todayText(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

@Composable
private fun EmptyProjectState(
    filter: ProjectListFilter,
    searchQuery: String
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = emptyProjectTitle(
                filter = filter,
                searchQuery = searchQuery
            ),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = emptyProjectMessage(
                filter = filter,
                searchQuery = searchQuery
            ),
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
