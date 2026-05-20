package com.chengjinfang.sitekeeper.database.project

import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordDao
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordEntity
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.finance.toEntity
import com.chengjinfang.sitekeeper.database.finance.toSummary
import com.chengjinfang.sitekeeper.database.SitekeeperDatabase
import com.chengjinfang.sitekeeper.database.contact.ProjectContactDao
import com.chengjinfang.sitekeeper.database.contact.ProjectContactEntity
import com.chengjinfang.sitekeeper.database.contact.ProjectContactSummary
import com.chengjinfang.sitekeeper.database.contact.toBackupProjectContact
import com.chengjinfang.sitekeeper.database.contact.toEntity
import com.chengjinfang.sitekeeper.database.contact.toSummary
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentDao
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentEntity
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentSummary
import com.chengjinfang.sitekeeper.database.document.toBackupProjectDocument
import com.chengjinfang.sitekeeper.database.document.toEntity
import com.chengjinfang.sitekeeper.database.document.toSummary
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingDao
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingEntity
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.drawing.toBackupProjectDrawing
import com.chengjinfang.sitekeeper.database.drawing.toEntity
import com.chengjinfang.sitekeeper.database.drawing.toSummary
import com.chengjinfang.sitekeeper.database.labor.LaborRecordDao
import com.chengjinfang.sitekeeper.database.labor.LaborRecordEntity
import com.chengjinfang.sitekeeper.database.labor.LaborRecordSummary
import com.chengjinfang.sitekeeper.database.labor.toBackupLaborRecord
import com.chengjinfang.sitekeeper.database.labor.toEntity
import com.chengjinfang.sitekeeper.database.labor.toSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemDao
import com.chengjinfang.sitekeeper.database.material.MaterialItemEntity
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.material.DefaultMaterialLibrary
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryDao
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryEntity
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntrySummary
import com.chengjinfang.sitekeeper.database.material.SupplierProfileDao
import com.chengjinfang.sitekeeper.database.material.SupplierProfileEntity
import com.chengjinfang.sitekeeper.database.material.SupplierProfileSummary
import com.chengjinfang.sitekeeper.database.material.toBackupMaterialPriceEntry
import com.chengjinfang.sitekeeper.database.material.toBackupSupplierProfile
import com.chengjinfang.sitekeeper.database.material.toEntity
import com.chengjinfang.sitekeeper.database.material.toSummary
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodDao
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodEntity
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodSummary
import com.chengjinfang.sitekeeper.database.method.DefaultConstructionMethodLibrary
import com.chengjinfang.sitekeeper.database.method.encodeConstructionMethodLines
import com.chengjinfang.sitekeeper.database.method.normalizedConstructionPublishStatus
import com.chengjinfang.sitekeeper.database.method.toBackupConstructionMethod
import com.chengjinfang.sitekeeper.database.method.toEntity
import com.chengjinfang.sitekeeper.database.method.toSummary
import com.chengjinfang.sitekeeper.database.note.QuickNoteDao
import com.chengjinfang.sitekeeper.database.note.QuickNoteEntity
import com.chengjinfang.sitekeeper.database.note.toBackupQuickNote
import com.chengjinfang.sitekeeper.database.note.toEntity
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskDao
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskEntity
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskSummary
import com.chengjinfang.sitekeeper.database.progress.toEntity
import com.chengjinfang.sitekeeper.database.progress.toSummary
import com.chengjinfang.sitekeeper.database.quote.QuoteItemDao
import com.chengjinfang.sitekeeper.database.quote.QuoteItemEntity
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.quote.toBackupQuoteItem
import com.chengjinfang.sitekeeper.database.quote.toEntity
import com.chengjinfang.sitekeeper.database.quote.toSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogDao
import com.chengjinfang.sitekeeper.database.record.DailyLogEntity
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoDao
import com.chengjinfang.sitekeeper.database.record.SiteTodoEntity
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.record.toBackupLogPhotos
import com.chengjinfang.sitekeeper.database.record.toEntity
import com.chengjinfang.sitekeeper.database.record.toSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementDao
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementEntity
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary
import com.chengjinfang.sitekeeper.database.warehouse.normalizedWarehouseMovementType
import com.chengjinfang.sitekeeper.database.warehouse.toBackupProjectWarehouseMovement
import com.chengjinfang.sitekeeper.database.warehouse.toEntity
import com.chengjinfang.sitekeeper.database.warehouse.toSummary
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshot
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ConstructionMethod
import com.chengjinfang.sitekeeper.model.backup.DailyLog
import com.chengjinfang.sitekeeper.model.backup.LaborRecord
import com.chengjinfang.sitekeeper.model.backup.LogPhoto
import com.chengjinfang.sitekeeper.model.backup.MaterialItem
import com.chengjinfang.sitekeeper.model.backup.MaterialPriceEntry
import com.chengjinfang.sitekeeper.model.backup.Project
import com.chengjinfang.sitekeeper.model.backup.ProjectContact
import com.chengjinfang.sitekeeper.model.backup.ProjectDocument
import com.chengjinfang.sitekeeper.model.backup.ProjectFinancialRecord
import com.chengjinfang.sitekeeper.model.backup.ProgressTask
import com.chengjinfang.sitekeeper.model.backup.QuickNote
import com.chengjinfang.sitekeeper.model.backup.QuickNoteAttachment
import com.chengjinfang.sitekeeper.model.backup.QuoteItem
import com.chengjinfang.sitekeeper.model.backup.SiteTodo
import com.chengjinfang.sitekeeper.model.backup.SupplierProfile
import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

class ProjectRepository(
    private val database: SitekeeperDatabase,
    private val projectDao: ProjectDao,
    private val dailyLogDao: DailyLogDao,
    private val siteTodoDao: SiteTodoDao,
    private val financialRecordDao: ProjectFinancialRecordDao,
    private val materialItemDao: MaterialItemDao,
    private val quickNoteDao: QuickNoteDao,
    private val projectContactDao: ProjectContactDao,
    private val projectDocumentDao: ProjectDocumentDao,
    private val progressTaskDao: ProgressTaskDao,
    private val projectDrawingDao: ProjectDrawingDao,
    private val quoteItemDao: QuoteItemDao,
    private val laborRecordDao: LaborRecordDao,
    private val projectWarehouseMovementDao: ProjectWarehouseMovementDao,
    private val materialPriceEntryDao: MaterialPriceEntryDao,
    private val supplierProfileDao: SupplierProfileDao,
    private val constructionMethodDao: ConstructionMethodDao
) {
    private val backupUseCases = ProjectBackupUseCases(
        database = database,
        projectDao = projectDao,
        dailyLogDao = dailyLogDao,
        siteTodoDao = siteTodoDao,
        financialRecordDao = financialRecordDao,
        materialItemDao = materialItemDao,
        quickNoteDao = quickNoteDao,
        projectContactDao = projectContactDao,
        projectDocumentDao = projectDocumentDao,
        progressTaskDao = progressTaskDao,
        projectDrawingDao = projectDrawingDao,
        quoteItemDao = quoteItemDao,
        laborRecordDao = laborRecordDao,
        projectWarehouseMovementDao = projectWarehouseMovementDao,
        materialPriceEntryDao = materialPriceEntryDao,
        supplierProfileDao = supplierProfileDao,
        constructionMethodDao = constructionMethodDao
    )

    val projects: Flow<List<ProjectSummary>> =
        combine(
            projectDao.observeProjects(),
            dailyLogDao.observeDailyLogs(),
            siteTodoDao.observeSiteTodos(),
            financialRecordDao.observeFinancialRecords(),
            materialItemDao.observeMaterialItems()
        ) { projects, dailyLogs, siteTodos, financialRecords, materialItems ->
            val today = currentDateText()
            val dailyLogCounts = dailyLogs
                .mapNotNull { it.projectId }
                .groupingBy { it }
                .eachCount()
            val openTodoCounts = siteTodos
                .filter { !it.isDone }
                .mapNotNull { it.projectId }
                .groupingBy { it }
                .eachCount()
            val financialRecordCounts = financialRecords
                .map { it.projectId }
                .groupingBy { it }
                .eachCount()
            val materialItemCounts = materialItems
                .mapNotNull { it.projectId }
                .groupingBy { it }
                .eachCount()
            val overdueTodoCounts = siteTodos
                .filter { !it.isDone && isBeforeToday(it.dueDate, today) }
                .mapNotNull { it.projectId }
                .groupingBy { it }
                .eachCount()
            val dueIncomeCounts = financialRecords
                .filter { it.direction == "收入" && isOnOrBeforeToday(it.dueDate, today) }
                .map { it.projectId }
                .groupingBy { it }
                .eachCount()
            val unarrivedMaterialCounts = materialItems
                .filter { it.purchaseStatus != "已进场" }
                .mapNotNull { it.projectId }
                .groupingBy { it }
                .eachCount()
            val latestActivityDates = mutableMapOf<String, String>()

            fun trackActivity(
                projectId: String?,
                date: String?
            ) {
                val normalizedDate = date?.trim().orEmpty()
                if (projectId.isNullOrBlank() || normalizedDate.isBlank()) {
                    return
                }

                val existingDate = latestActivityDates[projectId].orEmpty()
                if (normalizedDate > existingDate) {
                    latestActivityDates[projectId] = normalizedDate
                }
            }

            dailyLogs.forEach { log ->
                trackActivity(log.projectId, log.date)
            }
            siteTodos.forEach { todo ->
                trackActivity(todo.projectId, todo.dueDate)
                trackActivity(todo.projectId, todo.completedAt)
            }
            financialRecords.forEach { record ->
                trackActivity(record.projectId, record.date)
                trackActivity(record.projectId, record.dueDate)
            }
            materialItems.forEach { material ->
                trackActivity(material.projectId, material.arrivalDate)
            }

            projects.map { project ->
                project.toSummary(
                    latestActivityDate = latestActivityDates[project.id].orEmpty(),
                    dailyLogCount = dailyLogCounts[project.id] ?: 0,
                    openTodoCount = openTodoCounts[project.id] ?: 0,
                    financialRecordCount = financialRecordCounts[project.id] ?: 0,
                    materialItemCount = materialItemCounts[project.id] ?: 0,
                    overdueTodoCount = overdueTodoCounts[project.id] ?: 0,
                    dueIncomeCount = dueIncomeCounts[project.id] ?: 0,
                    unarrivedMaterialCount = unarrivedMaterialCounts[project.id] ?: 0
                )
            }
        }

    val checklistTodos: Flow<List<ChecklistTodoSummary>> =
        combine(
            projectDao.observeProjects(),
            siteTodoDao.observeSiteTodos()
        ) { projects, siteTodos ->
            val today = currentDateText()
            val projectsById = projects.associateBy { project -> project.id }

            siteTodos.map { todo ->
                val project = todo.projectId?.let { projectId -> projectsById[projectId] }
                ChecklistTodoSummary(
                    id = todo.id,
                    projectId = todo.projectId.orEmpty(),
                    projectName = project?.name.orEmpty().ifBlank { "未关联项目" },
                    projectLocation = project?.location.orEmpty(),
                    projectStatus = project?.status.orEmpty(),
                    title = todo.title,
                    owner = todo.owner,
                    dueDate = todo.dueDate,
                    priority = todo.priority,
                    issueType = todo.issueType,
                    isDone = todo.isDone,
                    note = todo.note,
                    linkedConstructionMethodIds = BackupSnapshotJson.decodeStringList(todo.linkedConstructionMethodIdsJson),
                    isOverdue = !todo.isDone && isBeforeToday(todo.dueDate, today),
                    isProjectArchived = project?.status == "已归档"
                )
            }
        }

    val quickNotes: Flow<List<QuickNoteSummary>> =
        combine(
            projectDao.observeProjects(),
            quickNoteDao.observeQuickNotes()
        ) { projects, notes ->
            val projectsById = projects.associateBy { project -> project.id }

            notes.map { note ->
                val project = note.projectId?.let { projectId -> projectsById[projectId] }
                val attachments = note.toBackupQuickNote()
                    .attachments
                    .map { attachment -> attachment.toSummary() }
                QuickNoteSummary(
                    id = note.id,
                    title = note.title,
                    content = note.content,
                    projectId = note.projectId.orEmpty(),
                    projectName = project?.name.orEmpty(),
                    projectLocation = project?.location.orEmpty(),
                    createdAt = note.createdAt,
                    updatedAt = note.updatedAt,
                    attachments = attachments,
                    attachmentCount = attachments.size,
                    isProjectArchived = project?.status == "已归档"
                )
            }
        }

    val materialLibrary: Flow<MaterialLibraryOverview> =
        combine(
            materialPriceEntryDao.observeMaterialPriceEntries(),
            supplierProfileDao.observeSupplierProfiles(),
            materialItemDao.observeMaterialItems(),
            projectWarehouseMovementDao.observeProjectWarehouseMovements()
        ) { priceEntries, suppliers, projectMaterials, warehouseMovements ->
            MaterialLibraryOverview(
                priceEntries = priceEntries.map { entry -> entry.toSummary() },
                suppliers = suppliers.map { supplier -> supplier.toSummary() },
                projectMaterialCount = projectMaterials.size,
                warehouseMaterialNames = warehouseMovements
                    .map { movement -> movement.materialName.trim() }
                    .filter(String::isNotBlank)
                    .distinct()
                    .size
            )
        }

    val constructionMethodLibrary: Flow<ConstructionMethodLibraryOverview> =
        constructionMethodDao.observeConstructionMethods()
            .map { methods ->
                ConstructionMethodLibraryOverview(
                    methods = methods.map { method -> method.toSummary() }
                )
            }

    fun observeProjectDetail(projectId: String): Flow<ProjectDetail?> {
        val baseDetail = combine(
            projectDao.observeProject(projectId),
            dailyLogDao.observeDailyLogsForProject(projectId),
            siteTodoDao.observeSiteTodosForProject(projectId),
            financialRecordDao.observeFinancialRecordsForProject(projectId),
            materialItemDao.observeMaterialItemsForProject(projectId)
        ) { project, dailyLogs, siteTodos, financialRecords, materialItems ->
            project?.let {
                ProjectDetail(
                    project = it.toSummary(
                        latestActivityDate = latestActivityDate(
                            dailyLogs = dailyLogs,
                            siteTodos = siteTodos,
                            financialRecords = financialRecords,
                            materialItems = materialItems
                        ),
                        dailyLogCount = dailyLogs.size,
                        openTodoCount = siteTodos.count { todo -> !todo.isDone },
                        financialRecordCount = financialRecords.size,
                        materialItemCount = materialItems.size,
                        overdueTodoCount = siteTodos.count { todo ->
                            !todo.isDone && isBeforeToday(todo.dueDate, currentDateText())
                        },
                        dueIncomeCount = financialRecords.count { record ->
                            record.direction == "收入" && isOnOrBeforeToday(record.dueDate, currentDateText())
                        },
                        unarrivedMaterialCount = materialItems.count { material ->
                            material.purchaseStatus != "已进场"
                        }
                    ),
                    dailyLogs = dailyLogs.map { log -> log.toSummary() },
                    siteTodos = siteTodos.map { todo -> todo.toSummary() },
                    financialRecords = financialRecords.map { record -> record.toSummary() },
                    materialItems = materialItems.map { material -> material.toSummary() },
                    progressTasks = emptyList(),
                    contacts = emptyList(),
                    documents = emptyList(),
                    drawings = emptyList(),
                    quoteItems = emptyList(),
                    laborRecords = emptyList(),
                    warehouseMovements = emptyList(),
                    constructionMethods = emptyList()
                )
            }
        }

        val linkedDetail = combine(
            baseDetail,
            projectContactDao.observeProjectContactsForProject(projectId),
            projectDocumentDao.observeProjectDocumentsForProject(projectId),
            progressTaskDao.observeProgressTasksForProject(projectId),
            projectDrawingDao.observeProjectDrawingsForProject(projectId)
        ) { detail, contacts, documents, progressTasks, drawings ->
            detail?.copy(
                progressTasks = progressTasks.map { task -> task.toSummary() },
                contacts = contacts.map { contact -> contact.toSummary() },
                documents = documents.map { document -> document.toSummary() },
                drawings = drawings.map { drawing -> drawing.toSummary() }
            )
        }

        return combine(
            linkedDetail,
            quoteItemDao.observeQuoteItemsForProject(projectId),
            laborRecordDao.observeLaborRecordsForProject(projectId),
            projectWarehouseMovementDao.observeProjectWarehouseMovementsForProject(projectId),
            constructionMethodDao.observeConstructionMethods()
        ) { detail, quoteItems, laborRecords, warehouseMovements, constructionMethods ->
            detail?.copy(
                quoteItems = quoteItems.map { quote -> quote.toSummary() },
                laborRecords = laborRecords.map { labor -> labor.toSummary() },
                warehouseMovements = warehouseMovements.map { movement -> movement.toSummary() },
                constructionMethods = constructionMethods.map { method -> method.toSummary() }
            )
        }
    }

    suspend fun seedFromBackupJsonIfEmpty(rawJson: String) {
        val snapshot = BackupSnapshotJson.decode(rawJson)

        if (projectDao.projectCount() == 0) {
            val projects = snapshot.projects.map { it.toEntity() }
            if (projects.isNotEmpty()) {
                projectDao.upsertProjects(projects)
            }
        }

        if (dailyLogDao.dailyLogCount() == 0) {
            val dailyLogs = snapshot.dailyLogs.map { it.toEntity() }
            if (dailyLogs.isNotEmpty()) {
                dailyLogDao.upsertDailyLogs(dailyLogs)
            }
        }

        if (siteTodoDao.siteTodoCount() == 0) {
            val siteTodos = snapshot.siteTodos.map { it.toEntity() }
            if (siteTodos.isNotEmpty()) {
                siteTodoDao.upsertSiteTodos(siteTodos)
            }
        }

        if (financialRecordDao.financialRecordCount() == 0) {
            val financialRecords = snapshot.projectFinancialRecords.map { it.toEntity() }
            if (financialRecords.isNotEmpty()) {
                financialRecordDao.upsertFinancialRecords(financialRecords)
            }
        }

        if (materialItemDao.materialItemCount() == 0) {
            val materials = snapshot.materialItems.map { it.toEntity() }
            if (materials.isNotEmpty()) {
                materialItemDao.upsertMaterialItems(materials)
            }
        }

        if (quickNoteDao.quickNoteCount() == 0) {
            val notes = snapshot.quickNotes.map { it.toEntity() }
            if (notes.isNotEmpty()) {
                quickNoteDao.upsertQuickNotes(notes)
            }
        }

        if (projectContactDao.projectContactCount() == 0) {
            val contacts = snapshot.projectContacts.map { it.toEntity() }
            if (contacts.isNotEmpty()) {
                projectContactDao.upsertProjectContacts(contacts)
            }
        }

        if (projectDocumentDao.projectDocumentCount() == 0) {
            val documents = snapshot.projectDocuments.map { it.toEntity() }
            if (documents.isNotEmpty()) {
                projectDocumentDao.upsertProjectDocuments(documents)
            }
        }

        if (progressTaskDao.progressTaskCount() == 0) {
            val progressTasks = snapshot.progressTasks.map { it.toEntity() }
            if (progressTasks.isNotEmpty()) {
                progressTaskDao.upsertProgressTasks(progressTasks)
            }
        }

        if (projectDrawingDao.projectDrawingCount() == 0) {
            val drawings = snapshot.projectDrawings.map { it.toEntity() }
            if (drawings.isNotEmpty()) {
                projectDrawingDao.upsertProjectDrawings(drawings)
            }
        }

        if (quoteItemDao.quoteItemCount() == 0) {
            val quoteItems = snapshot.quoteItems.map { it.toEntity() }
            if (quoteItems.isNotEmpty()) {
                quoteItemDao.upsertQuoteItems(quoteItems)
            }
        }

        if (laborRecordDao.laborRecordCount() == 0) {
            val laborRecords = snapshot.laborRecords.map { it.toEntity() }
            if (laborRecords.isNotEmpty()) {
                laborRecordDao.upsertLaborRecords(laborRecords)
            }
        }

        if (projectWarehouseMovementDao.projectWarehouseMovementCount() == 0) {
            val movements = snapshot.projectWarehouseMovements.map { it.toEntity() }
            if (movements.isNotEmpty()) {
                projectWarehouseMovementDao.upsertProjectWarehouseMovements(movements)
            }
        }

        if (materialPriceEntryDao.materialPriceEntryCount() == 0) {
            val updatedAt = currentTimestampText()
            val entries = snapshot.materialPriceEntries.mapIndexed { index, entry ->
                entry.toEntity(
                    fallbackId = "imported-material-price-${index + 1}",
                    fallbackUpdatedAt = updatedAt
                )
            }
            if (entries.isNotEmpty()) {
                materialPriceEntryDao.upsertMaterialPriceEntries(entries)
            }
        }

        if (supplierProfileDao.supplierProfileCount() == 0) {
            val updatedAt = currentTimestampText()
            val suppliers = snapshot.supplierProfiles.mapIndexed { index, supplier ->
                supplier.toEntity(
                    fallbackId = "imported-supplier-${index + 1}",
                    fallbackUpdatedAt = updatedAt
                )
            }
            if (suppliers.isNotEmpty()) {
                supplierProfileDao.upsertSupplierProfiles(suppliers)
            }
        }

        if (constructionMethodDao.constructionMethodCount() == 0) {
            val updatedAt = currentTimestampText()
            val methods = snapshot.constructionMethods.mapIndexed { index, method ->
                method.toEntity(
                    fallbackId = "imported-construction-method-${index + 1}",
                    fallbackUpdatedAt = updatedAt
                )
            }
            if (methods.isNotEmpty()) {
                constructionMethodDao.upsertConstructionMethods(methods)
            }
        }
    }

    suspend fun seedDefaultMaterialLibraryIfEmpty() {
        if (materialPriceEntryDao.materialPriceEntryCount() == 0) {
            materialPriceEntryDao.upsertMaterialPriceEntries(DefaultMaterialLibrary.priceEntries)
        }
        if (supplierProfileDao.supplierProfileCount() == 0) {
            supplierProfileDao.upsertSupplierProfiles(DefaultMaterialLibrary.suppliers)
        }
    }

    suspend fun seedDefaultConstructionMethodsIfEmpty() {
        if (constructionMethodDao.constructionMethodCount() == 0) {
            constructionMethodDao.upsertConstructionMethods(DefaultConstructionMethodLibrary.methods)
        }
    }

    fun previewBackupJson(rawJson: String): BackupImportPreview =
        backupUseCases.previewBackupJson(rawJson)

    suspend fun importBackupJson(
        rawJson: String,
        mode: BackupImportMode = BackupImportMode.Merge
    ): BackupImportResult =
        backupUseCases.importBackupJson(
            rawJson = rawJson,
            mode = mode
        )

    suspend fun exportBackupJson(): String =
        backupUseCases.exportBackupJson()

    suspend fun addProject(
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ): String {
        val projectId = UUID.randomUUID().toString()
        projectDao.upsertProjects(
            listOf(
                ProjectEntity(
                    id = projectId,
                    name = name.trim(),
                    location = location.trim(),
                    status = "进行中",
                    customerName = "",
                    customerPhone = "",
                    startDate = "",
                    expectedEndDate = expectedEndDate.trim(),
                    managerName = managerName.trim(),
                    contractAmount = contractAmount.trim(),
                    paidAmount = "",
                    paymentStatus = "未收款",
                    materialCost = "",
                    laborCost = ""
                )
            )
        )
        return projectId
    }

    suspend fun updateProject(
        projectId: String,
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ) {
        val project = projectDao.getProject(projectId) ?: return
        projectDao.upsertProjects(
            listOf(
                project.copy(
                    name = name.trim(),
                    location = location.trim(),
                    managerName = managerName.trim(),
                    contractAmount = contractAmount.trim(),
                    expectedEndDate = expectedEndDate.trim()
                )
            )
        )
    }

    suspend fun setProjectArchived(
        projectId: String,
        archived: Boolean
    ) {
        val project = projectDao.getProject(projectId) ?: return
        projectDao.upsertProjects(
            listOf(
                project.copy(status = if (archived) "已归档" else "进行中")
            )
        )
    }

    suspend fun addDailyLog(
        projectId: String,
        date: String,
        content: String,
        workers: String,
        weather: String,
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        dailyLogDao.upsertDailyLogs(
            listOf(
                DailyLogEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    date = date.trim(),
                    weather = weather.trim(),
                    content = content.trim(),
                    workers = workers.trim(),
                    safety = "",
                    materials = "",
                    tomorrowPlan = "",
                    photoFileName = null,
                    photosJson = BackupSnapshotJson.encodeLogPhotos(emptyList()),
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds)
                )
            )
        )
    }

    suspend fun updateDailyLog(
        dailyLogId: String,
        date: String,
        content: String,
        workers: String,
        weather: String,
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        val dailyLog = dailyLogDao.getDailyLog(dailyLogId) ?: return
        dailyLogDao.upsertDailyLogs(
            listOf(
                dailyLog.copy(
                    date = date.trim(),
                    weather = weather.trim(),
                    content = content.trim(),
                    workers = workers.trim(),
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds)
                )
            )
        )
    }

    suspend fun attachDailyLogPhoto(
        dailyLogId: String,
        fileName: String
    ) {
        val normalizedFileName = fileName.trim()
        if (normalizedFileName.isBlank()) {
            return
        }
        val dailyLog = dailyLogDao.getDailyLog(dailyLogId) ?: return
        val photos = dailyLog.toBackupLogPhotos()
        val updatedPhotos = if (photos.any { it.fileName == normalizedFileName }) {
            photos
        } else {
            photos + LogPhoto(
                id = UUID.randomUUID().toString(),
                fileName = normalizedFileName,
                note = "",
                tag = "现场"
            )
        }
        dailyLogDao.upsertDailyLogs(
            listOf(
                dailyLog.copy(
                    photoFileName = dailyLog.photoFileName ?: normalizedFileName,
                    photosJson = BackupSnapshotJson.encodeLogPhotos(updatedPhotos)
                )
            )
        )
    }

    suspend fun deleteDailyLogPhoto(
        dailyLogId: String,
        fileName: String
    ) {
        val dailyLog = dailyLogDao.getDailyLog(dailyLogId) ?: return
        val normalizedFileName = fileName.trim()
        val updatedPhotos = dailyLog.toBackupLogPhotos()
            .filterNot { it.fileName == normalizedFileName }
        dailyLogDao.upsertDailyLogs(
            listOf(
                dailyLog.copy(
                    photoFileName = dailyLog.photoFileName?.takeUnless { it == normalizedFileName },
                    photosJson = BackupSnapshotJson.encodeLogPhotos(updatedPhotos)
                )
            )
        )
    }

    suspend fun deleteDailyLog(dailyLogId: String) {
        dailyLogDao.deleteDailyLog(dailyLogId)
    }

    suspend fun addProgressTask(
        projectId: String,
        title: String,
        startDate: String,
        dueDate: String,
        completion: String,
        note: String
    ) {
        progressTaskDao.upsertProgressTasks(
            listOf(
                ProgressTaskEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    title = title.trim(),
                    startDate = startDate.trim(),
                    dueDate = dueDate.trim(),
                    completion = normalizedCompletion(completion),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun updateProgressTask(
        taskId: String,
        title: String,
        startDate: String,
        dueDate: String,
        completion: String,
        note: String
    ) {
        val task = progressTaskDao.getProgressTask(taskId) ?: return
        progressTaskDao.upsertProgressTasks(
            listOf(
                task.copy(
                    title = title.trim(),
                    startDate = startDate.trim(),
                    dueDate = dueDate.trim(),
                    completion = normalizedCompletion(completion),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun setProgressTaskCompletion(
        taskId: String,
        completion: Double
    ) {
        progressTaskDao.updateProgressTaskCompletion(
            taskId = taskId,
            completion = completion.coerceIn(0.0, 1.0)
        )
    }

    suspend fun deleteProgressTask(taskId: String) {
        progressTaskDao.deleteProgressTask(taskId)
    }

    suspend fun addSiteTodo(
        projectId: String,
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String,
        note: String = "",
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        siteTodoDao.upsertSiteTodos(
            listOf(
                SiteTodoEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    title = title.trim(),
                    owner = owner.trim(),
                    dueDate = dueDate.trim(),
                    priority = priority.trim().ifBlank { "普通" },
                    issueType = issueType.trim().ifBlank { "现场" },
                    isDone = false,
                    completedAt = null,
                    note = note.trim(),
                    rectificationBeforePhotoFileName = null,
                    rectificationAfterPhotoFileName = null,
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds)
                )
            )
        )
    }

    suspend fun addSiteTodoIfAbsent(
        projectId: String,
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String,
        note: String = "",
        linkedConstructionMethodIds: List<String> = emptyList()
    ): Boolean {
        val normalizedTitle = title.trim()
        val normalizedNote = note.trim()
        if (projectId.isBlank() || normalizedTitle.isBlank()) {
            return false
        }
        val exists = siteTodoDao.getSiteTodos().any { todo ->
            todo.projectId == projectId &&
                !todo.isDone &&
                todo.title == normalizedTitle &&
                todo.note == normalizedNote
        }
        if (exists) {
            return false
        }
        addSiteTodo(
            projectId = projectId,
            title = normalizedTitle,
            owner = owner,
            dueDate = dueDate,
            priority = priority,
            issueType = issueType,
            note = normalizedNote,
            linkedConstructionMethodIds = linkedConstructionMethodIds
        )
        return true
    }

    suspend fun updateSiteTodo(
        todoId: String,
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String,
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        val todo = siteTodoDao.getSiteTodo(todoId) ?: return
        siteTodoDao.upsertSiteTodos(
            listOf(
                todo.copy(
                    title = title.trim(),
                    owner = owner.trim(),
                    dueDate = dueDate.trim(),
                    priority = priority.trim().ifBlank { "普通" },
                    issueType = issueType.trim().ifBlank { "现场" },
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds)
                )
            )
        )
    }

    suspend fun attachSiteTodoPhoto(
        todoId: String,
        target: SiteTodoPhotoTarget,
        fileName: String
    ) {
        val normalizedFileName = fileName.trim()
        if (normalizedFileName.isBlank()) {
            return
        }
        val todo = siteTodoDao.getSiteTodo(todoId) ?: return
        siteTodoDao.upsertSiteTodos(
            listOf(
                when (target) {
                    SiteTodoPhotoTarget.Before -> todo.copy(rectificationBeforePhotoFileName = normalizedFileName)
                    SiteTodoPhotoTarget.After -> todo.copy(rectificationAfterPhotoFileName = normalizedFileName)
                }
            )
        )
    }

    suspend fun deleteSiteTodoPhoto(
        todoId: String,
        target: SiteTodoPhotoTarget
    ) {
        val todo = siteTodoDao.getSiteTodo(todoId) ?: return
        siteTodoDao.upsertSiteTodos(
            listOf(
                when (target) {
                    SiteTodoPhotoTarget.Before -> todo.copy(rectificationBeforePhotoFileName = null)
                    SiteTodoPhotoTarget.After -> todo.copy(rectificationAfterPhotoFileName = null)
                }
            )
        )
    }

    suspend fun deleteSiteTodo(todoId: String) {
        siteTodoDao.deleteSiteTodo(todoId)
    }

    suspend fun addFinancialRecord(
        projectId: String,
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) {
        financialRecordDao.upsertFinancialRecords(
            listOf(
                ProjectFinancialRecordEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    date = date.trim(),
                    direction = direction.trim().ifBlank { "支出" },
                    category = category.trim().ifBlank { "材料" },
                    amount = amount.trim(),
                    counterparty = counterparty.trim(),
                    invoiceNumber = "",
                    status = status.trim().ifBlank { "待处理" },
                    dueDate = dueDate.trim(),
                    reminderStatus = "",
                    note = note.trim()
                )
            )
        )
    }

    suspend fun updateFinancialRecord(
        recordId: String,
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) {
        val record = financialRecordDao.getFinancialRecord(recordId) ?: return
        financialRecordDao.upsertFinancialRecords(
            listOf(
                record.copy(
                    date = date.trim(),
                    direction = direction.trim().ifBlank { "支出" },
                    category = category.trim().ifBlank { "材料" },
                    amount = amount.trim(),
                    counterparty = counterparty.trim(),
                    status = status.trim().ifBlank { "待处理" },
                    dueDate = dueDate.trim(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun deleteFinancialRecord(recordId: String) {
        financialRecordDao.deleteFinancialRecord(recordId)
    }

    suspend fun addMaterialItem(
        projectId: String,
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) {
        materialItemDao.upsertMaterialItems(
            listOf(
                MaterialItemEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    name = name.trim(),
                    quantity = quantity.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    unitPrice = unitPrice.trim(),
                    specification = specification.trim(),
                    brand = "",
                    supplier = supplier.trim(),
                    purchaseStatus = purchaseStatus.trim().ifBlank { "待采购" },
                    arrivalDate = arrivalDate.trim()
                )
            )
        )
    }

    suspend fun updateMaterialItem(
        materialId: String,
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) {
        val material = materialItemDao.getMaterialItem(materialId) ?: return
        materialItemDao.upsertMaterialItems(
            listOf(
                material.copy(
                    name = name.trim(),
                    quantity = quantity.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    unitPrice = unitPrice.trim(),
                    specification = specification.trim(),
                    supplier = supplier.trim(),
                    purchaseStatus = purchaseStatus.trim().ifBlank { "待采购" },
                    arrivalDate = arrivalDate.trim()
                )
            )
        )
    }

    suspend fun deleteMaterialItem(materialId: String) {
        materialItemDao.deleteMaterialItem(materialId)
    }

    suspend fun addMaterialPriceEntry(
        name: String,
        specification: String,
        brand: String,
        unit: String,
        referencePrice: String,
        supplier: String,
        category: String,
        note: String
    ) {
        materialPriceEntryDao.upsertMaterialPriceEntries(
            listOf(
                MaterialPriceEntryEntity(
                    id = UUID.randomUUID().toString(),
                    name = name.trim(),
                    specification = specification.trim(),
                    brand = brand.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    referencePrice = referencePrice.trim(),
                    supplier = supplier.trim(),
                    category = category.trim().ifBlank { "其他" },
                    note = note.trim(),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun updateMaterialPriceEntry(
        entryId: String,
        name: String,
        specification: String,
        brand: String,
        unit: String,
        referencePrice: String,
        supplier: String,
        category: String,
        note: String
    ) {
        val entry = materialPriceEntryDao.getMaterialPriceEntry(entryId) ?: return
        materialPriceEntryDao.upsertMaterialPriceEntries(
            listOf(
                entry.copy(
                    name = name.trim(),
                    specification = specification.trim(),
                    brand = brand.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    referencePrice = referencePrice.trim(),
                    supplier = supplier.trim(),
                    category = category.trim().ifBlank { "其他" },
                    note = note.trim(),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun deleteMaterialPriceEntry(entryId: String) {
        materialPriceEntryDao.deleteMaterialPriceEntry(entryId)
    }

    suspend fun importDefaultMaterialLibrary() {
        materialPriceEntryDao.upsertMaterialPriceEntries(DefaultMaterialLibrary.priceEntries)
        supplierProfileDao.upsertSupplierProfiles(DefaultMaterialLibrary.suppliers)
    }

    suspend fun addSupplierProfile(
        name: String,
        category: String,
        contact: String,
        phone: String,
        address: String,
        note: String
    ) {
        supplierProfileDao.upsertSupplierProfiles(
            listOf(
                SupplierProfileEntity(
                    id = UUID.randomUUID().toString(),
                    name = name.trim(),
                    category = category.trim().ifBlank { "综合材料" },
                    contact = contact.trim(),
                    phone = phone.trim(),
                    address = address.trim(),
                    note = note.trim(),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun updateSupplierProfile(
        supplierId: String,
        name: String,
        category: String,
        contact: String,
        phone: String,
        address: String,
        note: String
    ) {
        val supplier = supplierProfileDao.getSupplierProfile(supplierId) ?: return
        supplierProfileDao.upsertSupplierProfiles(
            listOf(
                supplier.copy(
                    name = name.trim(),
                    category = category.trim().ifBlank { "综合材料" },
                    contact = contact.trim(),
                    phone = phone.trim(),
                    address = address.trim(),
                    note = note.trim(),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun deleteSupplierProfile(supplierId: String) {
        supplierProfileDao.deleteSupplierProfile(supplierId)
    }

    suspend fun importDefaultConstructionMethods() {
        constructionMethodDao.upsertConstructionMethods(DefaultConstructionMethodLibrary.methods)
    }

    suspend fun addConstructionMethod(
        title: String,
        trade: String,
        versionName: String,
        publishStatus: String,
        tutorialBody: String,
        procedureSteps: String,
        qualityChecklist: String,
        safetyChecklist: String
    ) {
        constructionMethodDao.upsertConstructionMethods(
            listOf(
                ConstructionMethodEntity(
                    id = UUID.randomUUID().toString(),
                    title = title.trim(),
                    trade = trade.trim().ifBlank { "通用" },
                    versionName = versionName.trim().ifBlank { "V1" },
                    publishStatus = normalizedConstructionPublishStatus(publishStatus),
                    tutorialBody = tutorialBody.trim(),
                    tutorialTextSize = "normal",
                    tutorialAttachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(emptyList()),
                    procedureStepsJson = encodeConstructionMethodLines(procedureSteps),
                    qualityChecklistJson = encodeConstructionMethodLines(qualityChecklist),
                    safetyChecklistJson = encodeConstructionMethodLines(safetyChecklist),
                    attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(emptyList()),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun updateConstructionMethod(
        methodId: String,
        title: String,
        trade: String,
        versionName: String,
        publishStatus: String,
        tutorialBody: String,
        procedureSteps: String,
        qualityChecklist: String,
        safetyChecklist: String
    ) {
        val method = constructionMethodDao.getConstructionMethod(methodId) ?: return
        constructionMethodDao.upsertConstructionMethods(
            listOf(
                method.copy(
                    title = title.trim(),
                    trade = trade.trim().ifBlank { "通用" },
                    versionName = versionName.trim().ifBlank { "V1" },
                    publishStatus = normalizedConstructionPublishStatus(publishStatus),
                    tutorialBody = tutorialBody.trim(),
                    procedureStepsJson = encodeConstructionMethodLines(procedureSteps),
                    qualityChecklistJson = encodeConstructionMethodLines(qualityChecklist),
                    safetyChecklistJson = encodeConstructionMethodLines(safetyChecklist),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun deleteConstructionMethod(methodId: String) {
        constructionMethodDao.deleteConstructionMethod(methodId)
    }

    suspend fun setSiteTodoDone(
        todoId: String,
        isDone: Boolean
    ) {
        siteTodoDao.updateSiteTodoDone(
            todoId = todoId,
            isDone = isDone,
            completedAt = if (isDone) currentDateText() else null
        )
    }

    suspend fun updateFinancialRecordStatus(
        recordId: String,
        status: String
    ) {
        financialRecordDao.updateFinancialRecordStatus(
            recordId = recordId,
            status = status
        )
    }

    suspend fun updateMaterialPurchaseStatus(
        materialId: String,
        purchaseStatus: String
    ) {
        materialItemDao.updateMaterialPurchaseStatus(
            materialId = materialId,
            purchaseStatus = purchaseStatus
        )
    }

    suspend fun addQuickNote(
        title: String,
        content: String,
        projectId: String?
    ) {
        val now = currentTimestampText()
        quickNoteDao.upsertQuickNotes(
            listOf(
                QuickNoteEntity(
                    id = UUID.randomUUID().toString(),
                    title = title.trim(),
                    content = content.trim(),
                    projectId = projectId?.takeIf(String::isNotBlank),
                    createdAt = now,
                    updatedAt = now,
                    attachmentsJson = "[]"
                )
            )
        )
    }

    suspend fun updateQuickNote(
        noteId: String,
        title: String,
        content: String,
        projectId: String?
    ) {
        val note = quickNoteDao.getQuickNote(noteId) ?: return
        quickNoteDao.upsertQuickNotes(
            listOf(
                note.copy(
                    title = title.trim(),
                    content = content.trim(),
                    projectId = projectId?.takeIf(String::isNotBlank),
                    updatedAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun attachQuickNoteFile(
        noteId: String,
        kind: String,
        fileName: String,
        originalName: String,
        durationSeconds: Double? = null
    ) {
        val note = quickNoteDao.getQuickNote(noteId) ?: return
        val now = currentTimestampText()
        val safeFileName = fileName.trim()
        if (safeFileName.isBlank()) {
            return
        }
        val attachments = BackupSnapshotJson.decodeQuickNoteAttachments(note.attachmentsJson)
        if (attachments.any { attachment -> attachment.fileName == safeFileName }) {
            return
        }
        val attachment = QuickNoteAttachment(
            id = UUID.randomUUID().toString(),
            kind = kind.trim().ifBlank { "file" },
            fileName = safeFileName,
            originalName = originalName.trim().ifBlank { safeFileName },
            createdAt = now,
            durationSeconds = durationSeconds
        )
        quickNoteDao.upsertQuickNotes(
            listOf(
                note.copy(
                    updatedAt = now,
                    attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(attachments + attachment)
                )
            )
        )
    }

    suspend fun deleteQuickNoteAttachment(
        noteId: String,
        attachmentId: String
    ) {
        val note = quickNoteDao.getQuickNote(noteId) ?: return
        val attachments = BackupSnapshotJson.decodeQuickNoteAttachments(note.attachmentsJson)
        val remainingAttachments = attachments.filterNot { attachment -> attachment.id == attachmentId }
        if (remainingAttachments.size == attachments.size) {
            return
        }
        quickNoteDao.upsertQuickNotes(
            listOf(
                note.copy(
                    updatedAt = currentTimestampText(),
                    attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(remainingAttachments)
                )
            )
        )
    }

    suspend fun deleteQuickNote(noteId: String) {
        quickNoteDao.deleteQuickNote(noteId)
    }

    suspend fun addProjectContact(
        projectId: String,
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) {
        projectContactDao.upsertProjectContacts(
            listOf(
                ProjectContactEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    relatedProjectIdsJson = "[]",
                    name = name.trim(),
                    role = role.trim().ifBlank { "联系人" },
                    company = company.trim(),
                    phone = phone.trim(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun updateProjectContact(
        contactId: String,
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) {
        val contact = projectContactDao.getProjectContact(contactId) ?: return
        projectContactDao.upsertProjectContacts(
            listOf(
                contact.copy(
                    name = name.trim(),
                    role = role.trim().ifBlank { "联系人" },
                    company = company.trim(),
                    phone = phone.trim(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun deleteProjectContact(contactId: String) {
        projectContactDao.deleteProjectContact(contactId)
    }

    suspend fun addProjectDocument(
        projectId: String,
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        projectDocumentDao.upsertProjectDocuments(
            listOf(
                ProjectDocumentEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    title = title.trim(),
                    category = category.trim().ifBlank { "施工资料" },
                    fileName = fileName.trim(),
                    fileType = fileType.trim().ifBlank { "pdf" },
                    pageCount = normalizedPageCount(pageCount),
                    amount = amount.trim(),
                    linkedFinancialRecordId = null,
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds),
                    createdAt = currentTimestampText(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun updateProjectDocument(
        documentId: String,
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedConstructionMethodIds: List<String> = emptyList()
    ) {
        val document = projectDocumentDao.getProjectDocument(documentId) ?: return
        projectDocumentDao.upsertProjectDocuments(
            listOf(
                document.copy(
                    title = title.trim(),
                    category = category.trim().ifBlank { "施工资料" },
                    fileName = fileName.trim(),
                    fileType = fileType.trim().ifBlank { "pdf" },
                    pageCount = normalizedPageCount(pageCount),
                    amount = amount.trim(),
                    note = note.trim(),
                    linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIds)
                )
            )
        )
    }

    suspend fun attachProjectDocumentFile(
        documentId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) {
        val document = projectDocumentDao.getProjectDocument(documentId) ?: return
        projectDocumentDao.upsertProjectDocuments(
            listOf(
                document.copy(
                    fileName = fileName.trim().ifBlank { document.fileName },
                    fileType = fileType.trim().ifBlank { document.fileType.ifBlank { "file" } },
                    localUri = localUri.trim()
                )
            )
        )
    }

    suspend fun deleteProjectDocument(documentId: String) {
        projectDocumentDao.deleteProjectDocument(documentId)
    }

    suspend fun addProjectDrawing(
        projectId: String,
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) {
        projectDrawingDao.upsertProjectDrawings(
            listOf(
                ProjectDrawingEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    name = name.trim(),
                    fileName = fileName.trim(),
                    fileType = normalizedDrawingFileType(fileType),
                    version = version.trim().ifBlank { "V1" },
                    isCurrentVersion = true,
                    relatedLogDate = relatedLogDate.trim(),
                    issueStatus = issueStatus.trim().ifBlank { "无问题" },
                    issueNote = issueNote.trim(),
                    textEncoding = "auto",
                    textBigFont = "auto",
                    textSchemeSnapshotJson = "{}",
                    cadViewStateJson = "{}",
                    importedAt = currentTimestampText(),
                    note = note.trim(),
                    cadOverlaySnapshotData = "",
                    localUri = ""
                )
            )
        )
    }

    suspend fun updateProjectDrawing(
        drawingId: String,
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) {
        val drawing = projectDrawingDao.getProjectDrawing(drawingId) ?: return
        projectDrawingDao.upsertProjectDrawings(
            listOf(
                drawing.copy(
                    name = name.trim(),
                    fileName = fileName.trim(),
                    fileType = normalizedDrawingFileType(fileType),
                    version = version.trim().ifBlank { "V1" },
                    relatedLogDate = relatedLogDate.trim(),
                    issueStatus = issueStatus.trim().ifBlank { "无问题" },
                    issueNote = issueNote.trim(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun attachProjectDrawingFile(
        drawingId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) {
        val drawing = projectDrawingDao.getProjectDrawing(drawingId) ?: return
        projectDrawingDao.upsertProjectDrawings(
            listOf(
                drawing.copy(
                    fileName = fileName.trim().ifBlank { drawing.fileName },
                    fileType = normalizedDrawingFileType(fileType.trim().ifBlank { drawing.fileType }),
                    localUri = localUri.trim()
                )
            )
        )
    }

    suspend fun deleteProjectDrawing(drawingId: String) {
        projectDrawingDao.deleteProjectDrawing(drawingId)
    }

    suspend fun addQuoteItem(
        projectId: String,
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) {
        quoteItemDao.upsertQuoteItems(
            listOf(
                QuoteItemEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    name = name.trim(),
                    unitPrice = unitPrice.trim(),
                    quantity = quantity.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    notes = notes.trim(),
                    taxRate = "0",
                    discountRate = "0",
                    versionName = versionName.trim().ifBlank { "V1" },
                    status = status.trim().ifBlank { "草稿" },
                    customerConfirmedDate = customerConfirmedDate.trim(),
                    contractAmount = contractAmount.trim()
                )
            )
        )
    }

    suspend fun updateQuoteItem(
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
    ) {
        val quoteItem = quoteItemDao.getQuoteItem(quoteItemId) ?: return
        quoteItemDao.upsertQuoteItems(
            listOf(
                quoteItem.copy(
                    name = name.trim(),
                    unitPrice = unitPrice.trim(),
                    quantity = quantity.trim(),
                    unit = unit.trim().ifBlank { "项" },
                    notes = notes.trim(),
                    versionName = versionName.trim().ifBlank { "V1" },
                    status = status.trim().ifBlank { "草稿" },
                    customerConfirmedDate = customerConfirmedDate.trim(),
                    contractAmount = contractAmount.trim()
                )
            )
        )
    }

    suspend fun deleteQuoteItem(quoteItemId: String) {
        quoteItemDao.deleteQuoteItem(quoteItemId)
    }

    suspend fun addLaborRecord(
        projectId: String,
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) {
        laborRecordDao.upsertLaborRecords(
            listOf(
                LaborRecordEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    date = date.trim(),
                    workers = workers.trim(),
                    hours = hours.trim(),
                    unitRate = unitRate.trim(),
                    workType = workType.trim(),
                    teamName = teamName.trim(),
                    isSettled = isSettled,
                    note = note.trim()
                )
            )
        )
    }

    suspend fun updateLaborRecord(
        recordId: String,
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) {
        val laborRecord = laborRecordDao.getLaborRecord(recordId) ?: return
        laborRecordDao.upsertLaborRecords(
            listOf(
                laborRecord.copy(
                    date = date.trim(),
                    workers = workers.trim(),
                    hours = hours.trim(),
                    unitRate = unitRate.trim(),
                    workType = workType.trim(),
                    teamName = teamName.trim(),
                    isSettled = isSettled,
                    note = note.trim()
                )
            )
        )
    }

    suspend fun setLaborRecordSettled(
        recordId: String,
        isSettled: Boolean
    ) {
        laborRecordDao.updateLaborRecordSettled(
            recordId = recordId,
            isSettled = isSettled
        )
    }

    suspend fun deleteLaborRecord(recordId: String) {
        laborRecordDao.deleteLaborRecord(recordId)
    }

    suspend fun addProjectWarehouseMovement(
        projectId: String,
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) {
        projectWarehouseMovementDao.upsertProjectWarehouseMovements(
            listOf(
                ProjectWarehouseMovementEntity(
                    id = UUID.randomUUID().toString(),
                    projectId = projectId,
                    date = date.trim().ifBlank { currentDateText() },
                    movementType = normalizedWarehouseMovementType(movementType),
                    materialName = materialName.trim(),
                    specification = specification.trim(),
                    unit = unit.trim().ifBlank { "件" },
                    quantity = quantity.trim(),
                    counterparty = counterparty.trim(),
                    handler = handler.trim(),
                    note = note.trim(),
                    linkedDocumentIdsJson = BackupSnapshotJson.encodeStringList(emptyList()),
                    createdAt = currentTimestampText()
                )
            )
        )
    }

    suspend fun updateProjectWarehouseMovement(
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
    ) {
        val movement = projectWarehouseMovementDao.getProjectWarehouseMovement(movementId) ?: return
        projectWarehouseMovementDao.upsertProjectWarehouseMovements(
            listOf(
                movement.copy(
                    date = date.trim().ifBlank { currentDateText() },
                    movementType = normalizedWarehouseMovementType(movementType),
                    materialName = materialName.trim(),
                    specification = specification.trim(),
                    unit = unit.trim().ifBlank { "件" },
                    quantity = quantity.trim(),
                    counterparty = counterparty.trim(),
                    handler = handler.trim(),
                    note = note.trim()
                )
            )
        )
    }

    suspend fun deleteProjectWarehouseMovement(movementId: String) {
        projectWarehouseMovementDao.deleteProjectWarehouseMovement(movementId)
    }

}

data class ProjectDetail(
    val project: ProjectSummary,
    val dailyLogs: List<DailyLogSummary>,
    val siteTodos: List<SiteTodoSummary>,
    val financialRecords: List<ProjectFinancialRecordSummary>,
    val materialItems: List<MaterialItemSummary>,
    val progressTasks: List<ProgressTaskSummary>,
    val contacts: List<ProjectContactSummary>,
    val documents: List<ProjectDocumentSummary>,
    val drawings: List<ProjectDrawingSummary>,
    val quoteItems: List<QuoteItemSummary>,
    val laborRecords: List<LaborRecordSummary>,
    val warehouseMovements: List<ProjectWarehouseMovementSummary>,
    val constructionMethods: List<ConstructionMethodSummary>
)

data class ChecklistTodoSummary(
    val id: String,
    val projectId: String,
    val projectName: String,
    val projectLocation: String,
    val projectStatus: String,
    val title: String,
    val owner: String,
    val dueDate: String,
    val priority: String,
    val issueType: String,
    val isDone: Boolean,
    val note: String,
    val linkedConstructionMethodIds: List<String>,
    val isOverdue: Boolean,
    val isProjectArchived: Boolean
)

data class QuickNoteSummary(
    val id: String,
    val title: String,
    val content: String,
    val projectId: String,
    val projectName: String,
    val projectLocation: String,
    val createdAt: String,
    val updatedAt: String,
    val attachments: List<QuickNoteAttachmentSummary> = emptyList(),
    val attachmentCount: Int = attachments.size,
    val isProjectArchived: Boolean
)

data class QuickNoteAttachmentSummary(
    val id: String,
    val kind: String,
    val fileName: String,
    val originalName: String,
    val createdAt: String,
    val durationSeconds: Double?
)

data class MaterialLibraryOverview(
    val priceEntries: List<MaterialPriceEntrySummary>,
    val suppliers: List<SupplierProfileSummary>,
    val projectMaterialCount: Int,
    val warehouseMaterialNames: Int
) {
    val pricedMaterialCount: Int
        get() = priceEntries.count { entry -> entry.hasReferencePrice }

    val missingPriceCount: Int
        get() = priceEntries.count { entry -> !entry.hasReferencePrice }

    val categories: List<String>
        get() = priceEntries
            .map { entry -> entry.category.trim() }
            .filter(String::isNotBlank)
            .distinct()
}

data class ConstructionMethodLibraryOverview(
    val methods: List<ConstructionMethodSummary>
) {
    val publishedCount: Int
        get() = methods.count { method -> method.statusLabel == "已发布" }

    val draftCount: Int
        get() = methods.count { method -> method.statusLabel == "草稿" }

    val deprecatedCount: Int
        get() = methods.count { method -> method.statusLabel == "已废止" }

    val trades: List<String>
        get() = methods
            .map { method -> method.trade.trim() }
            .filter(String::isNotBlank)
            .distinct()
}

private fun QuickNoteAttachment.toSummary(): QuickNoteAttachmentSummary =
    QuickNoteAttachmentSummary(
        id = id,
        kind = kind,
        fileName = fileName,
        originalName = originalName,
        createdAt = createdAt,
        durationSeconds = durationSeconds
    )

enum class BackupImportMode {
    Merge,
    Replace
}

enum class SiteTodoPhotoTarget {
    Before,
    After
}

private fun currentDateText(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

private fun currentTimestampText(): String =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).format(Date())

private fun isBeforeToday(
    date: String,
    today: String
): Boolean {
    val normalizedDate = date.trim()
    return normalizedDate.isNotBlank() && normalizedDate < today
}

private fun isOnOrBeforeToday(
    date: String,
    today: String
): Boolean {
    val normalizedDate = date.trim()
    return normalizedDate.isNotBlank() && normalizedDate <= today
}

private fun normalizedPageCount(pageCount: String): Int =
    pageCount.trim().toIntOrNull()?.coerceAtLeast(1) ?: 1

private fun normalizedDrawingFileType(fileType: String): String =
    fileType.trim().lowercase(Locale.ROOT).ifBlank { "pdf" }

private fun normalizedCompletion(completion: String): Double {
    val value = completion
        .trim()
        .removeSuffix("%")
        .trim()
        .toDoubleOrNull()
        ?: 0.0
    val ratio = if (value > 1.0) value / 100.0 else value
    return ratio.coerceIn(0.0, 1.0)
}

private fun latestActivityDate(
    dailyLogs: List<DailyLogEntity>,
    siteTodos: List<SiteTodoEntity>,
    financialRecords: List<ProjectFinancialRecordEntity>,
    materialItems: List<MaterialItemEntity>
): String =
    buildList {
        dailyLogs.forEach { log ->
            add(log.date)
        }
        siteTodos.forEach { todo ->
            add(todo.dueDate)
            add(todo.completedAt.orEmpty())
        }
        financialRecords.forEach { record ->
            add(record.date)
            add(record.dueDate)
        }
        materialItems.forEach { material ->
            add(material.arrivalDate)
        }
    }
        .map(String::trim)
        .filter(String::isNotBlank)
        .maxOrNull()
        .orEmpty()
