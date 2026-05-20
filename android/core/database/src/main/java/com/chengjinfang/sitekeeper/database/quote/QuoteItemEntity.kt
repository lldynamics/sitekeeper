package com.chengjinfang.sitekeeper.database.quote

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.QuoteItem

@Entity(
    tableName = "quote_items",
    indices = [Index("projectId")]
)
data class QuoteItemEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val name: String,
    val unitPrice: String,
    val quantity: String,
    val unit: String,
    val notes: String,
    val taxRate: String,
    val discountRate: String,
    val versionName: String,
    val status: String,
    val customerConfirmedDate: String,
    val contractAmount: String
)

data class QuoteItemSummary(
    val id: String,
    val name: String,
    val unitPrice: String,
    val quantity: String,
    val unit: String,
    val notes: String,
    val versionName: String,
    val status: String,
    val customerConfirmedDate: String,
    val contractAmount: String
)

fun QuoteItem.toEntity(): QuoteItemEntity =
    QuoteItemEntity(
        id = id,
        projectId = projectId,
        name = name,
        unitPrice = unitPrice,
        quantity = quantity,
        unit = unit,
        notes = notes,
        taxRate = taxRate,
        discountRate = discountRate,
        versionName = versionName,
        status = status,
        customerConfirmedDate = customerConfirmedDate,
        contractAmount = contractAmount
    )

fun QuoteItemEntity.toSummary(): QuoteItemSummary =
    QuoteItemSummary(
        id = id,
        name = name,
        unitPrice = unitPrice,
        quantity = quantity,
        unit = unit,
        notes = notes,
        versionName = versionName,
        status = status,
        customerConfirmedDate = customerConfirmedDate,
        contractAmount = contractAmount
    )

fun QuoteItemEntity.toBackupQuoteItem(): QuoteItem =
    QuoteItem(
        id = id,
        name = name,
        unitPrice = unitPrice,
        quantity = quantity,
        unit = unit,
        notes = notes,
        taxRate = taxRate,
        discountRate = discountRate,
        versionName = versionName,
        status = status,
        customerConfirmedDate = customerConfirmedDate,
        contractAmount = contractAmount,
        projectId = projectId
    )
