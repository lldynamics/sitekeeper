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

    @Query("SELECT * FROM project_financial_records ORDER BY date DESC")
    suspend fun getFinancialRecords(): List<ProjectFinancialRecordEntity>

    @Query("SELECT * FROM project_financial_records WHERE id = :recordId LIMIT 1")
    suspend fun getFinancialRecord(recordId: String): ProjectFinancialRecordEntity?

    @Query("SELECT * FROM project_financial_records WHERE projectId = :projectId ORDER BY date DESC")
    fun observeFinancialRecordsForProject(projectId: String): Flow<List<ProjectFinancialRecordEntity>>

    @Query("SELECT COUNT(*) FROM project_financial_records")
    suspend fun financialRecordCount(): Int

    @Query("UPDATE project_financial_records SET status = :status WHERE id = :recordId")
    suspend fun updateFinancialRecordStatus(
        recordId: String,
        status: String
    )

    @Query("DELETE FROM project_financial_records")
    suspend fun deleteFinancialRecords()

    @Query("DELETE FROM project_financial_records WHERE id = :recordId")
    suspend fun deleteFinancialRecord(recordId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertFinancialRecords(records: List<ProjectFinancialRecordEntity>)
}
