package com.chengjinfang.sitekeeper.database.progress

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProgressTaskDao {
    @Query("SELECT * FROM progress_tasks ORDER BY dueDate ASC, startDate ASC")
    fun observeProgressTasks(): Flow<List<ProgressTaskEntity>>

    @Query("SELECT * FROM progress_tasks ORDER BY dueDate ASC, startDate ASC")
    suspend fun getProgressTasks(): List<ProgressTaskEntity>

    @Query("SELECT * FROM progress_tasks WHERE id = :taskId LIMIT 1")
    suspend fun getProgressTask(taskId: String): ProgressTaskEntity?

    @Query("SELECT * FROM progress_tasks WHERE projectId = :projectId ORDER BY dueDate ASC, startDate ASC")
    fun observeProgressTasksForProject(projectId: String): Flow<List<ProgressTaskEntity>>

    @Query("SELECT COUNT(*) FROM progress_tasks")
    suspend fun progressTaskCount(): Int

    @Query("UPDATE progress_tasks SET completion = :completion WHERE id = :taskId")
    suspend fun updateProgressTaskCompletion(
        taskId: String,
        completion: Double
    )

    @Query("DELETE FROM progress_tasks")
    suspend fun deleteProgressTasks()

    @Query("DELETE FROM progress_tasks WHERE id = :taskId")
    suspend fun deleteProgressTask(taskId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProgressTasks(tasks: List<ProgressTaskEntity>)
}
