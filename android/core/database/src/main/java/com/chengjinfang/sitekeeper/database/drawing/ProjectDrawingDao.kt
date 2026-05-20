package com.chengjinfang.sitekeeper.database.drawing

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectDrawingDao {
    @Query("SELECT * FROM project_drawings ORDER BY importedAt DESC, name ASC")
    fun observeProjectDrawings(): Flow<List<ProjectDrawingEntity>>

    @Query("SELECT * FROM project_drawings ORDER BY importedAt DESC, name ASC")
    suspend fun getProjectDrawings(): List<ProjectDrawingEntity>

    @Query("SELECT * FROM project_drawings WHERE projectId = :projectId ORDER BY importedAt DESC, name ASC")
    fun observeProjectDrawingsForProject(projectId: String): Flow<List<ProjectDrawingEntity>>

    @Query("SELECT * FROM project_drawings WHERE id = :drawingId LIMIT 1")
    suspend fun getProjectDrawing(drawingId: String): ProjectDrawingEntity?

    @Query("SELECT COUNT(*) FROM project_drawings")
    suspend fun projectDrawingCount(): Int

    @Query("DELETE FROM project_drawings")
    suspend fun deleteProjectDrawings()

    @Query("DELETE FROM project_drawings WHERE id = :drawingId")
    suspend fun deleteProjectDrawing(drawingId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProjectDrawings(drawings: List<ProjectDrawingEntity>)
}
