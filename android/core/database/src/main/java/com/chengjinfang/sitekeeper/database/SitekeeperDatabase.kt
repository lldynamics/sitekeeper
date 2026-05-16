package com.chengjinfang.sitekeeper.database

import androidx.room.Database
import androidx.room.RoomDatabase
import com.chengjinfang.sitekeeper.database.contact.ProjectContactDao
import com.chengjinfang.sitekeeper.database.contact.ProjectContactEntity
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentDao
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentEntity
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingDao
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingEntity
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordDao
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordEntity
import com.chengjinfang.sitekeeper.database.labor.LaborRecordDao
import com.chengjinfang.sitekeeper.database.labor.LaborRecordEntity
import com.chengjinfang.sitekeeper.database.material.MaterialItemDao
import com.chengjinfang.sitekeeper.database.material.MaterialItemEntity
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryDao
import com.chengjinfang.sitekeeper.database.material.MaterialPriceEntryEntity
import com.chengjinfang.sitekeeper.database.material.SupplierProfileDao
import com.chengjinfang.sitekeeper.database.material.SupplierProfileEntity
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodDao
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodEntity
import com.chengjinfang.sitekeeper.database.note.QuickNoteDao
import com.chengjinfang.sitekeeper.database.note.QuickNoteEntity
import com.chengjinfang.sitekeeper.database.project.ProjectDao
import com.chengjinfang.sitekeeper.database.project.ProjectEntity
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskDao
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskEntity
import com.chengjinfang.sitekeeper.database.quote.QuoteItemDao
import com.chengjinfang.sitekeeper.database.quote.QuoteItemEntity
import com.chengjinfang.sitekeeper.database.record.DailyLogDao
import com.chengjinfang.sitekeeper.database.record.DailyLogEntity
import com.chengjinfang.sitekeeper.database.record.SiteTodoDao
import com.chengjinfang.sitekeeper.database.record.SiteTodoEntity
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementDao
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementEntity

@Database(
    entities = [
        ProjectEntity::class,
        DailyLogEntity::class,
        SiteTodoEntity::class,
        ProjectFinancialRecordEntity::class,
        MaterialItemEntity::class,
        QuickNoteEntity::class,
        ProjectContactEntity::class,
        ProjectDocumentEntity::class,
        ProgressTaskEntity::class,
        ProjectDrawingEntity::class,
        QuoteItemEntity::class,
        LaborRecordEntity::class,
        ProjectWarehouseMovementEntity::class,
        MaterialPriceEntryEntity::class,
        SupplierProfileEntity::class,
        ConstructionMethodEntity::class
    ],
    version = 16,
    exportSchema = true
)
abstract class SitekeeperDatabase : RoomDatabase() {
    abstract fun projectDao(): ProjectDao
    abstract fun dailyLogDao(): DailyLogDao
    abstract fun siteTodoDao(): SiteTodoDao
    abstract fun projectFinancialRecordDao(): ProjectFinancialRecordDao
    abstract fun materialItemDao(): MaterialItemDao
    abstract fun quickNoteDao(): QuickNoteDao
    abstract fun projectContactDao(): ProjectContactDao
    abstract fun projectDocumentDao(): ProjectDocumentDao
    abstract fun progressTaskDao(): ProgressTaskDao
    abstract fun projectDrawingDao(): ProjectDrawingDao
    abstract fun quoteItemDao(): QuoteItemDao
    abstract fun laborRecordDao(): LaborRecordDao
    abstract fun projectWarehouseMovementDao(): ProjectWarehouseMovementDao
    abstract fun materialPriceEntryDao(): MaterialPriceEntryDao
    abstract fun supplierProfileDao(): SupplierProfileDao
    abstract fun constructionMethodDao(): ConstructionMethodDao
}
