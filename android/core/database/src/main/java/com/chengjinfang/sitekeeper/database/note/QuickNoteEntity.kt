package com.chengjinfang.sitekeeper.database.note

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.QuickNote

@Entity(
    tableName = "quick_notes",
    indices = [Index("projectId")]
)
data class QuickNoteEntity(
    @PrimaryKey val id: String,
    val title: String,
    val content: String,
    val projectId: String?,
    val createdAt: String,
    val updatedAt: String,
    val attachmentsJson: String
)

fun QuickNote.toEntity(): QuickNoteEntity =
    QuickNoteEntity(
        id = id,
        title = title,
        content = content,
        projectId = projectId,
        createdAt = createdAt,
        updatedAt = updatedAt,
        attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(attachments)
    )

fun QuickNoteEntity.toBackupQuickNote(): QuickNote =
    QuickNote(
        id = id,
        title = title,
        content = content,
        projectId = projectId,
        createdAt = createdAt,
        updatedAt = updatedAt,
        attachments = BackupSnapshotJson.decodeQuickNoteAttachments(attachmentsJson)
    )
