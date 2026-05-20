package com.chengjinfang.sitekeeper.database.method

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ConstructionMethodDao {
    @Query("SELECT * FROM construction_methods ORDER BY updatedAt DESC, title COLLATE NOCASE")
    fun observeConstructionMethods(): Flow<List<ConstructionMethodEntity>>

    @Query("SELECT * FROM construction_methods ORDER BY updatedAt DESC, title COLLATE NOCASE")
    suspend fun getConstructionMethods(): List<ConstructionMethodEntity>

    @Query("SELECT * FROM construction_methods WHERE id = :methodId LIMIT 1")
    suspend fun getConstructionMethod(methodId: String): ConstructionMethodEntity?

    @Query("SELECT COUNT(*) FROM construction_methods")
    suspend fun constructionMethodCount(): Int

    @Query("DELETE FROM construction_methods")
    suspend fun deleteConstructionMethods()

    @Query("DELETE FROM construction_methods WHERE id = :methodId")
    suspend fun deleteConstructionMethod(methodId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertConstructionMethods(methods: List<ConstructionMethodEntity>)
}
