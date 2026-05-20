package com.chengjinfang.sitekeeper.database.material

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.SupplierProfile

@Entity(
    tableName = "supplier_profiles",
    indices = [
        Index("category"),
        Index("name")
    ]
)
data class SupplierProfileEntity(
    @PrimaryKey val id: String,
    val name: String,
    val category: String,
    val contact: String,
    val phone: String,
    val address: String,
    val note: String,
    val updatedAt: String
)

data class SupplierProfileSummary(
    val id: String,
    val name: String,
    val category: String,
    val contact: String,
    val phone: String,
    val address: String,
    val note: String,
    val updatedAt: String
)

fun SupplierProfile.toEntity(
    fallbackId: String,
    fallbackUpdatedAt: String
): SupplierProfileEntity =
    SupplierProfileEntity(
        id = id.trim().ifBlank { fallbackId },
        name = name.trim(),
        category = category.trim().ifBlank { "综合材料" },
        contact = contact.trim(),
        phone = phone.trim(),
        address = address.trim(),
        note = note.trim(),
        updatedAt = updatedAt.trim().ifBlank { fallbackUpdatedAt }
    )

fun SupplierProfileEntity.toSummary(): SupplierProfileSummary =
    SupplierProfileSummary(
        id = id,
        name = name,
        category = category,
        contact = contact,
        phone = phone,
        address = address,
        note = note,
        updatedAt = updatedAt
    )

fun SupplierProfileEntity.toBackupSupplierProfile(): SupplierProfile =
    SupplierProfile(
        id = id,
        name = name,
        category = category,
        contact = contact,
        phone = phone,
        address = address,
        note = note,
        updatedAt = updatedAt
    )
