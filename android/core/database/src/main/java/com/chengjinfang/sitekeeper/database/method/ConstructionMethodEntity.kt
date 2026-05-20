package com.chengjinfang.sitekeeper.database.method

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ConstructionMethod

@Entity(
    tableName = "construction_methods",
    indices = [
        Index("trade"),
        Index("publishStatus")
    ]
)
data class ConstructionMethodEntity(
    @PrimaryKey val id: String,
    val title: String,
    val trade: String,
    val versionName: String,
    val publishStatus: String,
    val tutorialBody: String,
    val tutorialTextSize: String,
    val tutorialAttachmentsJson: String,
    val procedureStepsJson: String,
    val qualityChecklistJson: String,
    val safetyChecklistJson: String,
    val attachmentsJson: String,
    val updatedAt: String
)

data class ConstructionMethodSummary(
    val id: String,
    val title: String,
    val trade: String,
    val versionName: String,
    val publishStatus: String,
    val tutorialBody: String,
    val tutorialAttachmentCount: Int,
    val procedureSteps: List<String>,
    val qualityChecklist: List<String>,
    val safetyChecklist: List<String>,
    val attachmentCount: Int,
    val updatedAt: String
) {
    val displayTitle: String
        get() = title.ifBlank { "未命名工艺" }

    val statusLabel: String
        get() = publishStatus.ifBlank { "草稿" }
}

fun ConstructionMethod.toEntity(
    fallbackId: String,
    fallbackUpdatedAt: String
): ConstructionMethodEntity =
    ConstructionMethodEntity(
        id = id.trim().ifBlank { fallbackId },
        title = title.trim(),
        trade = trade.trim().ifBlank { "通用" },
        versionName = versionName.trim().ifBlank { "V1" },
        publishStatus = normalizedConstructionPublishStatus(publishStatus),
        tutorialBody = tutorialBody.trim(),
        tutorialTextSize = tutorialTextSize.trim().ifBlank { "normal" },
        tutorialAttachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(tutorialAttachments),
        procedureStepsJson = BackupSnapshotJson.encodeStringList(normalizedProcedureSteps),
        qualityChecklistJson = BackupSnapshotJson.encodeStringList(normalizedQualityChecklist),
        safetyChecklistJson = BackupSnapshotJson.encodeStringList(normalizedSafetyChecklist),
        attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(attachments),
        updatedAt = updatedAt.trim().ifBlank { fallbackUpdatedAt }
    )

fun ConstructionMethodEntity.toSummary(): ConstructionMethodSummary {
    val tutorialAttachments = BackupSnapshotJson.decodeQuickNoteAttachments(tutorialAttachmentsJson)
    val attachments = BackupSnapshotJson.decodeQuickNoteAttachments(attachmentsJson)
    return ConstructionMethodSummary(
        id = id,
        title = title,
        trade = trade,
        versionName = versionName,
        publishStatus = normalizedConstructionPublishStatus(publishStatus),
        tutorialBody = tutorialBody,
        tutorialAttachmentCount = tutorialAttachments.size,
        procedureSteps = BackupSnapshotJson.decodeStringList(procedureStepsJson),
        qualityChecklist = BackupSnapshotJson.decodeStringList(qualityChecklistJson),
        safetyChecklist = BackupSnapshotJson.decodeStringList(safetyChecklistJson),
        attachmentCount = attachments.size,
        updatedAt = updatedAt
    )
}

fun ConstructionMethodEntity.toBackupConstructionMethod(): ConstructionMethod {
    val procedureSteps = BackupSnapshotJson.decodeStringList(procedureStepsJson)
    val qualityChecklist = BackupSnapshotJson.decodeStringList(qualityChecklistJson)
    val safetyChecklist = BackupSnapshotJson.decodeStringList(safetyChecklistJson)
    return ConstructionMethod(
        id = id,
        title = title,
        trade = trade,
        versionName = versionName,
        publishStatus = normalizedConstructionPublishStatus(publishStatus),
        tutorialBody = tutorialBody,
        tutorialTextSize = tutorialTextSize,
        tutorialAttachments = BackupSnapshotJson.decodeQuickNoteAttachments(tutorialAttachmentsJson),
        steps = procedureSteps.joinToString("\n"),
        qualityStandard = qualityChecklist.joinToString("\n"),
        safetyNotes = safetyChecklist.joinToString("\n"),
        procedureSteps = procedureSteps,
        qualityChecklist = qualityChecklist,
        safetyChecklist = safetyChecklist,
        attachments = BackupSnapshotJson.decodeQuickNoteAttachments(attachmentsJson),
        updatedAt = updatedAt
    )
}

fun normalizedConstructionPublishStatus(value: String): String =
    when (value.trim()) {
        "已发布", "published", "Published" -> "已发布"
        "已废止", "deprecated", "Deprecated" -> "已废止"
        else -> "草稿"
    }

fun encodeConstructionMethodLines(rawText: String): String =
    BackupSnapshotJson.encodeStringList(parseConstructionMethodLines(rawText))

fun parseConstructionMethodLines(rawText: String): List<String> =
    rawText
        .lineSequence()
        .map { line -> line.trim() }
        .filter(String::isNotBlank)
        .map { item -> item.replace(Regex("^\\d+[.、)]\\s*"), "") }
        .filter(String::isNotBlank)
        .toList()
