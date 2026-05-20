package com.chengjinfang.sitekeeper.database.progress

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.ProgressTask

@Entity(
    tableName = "progress_tasks",
    indices = [Index("projectId")]
)
data class ProgressTaskEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val title: String,
    val startDate: String,
    val dueDate: String,
    val completion: Double,
    val note: String
)

data class ProgressTaskSummary(
    val id: String,
    val title: String,
    val startDate: String,
    val dueDate: String,
    val completion: Double,
    val note: String
)

fun ProgressTask.toEntity(): ProgressTaskEntity =
    ProgressTaskEntity(
        id = id,
        projectId = projectId,
        title = title,
        startDate = startDate,
        dueDate = dueDate,
        completion = completion,
        note = note
    )

fun ProgressTaskEntity.toSummary(): ProgressTaskSummary =
    ProgressTaskSummary(
        id = id,
        title = title,
        startDate = startDate,
        dueDate = dueDate,
        completion = completion,
        note = note
    )
