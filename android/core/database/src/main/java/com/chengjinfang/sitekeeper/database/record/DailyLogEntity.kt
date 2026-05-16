package com.chengjinfang.sitekeeper.database.record

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.DailyLog

@Entity(
    tableName = "daily_logs",
    indices = [Index("projectId")]
)
data class DailyLogEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val date: String,
    val weather: String,
    val content: String,
    val workers: String,
    val safety: String,
    val materials: String,
    val tomorrowPlan: String
)

data class DailyLogSummary(
    val id: String,
    val date: String,
    val weather: String,
    val content: String,
    val workers: String,
    val safety: String,
    val materials: String,
    val tomorrowPlan: String
)

fun DailyLog.toEntity(): DailyLogEntity =
    DailyLogEntity(
        id = id,
        projectId = projectId,
        date = date,
        weather = weather,
        content = content,
        workers = workers,
        safety = safety,
        materials = materials,
        tomorrowPlan = tomorrowPlan
    )

fun DailyLogEntity.toSummary(): DailyLogSummary =
    DailyLogSummary(
        id = id,
        date = date,
        weather = weather,
        content = content,
        workers = workers,
        safety = safety,
        materials = materials,
        tomorrowPlan = tomorrowPlan
    )
