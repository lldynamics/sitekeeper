package com.chengjinfang.sitekeeper.database.finance

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.ProjectFinancialRecord

@Entity(
    tableName = "project_financial_records",
    indices = [Index("projectId")]
)
data class ProjectFinancialRecordEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val date: String,
    val direction: String,
    val category: String,
    val amount: String,
    val counterparty: String,
    val invoiceNumber: String,
    val status: String,
    val dueDate: String,
    val reminderStatus: String,
    val note: String
)

data class ProjectFinancialRecordSummary(
    val id: String,
    val date: String,
    val direction: String,
    val category: String,
    val amount: String,
    val counterparty: String,
    val status: String,
    val dueDate: String,
    val note: String
)

fun ProjectFinancialRecord.toEntity(): ProjectFinancialRecordEntity =
    ProjectFinancialRecordEntity(
        id = id,
        projectId = projectId,
        date = date,
        direction = direction,
        category = category,
        amount = amount,
        counterparty = counterparty,
        invoiceNumber = invoiceNumber,
        status = status,
        dueDate = dueDate,
        reminderStatus = reminderStatus,
        note = note
    )

fun ProjectFinancialRecordEntity.toSummary(): ProjectFinancialRecordSummary =
    ProjectFinancialRecordSummary(
        id = id,
        date = date,
        direction = direction,
        category = category,
        amount = amount,
        counterparty = counterparty,
        status = status,
        dueDate = dueDate,
        note = note
    )
