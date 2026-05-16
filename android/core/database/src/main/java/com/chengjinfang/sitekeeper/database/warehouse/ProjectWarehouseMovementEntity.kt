package com.chengjinfang.sitekeeper.database.warehouse

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import com.chengjinfang.sitekeeper.model.backup.ProjectWarehouseMovement

@Entity(
    tableName = "project_warehouse_movements",
    indices = [Index("projectId")]
)
data class ProjectWarehouseMovementEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val date: String,
    val movementType: String,
    val materialName: String,
    val specification: String,
    val unit: String,
    val quantity: String,
    val counterparty: String,
    val handler: String,
    val note: String,
    val linkedDocumentIdsJson: String,
    val createdAt: String
)

data class ProjectWarehouseMovementSummary(
    val id: String,
    val date: String,
    val movementType: String,
    val materialName: String,
    val specification: String,
    val unit: String,
    val quantity: String,
    val counterparty: String,
    val handler: String,
    val note: String,
    val linkedDocumentCount: Int,
    val createdAt: String
)

fun ProjectWarehouseMovement.toEntity(): ProjectWarehouseMovementEntity =
    ProjectWarehouseMovementEntity(
        id = id,
        projectId = projectId,
        date = date,
        movementType = normalizedWarehouseMovementType(movementType),
        materialName = materialName,
        specification = specification,
        unit = unit,
        quantity = quantity,
        counterparty = counterparty,
        handler = handler,
        note = note,
        linkedDocumentIdsJson = BackupSnapshotJson.encodeStringList(linkedDocumentIds),
        createdAt = createdAt
    )

fun ProjectWarehouseMovementEntity.toSummary(): ProjectWarehouseMovementSummary =
    ProjectWarehouseMovementSummary(
        id = id,
        date = date,
        movementType = normalizedWarehouseMovementType(movementType),
        materialName = materialName,
        specification = specification,
        unit = unit,
        quantity = quantity,
        counterparty = counterparty,
        handler = handler,
        note = note,
        linkedDocumentCount = BackupSnapshotJson.decodeStringList(linkedDocumentIdsJson).size,
        createdAt = createdAt
    )

fun ProjectWarehouseMovementEntity.toBackupProjectWarehouseMovement(): ProjectWarehouseMovement =
    ProjectWarehouseMovement(
        id = id,
        projectId = projectId,
        date = date,
        movementType = normalizedWarehouseMovementType(movementType),
        materialName = materialName,
        specification = specification,
        unit = unit,
        quantity = quantity,
        counterparty = counterparty,
        handler = handler,
        note = note,
        linkedDocumentIds = BackupSnapshotJson.decodeStringList(linkedDocumentIdsJson),
        createdAt = createdAt
    )

fun normalizedWarehouseMovementType(value: String): String =
    when (value.trim()) {
        "出库", "outbound", "Outbound" -> "出库"
        else -> "入库"
    }
