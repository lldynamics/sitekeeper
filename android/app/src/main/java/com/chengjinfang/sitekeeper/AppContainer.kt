package com.chengjinfang.sitekeeper

import android.content.Context
import androidx.room.Room
import com.chengjinfang.sitekeeper.database.SitekeeperDatabase
import com.chengjinfang.sitekeeper.database.project.ProjectRepository

class AppContainer(
    private val context: Context
) {
    private val database: SitekeeperDatabase by lazy {
        Room.databaseBuilder(
            context,
            SitekeeperDatabase::class.java,
            "sitekeeper.db"
        )
            .fallbackToDestructiveMigration(true)
            .build()
    }

    val projectRepository: ProjectRepository by lazy {
        ProjectRepository(
            database = database,
            projectDao = database.projectDao(),
            dailyLogDao = database.dailyLogDao(),
            siteTodoDao = database.siteTodoDao(),
            financialRecordDao = database.projectFinancialRecordDao(),
            materialItemDao = database.materialItemDao(),
            quickNoteDao = database.quickNoteDao(),
            projectContactDao = database.projectContactDao(),
            projectDocumentDao = database.projectDocumentDao(),
            progressTaskDao = database.progressTaskDao(),
            projectDrawingDao = database.projectDrawingDao(),
            quoteItemDao = database.quoteItemDao(),
            laborRecordDao = database.laborRecordDao(),
            projectWarehouseMovementDao = database.projectWarehouseMovementDao(),
            materialPriceEntryDao = database.materialPriceEntryDao(),
            supplierProfileDao = database.supplierProfileDao(),
            constructionMethodDao = database.constructionMethodDao()
        )
    }

    suspend fun seedInitialData() {
        val seedJson = context.assets
            .open("backup/p0-projects.json")
            .bufferedReader()
            .use { it.readText() }

        projectRepository.seedFromBackupJsonIfEmpty(seedJson)
        projectRepository.seedDefaultMaterialLibraryIfEmpty()
        projectRepository.seedDefaultConstructionMethodsIfEmpty()
    }
}
