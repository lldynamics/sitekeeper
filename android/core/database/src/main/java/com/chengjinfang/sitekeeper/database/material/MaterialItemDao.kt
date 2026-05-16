package com.chengjinfang.sitekeeper.database.material

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface MaterialItemDao {
    @Query("SELECT * FROM material_items ORDER BY name COLLATE NOCASE")
    fun observeMaterialItems(): Flow<List<MaterialItemEntity>>

    @Query("SELECT * FROM material_items WHERE projectId = :projectId ORDER BY name COLLATE NOCASE")
    fun observeMaterialItemsForProject(projectId: String): Flow<List<MaterialItemEntity>>

    @Query("SELECT COUNT(*) FROM material_items")
    suspend fun materialItemCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMaterialItems(materials: List<MaterialItemEntity>)
}
