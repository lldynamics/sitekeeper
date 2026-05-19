package com.chengjinfang.sitekeeper.ui

import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal fun buildProjectCommercialActions(
    projectId: String,
    projectRepository: ProjectRepository,
    scope: CoroutineScope
): ProjectCommercialActions =
    ProjectCommercialActions(
        onAddQuoteItem = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
            scope.launch {
                projectRepository.addQuoteItem(
                    projectId = projectId,
                    name = name,
                    unitPrice = unitPrice,
                    quantity = quantity,
                    unit = unit,
                    versionName = versionName,
                    status = status,
                    customerConfirmedDate = customerConfirmedDate,
                    contractAmount = contractAmount,
                    notes = notes
                )
            }
        },
        onUpdateQuoteItem = { quoteItemId, name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
            scope.launch {
                projectRepository.updateQuoteItem(
                    quoteItemId = quoteItemId,
                    name = name,
                    unitPrice = unitPrice,
                    quantity = quantity,
                    unit = unit,
                    versionName = versionName,
                    status = status,
                    customerConfirmedDate = customerConfirmedDate,
                    contractAmount = contractAmount,
                    notes = notes
                )
            }
        },
        onDeleteQuoteItem = { quoteItemId ->
            scope.launch {
                projectRepository.deleteQuoteItem(quoteItemId)
            }
        },
        onAddLaborRecord = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
            scope.launch {
                projectRepository.addLaborRecord(
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
            }
        },
        onUpdateLaborRecord = { recordId, date, workers, hours, unitRate, workType, teamName, isSettled, note ->
            scope.launch {
                projectRepository.updateLaborRecord(
                    recordId = recordId,
                    date = date,
                    workers = workers,
                    hours = hours,
                    unitRate = unitRate,
                    workType = workType,
                    teamName = teamName,
                    isSettled = isSettled,
                    note = note
                )
            }
        },
        onSetLaborRecordSettled = { recordId, isSettled ->
            scope.launch {
                projectRepository.setLaborRecordSettled(
                    recordId = recordId,
                    isSettled = isSettled
                )
            }
        },
        onDeleteLaborRecord = { recordId ->
            scope.launch {
                projectRepository.deleteLaborRecord(recordId)
            }
        },
        onAddWarehouseMovement = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
            scope.launch {
                projectRepository.addProjectWarehouseMovement(
                    projectId = projectId,
                    date = date,
                    movementType = movementType,
                    materialName = materialName,
                    specification = specification,
                    unit = unit,
                    quantity = quantity,
                    counterparty = counterparty,
                    handler = handler,
                    note = note
                )
            }
        },
        onUpdateWarehouseMovement = { movementId, date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
            scope.launch {
                projectRepository.updateProjectWarehouseMovement(
                    movementId = movementId,
                    date = date,
                    movementType = movementType,
                    materialName = materialName,
                    specification = specification,
                    unit = unit,
                    quantity = quantity,
                    counterparty = counterparty,
                    handler = handler,
                    note = note
                )
            }
        },
        onDeleteWarehouseMovement = { movementId ->
            scope.launch {
                projectRepository.deleteProjectWarehouseMovement(movementId)
            }
        }
    )
