package com.chengjinfang.sitekeeper.database.labor

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface LaborRecordDao {
    @Query("SELECT * FROM labor_records ORDER BY date DESC, teamName COLLATE NOCASE")
    fun observeLaborRecords(): Flow<List<LaborRecordEntity>>

    @Query("SELECT * FROM labor_records ORDER BY date DESC, teamName COLLATE NOCASE")
    suspend fun getLaborRecords(): List<LaborRecordEntity>

    @Query("SELECT * FROM labor_records WHERE projectId = :projectId ORDER BY date DESC, teamName COLLATE NOCASE")
    fun observeLaborRecordsForProject(projectId: String): Flow<List<LaborRecordEntity>>

    @Query("SELECT * FROM labor_records WHERE id = :recordId LIMIT 1")
    suspend fun getLaborRecord(recordId: String): LaborRecordEntity?

    @Query("SELECT COUNT(*) FROM labor_records")
    suspend fun laborRecordCount(): Int

    @Query("UPDATE labor_records SET isSettled = :isSettled WHERE id = :recordId")
    suspend fun updateLaborRecordSettled(
        recordId: String,
        isSettled: Boolean
    )

    @Query("DELETE FROM labor_records")
    suspend fun deleteLaborRecords()

    @Query("DELETE FROM labor_records WHERE id = :recordId")
    suspend fun deleteLaborRecord(recordId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertLaborRecords(records: List<LaborRecordEntity>)
}
