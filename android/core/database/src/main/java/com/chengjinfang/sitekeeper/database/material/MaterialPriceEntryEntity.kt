package com.chengjinfang.sitekeeper.database.material

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.MaterialPriceEntry

@Entity(
    tableName = "material_price_entries",
    indices = [
        Index("category"),
        Index(value = ["name", "specification", "unit"])
    ]
)
data class MaterialPriceEntryEntity(
    @PrimaryKey val id: String,
    val name: String,
    val specification: String,
    val brand: String,
    val unit: String,
    val referencePrice: String,
    val supplier: String,
    val category: String,
    val note: String,
    val updatedAt: String
)

data class MaterialPriceEntrySummary(
    val id: String,
    val name: String,
    val specification: String,
    val brand: String,
    val unit: String,
    val referencePrice: String,
    val supplier: String,
    val category: String,
    val note: String,
    val updatedAt: String
) {
    val displayName: String
        get() = listOf(name, specification)
            .map(String::trim)
            .filter(String::isNotBlank)
            .joinToString(" ")
            .ifBlank { "未命名材料" }

    val hasReferencePrice: Boolean
        get() = referencePrice.trim().isNotBlank()
}

fun MaterialPriceEntry.toEntity(
    fallbackId: String,
    fallbackUpdatedAt: String
): MaterialPriceEntryEntity =
    MaterialPriceEntryEntity(
        id = id.trim().ifBlank { fallbackId },
        name = name.trim(),
        specification = specification.trim(),
        brand = brand.trim(),
        unit = unit.trim().ifBlank { "项" },
        referencePrice = referencePrice.trim(),
        supplier = supplier.trim(),
        category = category.trim().ifBlank { "其他" },
        note = note.trim(),
        updatedAt = updatedAt.trim().ifBlank { fallbackUpdatedAt }
    )

fun MaterialPriceEntryEntity.toSummary(): MaterialPriceEntrySummary =
    MaterialPriceEntrySummary(
        id = id,
        name = name,
        specification = specification,
        brand = brand,
        unit = unit,
        referencePrice = referencePrice,
        supplier = supplier,
        category = category,
        note = note,
        updatedAt = updatedAt
    )

fun MaterialPriceEntryEntity.toBackupMaterialPriceEntry(): MaterialPriceEntry =
    MaterialPriceEntry(
        id = id,
        name = name,
        specification = specification,
        brand = brand,
        unit = unit,
        referencePrice = referencePrice,
        supplier = supplier,
        category = category,
        note = note,
        updatedAt = updatedAt
    )
