package com.chengjinfang.sitekeeper.database.contact

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ProjectContact

@Entity(
    tableName = "project_contacts",
    indices = [Index("projectId")]
)
data class ProjectContactEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val relatedProjectIdsJson: String,
    val name: String,
    val role: String,
    val company: String,
    val phone: String,
    val note: String
)

data class ProjectContactSummary(
    val id: String,
    val projectId: String,
    val name: String,
    val role: String,
    val company: String,
    val phone: String,
    val note: String
)

fun ProjectContact.toEntity(): ProjectContactEntity =
    ProjectContactEntity(
        id = id,
        projectId = projectId,
        relatedProjectIdsJson = BackupSnapshotJson.encodeStringList(relatedProjectIds),
        name = name,
        role = role,
        company = company,
        phone = phone,
        note = note
    )

fun ProjectContactEntity.toSummary(): ProjectContactSummary =
    ProjectContactSummary(
        id = id,
        projectId = projectId,
        name = name,
        role = role,
        company = company,
        phone = phone,
        note = note
    )

fun ProjectContactEntity.toBackupProjectContact(): ProjectContact =
    ProjectContact(
        id = id,
        projectId = projectId,
        relatedProjectIds = BackupSnapshotJson.decodeStringList(relatedProjectIdsJson),
        name = name,
        role = role,
        company = company,
        phone = phone,
        note = note
    )
