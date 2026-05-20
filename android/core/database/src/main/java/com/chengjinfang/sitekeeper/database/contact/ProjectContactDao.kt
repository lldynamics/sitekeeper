package com.chengjinfang.sitekeeper.database.contact

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ProjectContactDao {
    @Query("SELECT * FROM project_contacts ORDER BY name ASC")
    fun observeProjectContacts(): Flow<List<ProjectContactEntity>>

    @Query("SELECT * FROM project_contacts ORDER BY name ASC")
    suspend fun getProjectContacts(): List<ProjectContactEntity>

    @Query("SELECT * FROM project_contacts WHERE projectId = :projectId ORDER BY role ASC, name ASC")
    fun observeProjectContactsForProject(projectId: String): Flow<List<ProjectContactEntity>>

    @Query("SELECT * FROM project_contacts WHERE id = :contactId LIMIT 1")
    suspend fun getProjectContact(contactId: String): ProjectContactEntity?

    @Query("SELECT COUNT(*) FROM project_contacts")
    suspend fun projectContactCount(): Int

    @Query("DELETE FROM project_contacts")
    suspend fun deleteProjectContacts()

    @Query("DELETE FROM project_contacts WHERE id = :contactId")
    suspend fun deleteProjectContact(contactId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProjectContacts(contacts: List<ProjectContactEntity>)
}
