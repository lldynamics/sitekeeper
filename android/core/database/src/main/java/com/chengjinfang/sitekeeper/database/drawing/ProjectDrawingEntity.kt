package com.chengjinfang.sitekeeper.database.drawing

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ProjectDrawing
import kotlinx.serialization.json.JsonObject

@Entity(
    tableName = "project_drawings",
    indices = [Index("projectId")]
)
data class ProjectDrawingEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val name: String,
    val fileName: String,
    val fileType: String,
    val version: String,
    val isCurrentVersion: Boolean,
    val relatedLogDate: String,
    val issueStatus: String,
    val issueNote: String,
    val textEncoding: String,
    val textBigFont: String,
    val textSchemeSnapshotJson: String,
    val cadViewStateJson: String,
    val importedAt: String,
    val note: String,
    val cadOverlaySnapshotData: String,
    val localUri: String = ""
)

data class ProjectDrawingSummary(
    val id: String,
    val projectId: String,
    val name: String,
    val fileName: String,
    val fileType: String,
    val version: String,
    val isCurrentVersion: Boolean,
    val relatedLogDate: String,
    val issueStatus: String,
    val issueNote: String,
    val importedAt: String,
    val note: String,
    val localUri: String
)

fun ProjectDrawing.toEntity(): ProjectDrawingEntity =
    ProjectDrawingEntity(
        id = id,
        projectId = projectId,
        name = name,
        fileName = fileName,
        fileType = fileType,
        version = version,
        isCurrentVersion = isCurrentVersion,
        relatedLogDate = relatedLogDate,
        issueStatus = issueStatus,
        issueNote = issueNote,
        textEncoding = textEncoding,
        textBigFont = textBigFont,
        textSchemeSnapshotJson = textSchemeSnapshot.toString(),
        cadViewStateJson = cadViewState.toString(),
        importedAt = importedAt,
        note = note,
        cadOverlaySnapshotData = cadOverlaySnapshotData,
        localUri = ""
    )

fun ProjectDrawingEntity.toSummary(): ProjectDrawingSummary =
    ProjectDrawingSummary(
        id = id,
        projectId = projectId,
        name = name,
        fileName = fileName,
        fileType = fileType,
        version = version,
        isCurrentVersion = isCurrentVersion,
        relatedLogDate = relatedLogDate,
        issueStatus = issueStatus,
        issueNote = issueNote,
        importedAt = importedAt,
        note = note,
        localUri = localUri
    )

fun ProjectDrawingEntity.toBackupProjectDrawing(): ProjectDrawing =
    ProjectDrawing(
        id = id,
        projectId = projectId,
        name = name,
        fileName = fileName,
        fileType = fileType,
        version = version,
        isCurrentVersion = isCurrentVersion,
        relatedLogDate = relatedLogDate,
        issueStatus = issueStatus,
        issueNote = issueNote,
        textEncoding = textEncoding,
        textBigFont = textBigFont,
        textSchemeSnapshot = decodeJsonObject(textSchemeSnapshotJson),
        cadViewState = decodeJsonObject(cadViewStateJson),
        importedAt = importedAt,
        note = note,
        cadOverlaySnapshotData = cadOverlaySnapshotData
    )

private fun decodeJsonObject(rawJson: String): JsonObject =
    if (rawJson.isBlank()) {
        JsonObject(emptyMap())
    } else {
        runCatching {
            BackupSnapshotJson.format.decodeFromString(JsonObject.serializer(), rawJson)
        }.getOrElse { JsonObject(emptyMap()) }
    }
