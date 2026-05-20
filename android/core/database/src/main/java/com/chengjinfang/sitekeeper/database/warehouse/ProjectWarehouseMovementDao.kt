package com.chengjinfang.sitekeeper.database.warehouse

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectWarehouseMovementDao {
    @Query("SELECT * FROM project_warehouse_movements ORDER BY date DESC, createdAt DESC")
    fun observeProjectWarehouseMovements(): Flow<List<ProjectWarehouseMovementEntity>>

    @Query("SELECT * FROM project_warehouse_movements ORDER BY date DESC, createdAt DESC")
    suspend fun getProjectWarehouseMovements(): List<ProjectWarehouseMovementEntity>

    @Query("SELECT * FROM project_warehouse_movements WHERE projectId = :projectId ORDER BY date DESC, createdAt DESC")
    fun observeProjectWarehouseMovementsForProject(projectId: String): Flow<List<ProjectWarehouseMovementEntity>>

    @Query("SELECT * FROM project_warehouse_movements WHERE id = :movementId LIMIT 1")
    suspend fun getProjectWarehouseMovement(movementId: String): ProjectWarehouseMovementEntity?

    @Query("SELECT COUNT(*) FROM project_warehouse_movements")
    suspend fun projectWarehouseMovementCount(): Int

    @Query("DELETE FROM project_warehouse_movements")
    suspend fun deleteProjectWarehouseMovements()

    @Query("DELETE FROM project_warehouse_movements WHERE id = :movementId")
    suspend fun deleteProjectWarehouseMovement(movementId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProjectWarehouseMovements(movements: List<ProjectWarehouseMovementEntity>)
}
