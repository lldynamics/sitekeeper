package com.chengjinfang.sitekeeper.database.record

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface DailyLogDao {
    @Query("SELECT * FROM daily_logs ORDER BY date DESC")
    fun observeDailyLogs(): Flow<List<DailyLogEntity>>

    @Query("SELECT * FROM daily_logs ORDER BY date DESC")
    suspend fun getDailyLogs(): List<DailyLogEntity>

    @Query("SELECT * FROM daily_logs WHERE id = :dailyLogId LIMIT 1")
    suspend fun getDailyLog(dailyLogId: String): DailyLogEntity?

    @Query("SELECT * FROM daily_logs WHERE projectId = :projectId ORDER BY date DESC")
    fun observeDailyLogsForProject(projectId: String): Flow<List<DailyLogEntity>>

    @Query("SELECT COUNT(*) FROM daily_logs")
    suspend fun dailyLogCount(): Int

    @Query("DELETE FROM daily_logs")
    suspend fun deleteDailyLogs()

    @Query("DELETE FROM daily_logs WHERE id = :dailyLogId")
    suspend fun deleteDailyLog(dailyLogId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertDailyLogs(dailyLogs: List<DailyLogEntity>)
}
