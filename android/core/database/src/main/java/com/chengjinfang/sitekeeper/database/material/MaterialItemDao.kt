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

    @Query("SELECT * FROM material_items ORDER BY name COLLATE NOCASE")
    suspend fun getMaterialItems(): List<MaterialItemEntity>

    @Query("SELECT * FROM material_items WHERE id = :materialId LIMIT 1")
    suspend fun getMaterialItem(materialId: String): MaterialItemEntity?

    @Query("SELECT * FROM material_items WHERE projectId = :projectId ORDER BY name COLLATE NOCASE")
    fun observeMaterialItemsForProject(projectId: String): Flow<List<MaterialItemEntity>>

    @Query("SELECT COUNT(*) FROM material_items")
    suspend fun materialItemCount(): Int

    @Query("UPDATE material_items SET purchaseStatus = :purchaseStatus WHERE id = :materialId")
    suspend fun updateMaterialPurchaseStatus(
        materialId: String,
        purchaseStatus: String
    )

    @Query("DELETE FROM material_items")
    suspend fun deleteMaterialItems()

    @Query("DELETE FROM material_items WHERE id = :materialId")
    suspend fun deleteMaterialItem(materialId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMaterialItems(materials: List<MaterialItemEntity>)
}
