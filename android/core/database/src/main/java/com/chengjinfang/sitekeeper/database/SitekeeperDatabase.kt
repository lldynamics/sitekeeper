package com.chengjinfang.sitekeeper.database

import androidx.room.Database
import androidx.room.RoomDatabase
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordDao
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordEntity
import com.chengjinfang.sitekeeper.database.material.MaterialItemDao
import com.chengjinfang.sitekeeper.database.material.MaterialItemEntity
import com.chengjinfang.sitekeeper.database.project.ProjectDao
import com.chengjinfang.sitekeeper.database.project.ProjectEntity
import com.chengjinfang.sitekeeper.database.record.DailyLogDao
import com.chengjinfang.sitekeeper.database.record.DailyLogEntity
import com.chengjinfang.sitekeeper.database.record.SiteTodoDao
import com.chengjinfang.sitekeeper.database.record.SiteTodoEntity

@Database(
    entities = [
        ProjectEntity::class,
        DailyLogEntity::class,
        SiteTodoEntity::class,
        ProjectFinancialRecordEntity::class,
        MaterialItemEntity::class
    ],
    version = 3,
    exportSchema = true
)
abstract class SitekeeperDatabase : RoomDatabase() {
    abstract fun projectDao(): ProjectDao
    abstract fun dailyLogDao(): DailyLogDao
    abstract fun siteTodoDao(): SiteTodoDao
    abstract fun projectFinancialRecordDao(): ProjectFinancialRecordDao
    abstract fun materialItemDao(): MaterialItemDao
}
