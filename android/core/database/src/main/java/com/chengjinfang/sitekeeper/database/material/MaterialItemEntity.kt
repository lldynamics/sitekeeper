package com.chengjinfang.sitekeeper.database.material

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.MaterialItem

@Entity(
    tableName = "material_items",
    indices = [Index("projectId")]
)
data class MaterialItemEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val name: String,
    val quantity: String,
    val unit: String,
    val unitPrice: String,
    val specification: String,
    val brand: String,
    val supplier: String,
    val purchaseStatus: String,
    val arrivalDate: String
)

data class MaterialItemSummary(
    val id: String,
    val name: String,
    val quantity: String,
    val unit: String,
    val unitPrice: String,
    val specification: String,
    val supplier: String,
    val purchaseStatus: String,
    val arrivalDate: String
)

fun MaterialItem.toEntity(): MaterialItemEntity =
    MaterialItemEntity(
        id = id,
        projectId = projectId,
        name = name,
        quantity = quantity,
        unit = unit,
        unitPrice = unitPrice,
        specification = specification,
        brand = brand,
        supplier = supplier,
        purchaseStatus = purchaseStatus,
        arrivalDate = arrivalDate
    )

fun MaterialItemEntity.toSummary(): MaterialItemSummary =
    MaterialItemSummary(
        id = id,
        name = name,
        quantity = quantity,
        unit = unit,
        unitPrice = unitPrice,
        specification = specification,
        supplier = supplier,
        purchaseStatus = purchaseStatus,
        arrivalDate = arrivalDate
    )
