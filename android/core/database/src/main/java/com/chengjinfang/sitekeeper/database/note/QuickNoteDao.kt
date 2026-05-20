package com.chengjinfang.sitekeeper.database.note

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface QuickNoteDao {
    @Query("SELECT * FROM quick_notes ORDER BY updatedAt DESC, createdAt DESC")
    fun observeQuickNotes(): Flow<List<QuickNoteEntity>>

    @Query("SELECT * FROM quick_notes ORDER BY updatedAt DESC, createdAt DESC")
    suspend fun getQuickNotes(): List<QuickNoteEntity>

    @Query("SELECT * FROM quick_notes WHERE id = :noteId LIMIT 1")
    suspend fun getQuickNote(noteId: String): QuickNoteEntity?

    @Query("SELECT COUNT(*) FROM quick_notes")
    suspend fun quickNoteCount(): Int

    @Query("DELETE FROM quick_notes")
    suspend fun deleteQuickNotes()

    @Query("DELETE FROM quick_notes WHERE id = :noteId")
    suspend fun deleteQuickNote(noteId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertQuickNotes(notes: List<QuickNoteEntity>)
}
