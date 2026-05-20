package com.chengjinfang.sitekeeper.database.project

import androidx.room.withTransaction
import com.chengjinfang.sitekeeper.database.SitekeeperDatabase
import com.chengjinfang.sitekeeper.database.contact.ProjectContactDao
import com.chengjinfang.sitekeeper.database.contact.ProjectContactEntity
import com.chengjinfang.sitekeeper.database.contact.toBackupProjectContact
import com.chengjinfang.sitekeeper.database.contact.toEntity
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentDao
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentEntity
import com.chengjinfang.sitekeeper.database.document.toBackupProjectDocument
import com.chengjinfang.sitekeeper.database.document.toEntity
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingDao
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingEntity
import com.chengjinfang.sitekeeper.database.drawing.toBackupProjectDrawing
import com.chengjinfang.sitekeeper.database.drawing.toEntity
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordDao
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordEntity
import com.chengjinfang.sitekeeper.database.finance.toEntity
import com.chengjinfang.sitekeeper.database.labor.LaborRecordDao
import com.chengjinfang.sitekeeper.database.labor.LaborRecordEntity
import com.chengjinfang.sitekeeper.database.labor.toBackupLaborRecord
import com.chengjinfang.sitekeeper.database.labor.toEntity
import com.chengjinfang.sitekeeper.database.material.MaterialItemDao
import com.chengjinfang.sitekeeper.database.material.MaterialItemEntity
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryDao
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryEntity
import com.chengjinfang.sitekeeper.database.material.SupplierProfileDao
import com.chengjinfang.sitekeeper.database.material.SupplierProfileEntity
import com.chengjinfang.sitekeeper.database.material.toBackupMaterialPriceEntry
import com.chengjinfang.sitekeeper.database.material.toBackupSupplierProfile
import com.chengjinfang.sitekeeper.database.material.toEntity
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodDao
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodEntity
import com.chengjinfang.sitekeeper.database.method.toBackupConstructionMethod
import com.chengjinfang.sitekeeper.database.method.toEntity
import com.chengjinfang.sitekeeper.database.note.QuickNoteDao
import com.chengjinfang.sitekeeper.database.note.QuickNoteEntity
import com.chengjinfang.sitekeeper.database.note.toBackupQuickNote
import com.chengjinfang.sitekeeper.database.note.toEntity
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskDao
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskEntity
import com.chengjinfang.sitekeeper.database.progress.toEntity
import com.chengjinfang.sitekeeper.database.quote.QuoteItemDao
import com.chengjinfang.sitekeeper.database.quote.QuoteItemEntity
import com.chengjinfang.sitekeeper.database.quote.toBackupQuoteItem
import com.chengjinfang.sitekeeper.database.quote.toEntity
import com.chengjinfang.sitekeeper.database.record.DailyLogDao
import com.chengjinfang.sitekeeper.database.record.DailyLogEntity
import com.chengjinfang.sitekeeper.database.record.SiteTodoDao
import com.chengjinfang.sitekeeper.database.record.SiteTodoEntity
import com.chengjinfang.sitekeeper.database.record.toBackupLogPhotos
import com.chengjinfang.sitekeeper.database.record.toEntity
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementDao
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementEntity
import com.chengjinfang.sitekeeper.database.warehouse.toBackupProjectWarehouseMovement
import com.chengjinfang.sitekeeper.database.warehouse.toEntity
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshot
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.DailyLog
import com.chengjinfang.sitekeeper.model.backup.MaterialItem
import com.chengjinfang.sitekeeper.model.backup.Project
import com.chengjinfang.sitekeeper.model.backup.ProjectFinancialRecord
import com.chengjinfang.sitekeeper.model.backup.ProgressTask
import com.chengjinfang.sitekeeper.model.backup.SiteTodo
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal class ProjectBackupUseCases(
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
    fun previewBackupJson(rawJson: String): BackupImportPreview =
        parseBackupJson(rawJson).preview

    suspend fun importBackupJson(
        rawJson: String,
        mode: BackupImportMode = BackupImportMode.Merge
    ): BackupImportResult {
        val prepared = parseBackupJson(rawJson)
        database.withTransaction {
            if (mode == BackupImportMode.Replace) {
                clearSupportedBackupData()
            }
            upsertSupportedBackupData(prepared)
        }

        return prepared.preview.toResult(mode)
    }

    suspend fun exportBackupJson(): String {
        val snapshot = BackupSnapshot(
            schemaVersion = 1,
            exportedAt = backupCurrentTimestampText(),
            exportPlatform = "android",
            projects = projectDao.getProjects().map { it.toBackupProject() },
            dailyLogs = dailyLogDao.getDailyLogs().map { it.toBackupDailyLog() },
            siteTodos = siteTodoDao.getSiteTodos().map { it.toBackupSiteTodo() },
            projectFinancialRecords = financialRecordDao.getFinancialRecords()
                .map { it.toBackupFinancialRecord() },
            materialItems = materialItemDao.getMaterialItems().map { it.toBackupMaterialItem() },
            quickNotes = quickNoteDao.getQuickNotes().map { it.toBackupQuickNote() },
            projectContacts = projectContactDao.getProjectContacts().map { it.toBackupProjectContact() },
            projectDocuments = projectDocumentDao.getProjectDocuments().map { it.toBackupProjectDocument() },
            progressTasks = progressTaskDao.getProgressTasks().map { it.toBackupProgressTask() },
            projectDrawings = projectDrawingDao.getProjectDrawings().map { it.toBackupProjectDrawing() },
            quoteItems = quoteItemDao.getQuoteItems().map { it.toBackupQuoteItem() },
            laborRecords = laborRecordDao.getLaborRecords().map { it.toBackupLaborRecord() },
            projectWarehouseMovements = projectWarehouseMovementDao.getProjectWarehouseMovements()
                .map { it.toBackupProjectWarehouseMovement() },
            materialPriceEntries = materialPriceEntryDao.getMaterialPriceEntries()
                .map { it.toBackupMaterialPriceEntry() },
            supplierProfiles = supplierProfileDao.getSupplierProfiles()
                .map { it.toBackupSupplierProfile() },
            constructionMethods = constructionMethodDao.getConstructionMethods()
                .map { it.toBackupConstructionMethod() }
        )
        return BackupSnapshotJson.encode(snapshot)
    }

    private suspend fun clearSupportedBackupData() {
        constructionMethodDao.deleteConstructionMethods()
        supplierProfileDao.deleteSupplierProfiles()
        materialPriceEntryDao.deleteMaterialPriceEntries()
        projectWarehouseMovementDao.deleteProjectWarehouseMovements()
        laborRecordDao.deleteLaborRecords()
        quoteItemDao.deleteQuoteItems()
        projectDrawingDao.deleteProjectDrawings()
        progressTaskDao.deleteProgressTasks()
        projectDocumentDao.deleteProjectDocuments()
        projectContactDao.deleteProjectContacts()
        quickNoteDao.deleteQuickNotes()
        materialItemDao.deleteMaterialItems()
        financialRecordDao.deleteFinancialRecords()
        siteTodoDao.deleteSiteTodos()
        dailyLogDao.deleteDailyLogs()
        projectDao.deleteProjects()
    }

    private suspend fun upsertSupportedBackupData(prepared: PreparedBackupImport) {
        if (prepared.projects.isNotEmpty()) {
            projectDao.upsertProjects(prepared.projects)
        }
        if (prepared.dailyLogs.isNotEmpty()) {
            dailyLogDao.upsertDailyLogs(prepared.dailyLogs)
        }
        if (prepared.siteTodos.isNotEmpty()) {
            siteTodoDao.upsertSiteTodos(prepared.siteTodos)
        }
        if (prepared.financialRecords.isNotEmpty()) {
            financialRecordDao.upsertFinancialRecords(prepared.financialRecords)
        }
        if (prepared.materials.isNotEmpty()) {
            materialItemDao.upsertMaterialItems(prepared.materials)
        }
        if (prepared.quickNotes.isNotEmpty()) {
            quickNoteDao.upsertQuickNotes(prepared.quickNotes)
        }
        if (prepared.projectContacts.isNotEmpty()) {
            projectContactDao.upsertProjectContacts(prepared.projectContacts)
        }
        if (prepared.projectDocuments.isNotEmpty()) {
            projectDocumentDao.upsertProjectDocuments(prepared.projectDocuments)
        }
        if (prepared.progressTasks.isNotEmpty()) {
            progressTaskDao.upsertProgressTasks(prepared.progressTasks)
        }
        if (prepared.projectDrawings.isNotEmpty()) {
            projectDrawingDao.upsertProjectDrawings(prepared.projectDrawings)
        }
        if (prepared.quoteItems.isNotEmpty()) {
            quoteItemDao.upsertQuoteItems(prepared.quoteItems)
        }
        if (prepared.laborRecords.isNotEmpty()) {
            laborRecordDao.upsertLaborRecords(prepared.laborRecords)
        }
        if (prepared.projectWarehouseMovements.isNotEmpty()) {
            projectWarehouseMovementDao.upsertProjectWarehouseMovements(prepared.projectWarehouseMovements)
        }
        if (prepared.materialPriceEntries.isNotEmpty()) {
            materialPriceEntryDao.upsertMaterialPriceEntries(prepared.materialPriceEntries)
        }
        if (prepared.supplierProfiles.isNotEmpty()) {
            supplierProfileDao.upsertSupplierProfiles(prepared.supplierProfiles)
        }
        if (prepared.constructionMethods.isNotEmpty()) {
            constructionMethodDao.upsertConstructionMethods(prepared.constructionMethods)
        }
    }
}

data class BackupImportPreview(
    val projectCount: Int,
    val dailyLogCount: Int,
    val siteTodoCount: Int,
    val financialRecordCount: Int,
    val materialItemCount: Int,
    val quickNoteCount: Int = 0,
    val projectContactCount: Int = 0,
    val projectDocumentCount: Int = 0,
    val progressTaskCount: Int = 0,
    val projectDrawingCount: Int = 0,
    val quoteItemCount: Int = 0,
    val laborRecordCount: Int = 0,
    val projectWarehouseMovementCount: Int = 0,
    val materialPriceEntryCount: Int = 0,
    val supplierProfileCount: Int = 0,
    val constructionMethodCount: Int = 0
) {
    val totalCount: Int
        get() = projectCount +
            dailyLogCount +
            siteTodoCount +
            financialRecordCount +
            materialItemCount +
            quickNoteCount +
            projectContactCount +
            projectDocumentCount +
            progressTaskCount +
            projectDrawingCount +
            quoteItemCount +
            laborRecordCount +
            projectWarehouseMovementCount +
            materialPriceEntryCount +
            supplierProfileCount +
            constructionMethodCount

    fun toResult(mode: BackupImportMode): BackupImportResult =
        BackupImportResult(
            projectCount = projectCount,
            dailyLogCount = dailyLogCount,
            siteTodoCount = siteTodoCount,
            financialRecordCount = financialRecordCount,
            materialItemCount = materialItemCount,
            quickNoteCount = quickNoteCount,
            projectContactCount = projectContactCount,
            projectDocumentCount = projectDocumentCount,
            progressTaskCount = progressTaskCount,
            projectDrawingCount = projectDrawingCount,
            quoteItemCount = quoteItemCount,
            laborRecordCount = laborRecordCount,
            projectWarehouseMovementCount = projectWarehouseMovementCount,
            materialPriceEntryCount = materialPriceEntryCount,
            supplierProfileCount = supplierProfileCount,
            constructionMethodCount = constructionMethodCount,
            mode = mode
        )
}

data class BackupImportResult(
    val projectCount: Int,
    val dailyLogCount: Int,
    val siteTodoCount: Int,
    val financialRecordCount: Int,
    val materialItemCount: Int,
    val quickNoteCount: Int = 0,
    val projectContactCount: Int = 0,
    val projectDocumentCount: Int = 0,
    val progressTaskCount: Int = 0,
    val projectDrawingCount: Int = 0,
    val quoteItemCount: Int = 0,
    val laborRecordCount: Int = 0,
    val projectWarehouseMovementCount: Int = 0,
    val materialPriceEntryCount: Int = 0,
    val supplierProfileCount: Int = 0,
    val constructionMethodCount: Int = 0,
    val mode: BackupImportMode
) {
    val totalCount: Int
        get() = projectCount +
            dailyLogCount +
            siteTodoCount +
            financialRecordCount +
            materialItemCount +
            quickNoteCount +
            projectContactCount +
            projectDocumentCount +
            progressTaskCount +
            projectDrawingCount +
            quoteItemCount +
            laborRecordCount +
            projectWarehouseMovementCount +
            materialPriceEntryCount +
            supplierProfileCount +
            constructionMethodCount
}

private data class PreparedBackupImport(
    val projects: List<ProjectEntity>,
    val dailyLogs: List<DailyLogEntity>,
    val siteTodos: List<SiteTodoEntity>,
    val financialRecords: List<ProjectFinancialRecordEntity>,
    val materials: List<MaterialItemEntity>,
    val quickNotes: List<QuickNoteEntity>,
    val projectContacts: List<ProjectContactEntity>,
    val projectDocuments: List<ProjectDocumentEntity>,
    val progressTasks: List<ProgressTaskEntity>,
    val projectDrawings: List<ProjectDrawingEntity>,
    val quoteItems: List<QuoteItemEntity>,
    val laborRecords: List<LaborRecordEntity>,
    val projectWarehouseMovements: List<ProjectWarehouseMovementEntity>,
    val materialPriceEntries: List<MaterialPriceEntryEntity>,
    val supplierProfiles: List<SupplierProfileEntity>,
    val constructionMethods: List<ConstructionMethodEntity>,
    val preview: BackupImportPreview
)

private fun parseBackupJson(rawJson: String): PreparedBackupImport {
    val snapshot = BackupSnapshotJson.decode(rawJson)
    val projects = snapshot.projects.map { it.toEntity() }
    val dailyLogs = snapshot.dailyLogs.map { it.toEntity() }
    val siteTodos = snapshot.siteTodos.map { it.toEntity() }
    val financialRecords = snapshot.projectFinancialRecords.map { it.toEntity() }
    val materials = snapshot.materialItems.map { it.toEntity() }
    val quickNotes = snapshot.quickNotes.map { it.toEntity() }
    val projectContacts = snapshot.projectContacts.map { it.toEntity() }
    val projectDocuments = snapshot.projectDocuments.map { it.toEntity() }
    val progressTasks = snapshot.progressTasks.map { it.toEntity() }
    val projectDrawings = snapshot.projectDrawings.map { it.toEntity() }
    val quoteItems = snapshot.quoteItems.map { it.toEntity() }
    val laborRecords = snapshot.laborRecords.map { it.toEntity() }
    val projectWarehouseMovements = snapshot.projectWarehouseMovements.map { it.toEntity() }
    val updatedAt = backupCurrentTimestampText()
    val materialPriceEntries = snapshot.materialPriceEntries.mapIndexed { index, entry ->
        entry.toEntity(
            fallbackId = "imported-material-price-${index + 1}",
            fallbackUpdatedAt = updatedAt
        )
    }
    val supplierProfiles = snapshot.supplierProfiles.mapIndexed { index, supplier ->
        supplier.toEntity(
            fallbackId = "imported-supplier-${index + 1}",
            fallbackUpdatedAt = updatedAt
        )
    }
    val constructionMethods = snapshot.constructionMethods.mapIndexed { index, method ->
        method.toEntity(
            fallbackId = "imported-construction-method-${index + 1}",
            fallbackUpdatedAt = updatedAt
        )
    }

    return PreparedBackupImport(
        projects = projects,
        dailyLogs = dailyLogs,
        siteTodos = siteTodos,
        financialRecords = financialRecords,
        materials = materials,
        quickNotes = quickNotes,
        projectContacts = projectContacts,
        projectDocuments = projectDocuments,
        progressTasks = progressTasks,
        projectDrawings = projectDrawings,
        quoteItems = quoteItems,
        laborRecords = laborRecords,
        projectWarehouseMovements = projectWarehouseMovements,
        materialPriceEntries = materialPriceEntries,
        supplierProfiles = supplierProfiles,
        constructionMethods = constructionMethods,
        preview = BackupImportPreview(
            projectCount = projects.size,
            dailyLogCount = dailyLogs.size,
            siteTodoCount = siteTodos.size,
            financialRecordCount = financialRecords.size,
            materialItemCount = materials.size,
            quickNoteCount = quickNotes.size,
            projectContactCount = projectContacts.size,
            projectDocumentCount = projectDocuments.size,
            progressTaskCount = progressTasks.size,
            projectDrawingCount = projectDrawings.size,
            quoteItemCount = quoteItems.size,
            laborRecordCount = laborRecords.size,
            projectWarehouseMovementCount = projectWarehouseMovements.size,
            materialPriceEntryCount = materialPriceEntries.size,
            supplierProfileCount = supplierProfiles.size,
            constructionMethodCount = constructionMethods.size
        )
    )
}

private fun backupCurrentTimestampText(): String =
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssZ", Locale.US).format(Date())

private fun ProjectEntity.toBackupProject(): Project =
    Project(
        id = id,
        name = name,
        location = location,
        status = status,
        customerName = customerName,
        customerPhone = customerPhone,
        startDate = startDate,
        expectedEndDate = expectedEndDate,
        managerName = managerName,
        contractAmount = contractAmount,
        paidAmount = paidAmount,
        paymentStatus = paymentStatus,
        materialCost = materialCost,
        laborCost = laborCost
    )

private fun DailyLogEntity.toBackupDailyLog(): DailyLog =
    DailyLog(
        id = id,
        projectId = projectId,
        date = date,
        weather = weather,
        content = content,
        workers = workers,
        safety = safety,
        materials = materials,
        tomorrowPlan = tomorrowPlan,
        photoFileName = photoFileName,
        photos = toBackupLogPhotos(),
        linkedConstructionMethodIDs = BackupSnapshotJson.decodeStringList(linkedConstructionMethodIdsJson)
    )

private fun SiteTodoEntity.toBackupSiteTodo(): SiteTodo =
    SiteTodo(
        id = id,
        projectId = projectId,
        title = title,
        owner = owner,
        dueDate = dueDate,
        priority = priority,
        issueType = issueType,
        rectificationBeforePhotoFileName = rectificationBeforePhotoFileName,
        rectificationAfterPhotoFileName = rectificationAfterPhotoFileName,
        isDone = isDone,
        completedAt = completedAt,
        note = note,
        linkedConstructionMethodIDs = BackupSnapshotJson.decodeStringList(linkedConstructionMethodIdsJson)
    )

private fun ProjectFinancialRecordEntity.toBackupFinancialRecord(): ProjectFinancialRecord =
    ProjectFinancialRecord(
        id = id,
        projectId = projectId,
        date = date,
        direction = direction,
        category = category,
        amount = amount,
        counterparty = counterparty,
        invoiceNumber = invoiceNumber,
        status = status,
        dueDate = dueDate,
        reminderStatus = reminderStatus,
        note = note
    )

private fun MaterialItemEntity.toBackupMaterialItem(): MaterialItem =
    MaterialItem(
        id = id,
        projectId = projectId,
        name = name,
        quantity = quantity,
        unit = unit,
        unitPrice = unitPrice,
        specification = specification,
        brand = brand,
        supplier = supplier,
        purchaseStatus = purchaseStatus,
        arrivalDate = arrivalDate
    )

private fun ProgressTaskEntity.toBackupProgressTask(): ProgressTask =
    ProgressTask(
        id = id,
        projectId = projectId,
        title = title,
        startDate = startDate,
        dueDate = dueDate,
        completion = completion,
        note = note
    )
