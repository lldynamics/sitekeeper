package com.chengjinfang.sitekeeper.database.record

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface SiteTodoDao {
    @Query("SELECT * FROM site_todos ORDER BY isDone ASC, dueDate ASC")
    fun observeSiteTodos(): Flow<List<SiteTodoEntity>>

    @Query("SELECT * FROM site_todos WHERE projectId = :projectId ORDER BY isDone ASC, dueDate ASC")
    fun observeSiteTodosForProject(projectId: String): Flow<List<SiteTodoEntity>>

    @Query("SELECT COUNT(*) FROM site_todos")
    suspend fun siteTodoCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSiteTodos(siteTodos: List<SiteTodoEntity>)
}
