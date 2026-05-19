package com.chengjinfang.sitekeeper.ui

import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal fun buildProjectDailyTodoActions(
    projectId: String,
    projectRepository: ProjectRepository,
    scope: CoroutineScope
): ProjectDailyTodoActions =
    ProjectDailyTodoActions(
        onAddDailyLog = { date, content, workers, weather, linkedMethodIds ->
            scope.launch {
                projectRepository.addDailyLog(
                    projectId = projectId,
                    date = date,
                    content = content,
                    workers = workers,
                    weather = weather,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onUpdateDailyLog = { dailyLogId, date, content, workers, weather, linkedMethodIds ->
            scope.launch {
                projectRepository.updateDailyLog(
                    dailyLogId = dailyLogId,
                    date = date,
                    content = content,
                    workers = workers,
                    weather = weather,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onDeleteDailyLog = { dailyLogId ->
            scope.launch {
                projectRepository.deleteDailyLog(dailyLogId)
            }
        },
        onAttachDailyLogPhoto = { dailyLogId, fileName ->
            scope.launch {
                projectRepository.attachDailyLogPhoto(dailyLogId, fileName)
            }
        },
        onDeleteDailyLogPhoto = { dailyLogId, fileName ->
            scope.launch {
                projectRepository.deleteDailyLogPhoto(dailyLogId, fileName)
            }
        },
        onAddProgressTask = { title, startDate, dueDate, completion, note ->
            scope.launch {
                projectRepository.addProgressTask(
                    projectId = projectId,
                    title = title,
                    startDate = startDate,
                    dueDate = dueDate,
                    completion = completion,
                    note = note
                )
            }
        },
        onUpdateProgressTask = { taskId, title, startDate, dueDate, completion, note ->
            scope.launch {
                projectRepository.updateProgressTask(
                    taskId = taskId,
                    title = title,
                    startDate = startDate,
                    dueDate = dueDate,
                    completion = completion,
                    note = note
                )
            }
        },
        onSetProgressTaskCompletion = { taskId, completion ->
            scope.launch {
                projectRepository.setProgressTaskCompletion(
                    taskId = taskId,
                    completion = completion
                )
            }
        },
        onDeleteProgressTask = { taskId ->
            scope.launch {
                projectRepository.deleteProgressTask(taskId)
            }
        },
        onAddSiteTodo = { title, owner, dueDate, priority, issueType, linkedMethodIds ->
            scope.launch {
                projectRepository.addSiteTodo(
                    projectId = projectId,
                    title = title,
                    owner = owner,
                    dueDate = dueDate,
                    priority = priority,
                    issueType = issueType,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onUpdateSiteTodo = { todoId, title, owner, dueDate, priority, issueType, linkedMethodIds ->
            scope.launch {
                projectRepository.updateSiteTodo(
                    todoId = todoId,
                    title = title,
                    owner = owner,
                    dueDate = dueDate,
                    priority = priority,
                    issueType = issueType,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onDeleteSiteTodo = { todoId ->
            scope.launch {
                projectRepository.deleteSiteTodo(todoId)
            }
        },
        onAttachSiteTodoPhoto = { todoId, target, fileName ->
            scope.launch {
                projectRepository.attachSiteTodoPhoto(todoId, target, fileName)
            }
        },
        onDeleteSiteTodoPhoto = { todoId, target ->
            scope.launch {
                projectRepository.deleteSiteTodoPhoto(todoId, target)
            }
        },
        onSetSiteTodoDone = { todoId, isDone ->
            scope.launch {
                projectRepository.setSiteTodoDone(
                    todoId = todoId,
                    isDone = isDone
                )
            }
        }
    )
