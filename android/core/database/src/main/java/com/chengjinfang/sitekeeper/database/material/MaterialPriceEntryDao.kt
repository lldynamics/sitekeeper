package com.chengjinfang.sitekeeper.database.material

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface MaterialPriceEntryDao {
    @Query("SELECT * FROM material_price_entries ORDER BY updatedAt DESC, name COLLATE NOCASE")
    fun observeMaterialPriceEntries(): Flow<List<MaterialPriceEntryEntity>>

    @Query("SELECT * FROM material_price_entries ORDER BY updatedAt DESC, name COLLATE NOCASE")
    suspend fun getMaterialPriceEntries(): List<MaterialPriceEntryEntity>

    @Query("SELECT * FROM material_price_entries WHERE id = :entryId LIMIT 1")
    suspend fun getMaterialPriceEntry(entryId: String): MaterialPriceEntryEntity?

    @Query("SELECT COUNT(*) FROM material_price_entries")
    suspend fun materialPriceEntryCount(): Int

    @Query("DELETE FROM material_price_entries")
    suspend fun deleteMaterialPriceEntries()

    @Query("DELETE FROM material_price_entries WHERE id = :entryId")
    suspend fun deleteMaterialPriceEntry(entryId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMaterialPriceEntries(entries: List<MaterialPriceEntryEntity>)
}
