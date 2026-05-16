package com.chengjinfang.sitekeeper.database.document

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectDocumentDao {
    @Query("SELECT * FROM project_documents ORDER BY createdAt DESC, title ASC")
    fun observeProjectDocuments(): Flow<List<ProjectDocumentEntity>>

    @Query("SELECT * FROM project_documents ORDER BY createdAt DESC, title ASC")
    suspend fun getProjectDocuments(): List<ProjectDocumentEntity>

    @Query("SELECT * FROM project_documents WHERE projectId = :projectId ORDER BY createdAt DESC, title ASC")
    fun observeProjectDocumentsForProject(projectId: String): Flow<List<ProjectDocumentEntity>>

    @Query("SELECT * FROM project_documents WHERE id = :documentId LIMIT 1")
    suspend fun getProjectDocument(documentId: String): ProjectDocumentEntity?

    @Query("SELECT COUNT(*) FROM project_documents")
    suspend fun projectDocumentCount(): Int

    @Query("DELETE FROM project_documents")
    suspend fun deleteProjectDocuments()

    @Query("DELETE FROM project_documents WHERE id = :documentId")
    suspend fun deleteProjectDocument(documentId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProjectDocuments(documents: List<ProjectDocumentEntity>)
}
