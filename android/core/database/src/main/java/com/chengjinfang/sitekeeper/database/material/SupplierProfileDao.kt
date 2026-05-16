package com.chengjinfang.sitekeeper.database.material

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface SupplierProfileDao {
    @Query("SELECT * FROM supplier_profiles ORDER BY updatedAt DESC, name COLLATE NOCASE")
    fun observeSupplierProfiles(): Flow<List<SupplierProfileEntity>>

    @Query("SELECT * FROM supplier_profiles ORDER BY updatedAt DESC, name COLLATE NOCASE")
    suspend fun getSupplierProfiles(): List<SupplierProfileEntity>

    @Query("SELECT * FROM supplier_profiles WHERE id = :supplierId LIMIT 1")
    suspend fun getSupplierProfile(supplierId: String): SupplierProfileEntity?

    @Query("SELECT COUNT(*) FROM supplier_profiles")
    suspend fun supplierProfileCount(): Int

    @Query("DELETE FROM supplier_profiles")
    suspend fun deleteSupplierProfiles()

    @Query("DELETE FROM supplier_profiles WHERE id = :supplierId")
    suspend fun deleteSupplierProfile(supplierId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSupplierProfiles(suppliers: List<SupplierProfileEntity>)
}
