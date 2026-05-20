package com.chengjinfang.sitekeeper.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.unit.dp
import com.chengjinfang.sitekeeper.backup.deletePhotoArchive
import com.chengjinfang.sitekeeper.backup.openLocalPhoto
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.SiteTodoPhotoTarget
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary

internal fun LazyListScope.projectDailyLogAndTodoSections(
    detail: ProjectDetail,
    context: Context,
    mediaState: ProjectDetailMediaState,
    actions: ProjectDailyTodoActions,
    showDailyLogForm: Boolean,
    onShowDailyLogFormChange: (Boolean) -> Unit,
    editingDailyLogId: String?,
    onEditingDailyLogIdChange: (String?) -> Unit,
    showTodoForm: Boolean,
    onShowTodoFormChange: (Boolean) -> Unit,
    editingTodoId: String?,
    onEditingTodoIdChange: (String?) -> Unit,
    confirmingDeleteKey: String?,
    onConfirmingDeleteKeyChange: (String?) -> Unit
) {
    item {
        SectionTitle(
            title = "施工日志",
            count = detail.dailyLogs.size,
            actionLabel = if (showDailyLogForm) "收起" else "添加日志",
            onAction = { onShowDailyLogFormChange(!showDailyLogForm) }
        )
    }

    if (showDailyLogForm) {
        item {
            DailyLogFormCard(
                availableMethods = detail.constructionMethods,
                onCancel = { onShowDailyLogFormChange(false) },
                onSave = { date, content, workers, weather, linkedMethodIds ->
                    actions.onAddDailyLog(date, content, workers, weather, linkedMethodIds)
                    onShowDailyLogFormChange(false)
                }
            )
        }
    }

    if (detail.dailyLogs.isEmpty()) {
        item {
            CompactEmptyText("暂无施工日志")
        }
    } else {
        items(
            items = detail.dailyLogs,
            key = DailyLogSummary::id
        ) { log ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DailyLogRow(
                    log = log,
                    linkedMethodTitles = linkedMethodTitles(
                        detail.constructionMethods,
                        log.linkedConstructionMethodIds
                    ),
                    onEdit = {
                        onEditingDailyLogIdChange(
                            if (editingDailyLogId == log.id) {
                                null
                            } else {
                                log.id
                            }
                        )
                    },
                    onAddPhoto = {
                        mediaState.pickDailyLogPhotoFor(log.id)
                    },
                    onOpenPhoto = { fileName ->
                        openLocalPhoto(context, fileName)
                    },
                    onDeletePhoto = { fileName ->
                        deletePhotoArchive(context, fileName)
                        actions.onDeleteDailyLogPhoto(log.id, fileName)
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("daily-${log.id}")
                    }
                )
                if (confirmingDeleteKey == "daily-${log.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条施工日志？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteDailyLog(log.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingDailyLogIdChange(null)
                        }
                    )
                }
                if (editingDailyLogId == log.id) {
                    DailyLogFormCard(
                        formKey = "edit-daily-log-${log.id}",
                        title = "编辑施工日志",
                        availableMethods = detail.constructionMethods,
                        initialDate = log.date,
                        initialContent = log.content,
                        initialWorkers = log.workers,
                        initialWeather = log.weather,
                        initialLinkedMethodIds = log.linkedConstructionMethodIds,
                        onCancel = { onEditingDailyLogIdChange(null) },
                        onSave = { date, content, workers, weather, linkedMethodIds ->
                            actions.onUpdateDailyLog(log.id, date, content, workers, weather, linkedMethodIds)
                            onEditingDailyLogIdChange(null)
                        }
                    )
                }
            }
        }
    }

    item {
        SectionTitle(
            title = "待办整改",
            count = detail.siteTodos.count { !it.isDone },
            actionLabel = if (showTodoForm) "收起" else "添加待办",
            onAction = { onShowTodoFormChange(!showTodoForm) }
        )
    }

    if (showTodoForm) {
        item {
            SiteTodoFormCard(
                availableMethods = detail.constructionMethods,
                onCancel = { onShowTodoFormChange(false) },
                onSave = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                    actions.onAddSiteTodo(title, owner, dueDate, priority, issueType, linkedMethodIds)
                    onShowTodoFormChange(false)
                }
            )
        }
    }

    if (detail.siteTodos.isEmpty()) {
        item {
            CompactEmptyText("暂无待办")
        }
    } else {
        items(
            items = detail.siteTodos,
            key = SiteTodoSummary::id
        ) { todo ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SiteTodoRow(
                    todo = todo,
                    linkedMethodTitles = linkedMethodTitles(
                        detail.constructionMethods,
                        todo.linkedConstructionMethodIds
                    ),
                    onEdit = {
                        onEditingTodoIdChange(
                            if (editingTodoId == todo.id) {
                                null
                            } else {
                                todo.id
                            }
                        )
                    },
                    onToggleDone = {
                        actions.onSetSiteTodoDone(todo.id, !todo.isDone)
                    },
                    onAttachBeforePhoto = {
                        mediaState.pickTodoBeforePhotoFor(todo.id)
                    },
                    onAttachAfterPhoto = {
                        mediaState.pickTodoAfterPhotoFor(todo.id)
                    },
                    onOpenPhoto = { fileName ->
                        openLocalPhoto(context, fileName)
                    },
                    onDeleteBeforePhoto = {
                        todo.rectificationBeforePhotoFileName?.let { fileName ->
                            deletePhotoArchive(context, fileName)
                            actions.onDeleteSiteTodoPhoto(todo.id, SiteTodoPhotoTarget.Before)
                        }
                    },
                    onDeleteAfterPhoto = {
                        todo.rectificationAfterPhotoFileName?.let { fileName ->
                            deletePhotoArchive(context, fileName)
                            actions.onDeleteSiteTodoPhoto(todo.id, SiteTodoPhotoTarget.After)
                        }
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("todo-${todo.id}")
                    }
                )
                if (confirmingDeleteKey == "todo-${todo.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条待办？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteSiteTodo(todo.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingTodoIdChange(null)
                        }
                    )
                }
                if (editingTodoId == todo.id) {
                    SiteTodoFormCard(
                        formKey = "edit-todo-${todo.id}",
                        titleText = "编辑待办整改",
                        availableMethods = detail.constructionMethods,
                        initialTitle = todo.title,
                        initialOwner = todo.owner,
                        initialDueDate = todo.dueDate,
                        initialPriority = todo.priority,
                        initialIssueType = todo.issueType,
                        initialLinkedMethodIds = todo.linkedConstructionMethodIds,
                        onCancel = { onEditingTodoIdChange(null) },
                        onSave = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
                            actions.onUpdateSiteTodo(
                                todo.id,
                                title,
                                owner,
                                dueDate,
                                priority,
                                issueType,
                                linkedMethodIds
                            )
                            onEditingTodoIdChange(null)
                        }
                    )
                }
            }
        }
    }
}
