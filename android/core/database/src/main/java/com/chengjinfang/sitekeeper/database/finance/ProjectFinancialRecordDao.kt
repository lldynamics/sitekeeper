package com.chengjinfang.sitekeeper.database.finance

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectFinancialRecordDao {
    @Query("SELECT * FROM project_financial_records ORDER BY date DESC")
    fun observeFinancialRecords(): Flow<List<ProjectFinancialRecordEntity>>

    @Query("SELECT * FROM project_financial_records WHERE projectId = :projectId ORDER BY date DESC")
    fun observeFinancialRecordsForProject(projectId: String): Flow<List<ProjectFinancialRecordEntity>>

    @Query("SELECT COUNT(*) FROM project_financial_records")
    suspend fun financialRecordCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertFinancialRecords(records: List<ProjectFinancialRecordEntity>)
}
