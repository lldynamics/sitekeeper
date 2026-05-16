package com.chengjinfang.sitekeeper.database.project

import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordDao
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.finance.toEntity
import com.chengjinfang.sitekeeper.database.finance.toSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemDao
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.material.toEntity
import com.chengjinfang.sitekeeper.database.material.toSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogDao
import com.chengjinfang.sitekeeper.database.record.DailyLogEntity
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoDao
import com.chengjinfang.sitekeeper.database.record.SiteTodoEntity
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.record.toEntity
import com.chengjinfang.sitekeeper.database.record.toSummary
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import java.util.UUID

class ProjectRepository(
    private val projectDao: ProjectDao,
    private val dailyLogDao: DailyLogDao,
    private val siteTodoDao: SiteTodoDao,
    private val financialRecordDao: ProjectFinancialRecordDao,
    private val materialItemDao: MaterialItemDao
) {
    val projects: Flow<List<ProjectSummary>> =
        combine(
            projectDao.observeProjects(),
            dailyLogDao.observeDailyLogs(),
            siteTodoDao.observeSiteTodos(),
            financialRecordDao.observeFinancialRecords(),
            materialItemDao.observeMaterialItems()
        ) { projects, dailyLogs, siteTodos, financialRecords, materialItems ->
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

            projects.map { project ->
                project.toSummary(
                    dailyLogCount = dailyLogCounts[project.id] ?: 0,
                    openTodoCount = openTodoCounts[project.id] ?: 0,
                    financialRecordCount = financialRecordCounts[project.id] ?: 0,
                    materialItemCount = materialItemCounts[project.id] ?: 0
                )
            }
        }

    fun observeProjectDetail(projectId: String): Flow<ProjectDetail?> =
        combine(
            projectDao.observeProject(projectId),
            dailyLogDao.observeDailyLogsForProject(projectId),
            siteTodoDao.observeSiteTodosForProject(projectId),
            financialRecordDao.observeFinancialRecordsForProject(projectId),
            materialItemDao.observeMaterialItemsForProject(projectId)
        ) { project, dailyLogs, siteTodos, financialRecords, materialItems ->
            project?.let {
                ProjectDetail(
                    project = it.toSummary(
                        dailyLogCount = dailyLogs.size,
                        openTodoCount = siteTodos.count { todo -> !todo.isDone },
                        financialRecordCount = financialRecords.size,
                        materialItemCount = materialItems.size
                    ),
                    dailyLogs = dailyLogs.map { log -> log.toSummary() },
                    siteTodos = siteTodos.map { todo -> todo.toSummary() },
                    financialRecords = financialRecords.map { record -> record.toSummary() },
                    materialItems = materialItems.map { material -> material.toSummary() }
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
    }

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

    suspend fun addDailyLog(
        projectId: String,
        date: String,
        content: String,
        workers: String,
        weather: String
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
                    tomorrowPlan = ""
                )
            )
        )
    }

    suspend fun addSiteTodo(
        projectId: String,
        title: String,
        owner: String,
        dueDate: String,
        priority: String,
        issueType: String
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
                    note = ""
                )
            )
        )
    }
}

data class ProjectDetail(
    val project: ProjectSummary,
    val dailyLogs: List<DailyLogSummary>,
    val siteTodos: List<SiteTodoSummary>,
    val financialRecords: List<ProjectFinancialRecordSummary>,
    val materialItems: List<MaterialItemSummary>
)
