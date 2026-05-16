package com.chengjinfang.sitekeeper.database.record

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.chengjinfang.sitekeeper.model.backup.SiteTodo

@Entity(
    tableName = "site_todos",
    indices = [Index("projectId")]
)
data class SiteTodoEntity(
    @PrimaryKey val id: String,
    val projectId: String?,
    val title: String,
    val owner: String,
    val dueDate: String,
    val priority: String,
    val issueType: String,
    val isDone: Boolean,
    val completedAt: String?,
    val note: String
)

data class SiteTodoSummary(
    val id: String,
    val title: String,
    val owner: String,
    val dueDate: String,
    val priority: String,
    val issueType: String,
    val isDone: Boolean,
    val note: String
)

fun SiteTodo.toEntity(): SiteTodoEntity =
    SiteTodoEntity(
        id = id,
        projectId = projectId,
        title = title,
        owner = owner,
        dueDate = dueDate,
        priority = priority,
        issueType = issueType,
        isDone = isDone,
        completedAt = completedAt,
        note = note
    )

fun SiteTodoEntity.toSummary(): SiteTodoSummary =
    SiteTodoSummary(
        id = id,
        title = title,
        owner = owner,
        dueDate = dueDate,
        priority = priority,
        issueType = issueType,
        isDone = isDone,
        note = note
    )
