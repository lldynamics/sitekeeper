package com.chengjinfang.sitekeeper.database.quote

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface QuoteItemDao {
    @Query("SELECT * FROM quote_items ORDER BY versionName DESC, name COLLATE NOCASE")
    fun observeQuoteItems(): Flow<List<QuoteItemEntity>>

    @Query("SELECT * FROM quote_items ORDER BY versionName DESC, name COLLATE NOCASE")
    suspend fun getQuoteItems(): List<QuoteItemEntity>

    @Query("SELECT * FROM quote_items WHERE projectId = :projectId ORDER BY versionName DESC, name COLLATE NOCASE")
    fun observeQuoteItemsForProject(projectId: String): Flow<List<QuoteItemEntity>>

    @Query("SELECT * FROM quote_items WHERE id = :quoteItemId LIMIT 1")
    suspend fun getQuoteItem(quoteItemId: String): QuoteItemEntity?

    @Query("SELECT COUNT(*) FROM quote_items")
    suspend fun quoteItemCount(): Int

    @Query("DELETE FROM quote_items")
    suspend fun deleteQuoteItems()

    @Query("DELETE FROM quote_items WHERE id = :quoteItemId")
    suspend fun deleteQuoteItem(quoteItemId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertQuoteItems(items: List<QuoteItemEntity>)
}
