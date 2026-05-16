package com.chengjinfang.sitekeeper.database.project

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectDao {
    @Query("SELECT * FROM projects ORDER BY name COLLATE NOCASE")
    fun observeProjects(): Flow<List<ProjectEntity>>

    @Query("SELECT * FROM projects WHERE id = :projectId LIMIT 1")
    fun observeProject(projectId: String): Flow<ProjectEntity?>

    @Query("SELECT COUNT(*) FROM projects")
    suspend fun projectCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProjects(projects: List<ProjectEntity>)
}
