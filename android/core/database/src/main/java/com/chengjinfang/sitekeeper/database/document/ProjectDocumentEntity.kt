package com.chengjinfang.sitekeeper.database.document

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ProjectDocument

@Entity(
    tableName = "project_documents",
    indices = [Index("projectId")]
)
data class ProjectDocumentEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val title: String,
    val category: String,
    val fileName: String,
    val fileType: String,
    val pageCount: Int,
    val amount: String,
    val linkedFinancialRecordId: String?,
    val linkedConstructionMethodIdsJson: String,
    val createdAt: String,
    val note: String,
    val localUri: String = ""
)

data class ProjectDocumentSummary(
    val id: String,
    val projectId: String,
    val title: String,
    val category: String,
    val fileName: String,
    val fileType: String,
    val pageCount: Int,
    val amount: String,
    val createdAt: String,
    val note: String,
    val localUri: String,
    val linkedConstructionMethodIds: List<String>
)

fun ProjectDocument.toEntity(): ProjectDocumentEntity =
    ProjectDocumentEntity(
        id = id,
        projectId = projectId,
        title = title,
        category = category,
        fileName = fileName,
        fileType = fileType,
        pageCount = pageCount,
        amount = amount,
        linkedFinancialRecordId = linkedFinancialRecordId,
        linkedConstructionMethodIdsJson = BackupSnapshotJson.encodeStringList(linkedConstructionMethodIDs),
        createdAt = createdAt,
        note = note,
        localUri = ""
    )

fun ProjectDocumentEntity.toSummary(): ProjectDocumentSummary =
    ProjectDocumentSummary(
        id = id,
        projectId = projectId,
        title = title,
        category = category,
        fileName = fileName,
        fileType = fileType,
        pageCount = pageCount,
        amount = amount,
        createdAt = createdAt,
        note = note,
        localUri = localUri,
        linkedConstructionMethodIds = BackupSnapshotJson.decodeStringList(linkedConstructionMethodIdsJson)
    )

fun ProjectDocumentEntity.toBackupProjectDocument(): ProjectDocument =
    ProjectDocument(
        id = id,
        projectId = projectId,
        title = title,
        category = category,
        fileName = fileName,
        fileType = fileType,
        pageCount = pageCount,
        amount = amount,
        linkedFinancialRecordId = linkedFinancialRecordId,
        linkedConstructionMethodIDs = BackupSnapshotJson.decodeStringList(linkedConstructionMethodIdsJson),
        createdAt = createdAt,
        note = note
    )
