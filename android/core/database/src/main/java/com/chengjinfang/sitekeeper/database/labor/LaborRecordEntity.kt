package com.chengjinfang.sitekeeper.database.labor

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.LaborRecord

@Entity(
    tableName = "labor_records",
    indices = [Index("projectId")]
)
data class LaborRecordEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val date: String,
    val workers: String,
    val hours: String,
    val unitRate: String,
    val workType: String,
    val teamName: String,
    val isSettled: Boolean,
    val note: String
)

data class LaborRecordSummary(
    val id: String,
    val date: String,
    val workers: String,
    val hours: String,
    val unitRate: String,
    val workType: String,
    val teamName: String,
    val isSettled: Boolean,
    val note: String
)

fun LaborRecord.toEntity(): LaborRecordEntity =
    LaborRecordEntity(
        id = id,
        projectId = projectId,
        date = date,
        workers = workers,
        hours = hours,
        unitRate = unitRate,
        workType = workType,
        teamName = teamName,
        isSettled = isSettled,
        note = note
    )

fun LaborRecordEntity.toSummary(): LaborRecordSummary =
    LaborRecordSummary(
        id = id,
        date = date,
        workers = workers,
        hours = hours,
        unitRate = unitRate,
        workType = workType,
        teamName = teamName,
        isSettled = isSettled,
        note = note
    )

fun LaborRecordEntity.toBackupLaborRecord(): LaborRecord =
    LaborRecord(
        id = id,
        date = date,
        workers = workers,
        hours = hours,
        unitRate = unitRate,
        workType = workType,
        teamName = teamName,
        isSettled = isSettled,
        note = note,
        projectId = projectId
    )
