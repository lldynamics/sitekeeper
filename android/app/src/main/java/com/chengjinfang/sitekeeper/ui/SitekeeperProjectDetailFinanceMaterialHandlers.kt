package com.chengjinfang.sitekeeper.ui

import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal fun buildProjectFinanceMaterialActions(
    projectId: String,
    projectRepository: ProjectRepository,
    scope: CoroutineScope
): ProjectFinanceMaterialActions =
    ProjectFinanceMaterialActions(
        onAddFinancialRecord = { date, direction, category, amount, counterparty, status, dueDate, note ->
            scope.launch {
                projectRepository.addFinancialRecord(
                    projectId = projectId,
                    date = date,
                    direction = direction,
                    category = category,
                    amount = amount,
                    counterparty = counterparty,
                    status = status,
                    dueDate = dueDate,
                    note = note
                )
            }
        },
        onUpdateFinancialRecord = { recordId, date, direction, category, amount, counterparty, status, dueDate, note ->
            scope.launch {
                projectRepository.updateFinancialRecord(
                    recordId = recordId,
                    date = date,
                    direction = direction,
                    category = category,
                    amount = amount,
                    counterparty = counterparty,
                    status = status,
                    dueDate = dueDate,
                    note = note
                )
            }
        },
        onDeleteFinancialRecord = { recordId ->
            scope.launch {
                projectRepository.deleteFinancialRecord(recordId)
            }
        },
        onAddMaterialItem = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
            scope.launch {
                projectRepository.addMaterialItem(
                    projectId = projectId,
                    name = name,
                    specification = specification,
                    quantity = quantity,
                    unit = unit,
                    unitPrice = unitPrice,
                    supplier = supplier,
                    purchaseStatus = purchaseStatus,
                    arrivalDate = arrivalDate
                )
            }
        },
        onUpdateMaterialItem = { materialId, name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
            scope.launch {
                projectRepository.updateMaterialItem(
                    materialId = materialId,
                    name = name,
                    specification = specification,
                    quantity = quantity,
                    unit = unit,
                    unitPrice = unitPrice,
                    supplier = supplier,
                    purchaseStatus = purchaseStatus,
                    arrivalDate = arrivalDate
                )
            }
        },
        onDeleteMaterialItem = { materialId ->
            scope.launch {
                projectRepository.deleteMaterialItem(materialId)
            }
        },
        onUpdateFinancialRecordStatus = { recordId, status ->
            scope.launch {
                projectRepository.updateFinancialRecordStatus(
                    recordId = recordId,
                    status = status
                )
            }
        },
        onUpdateMaterialPurchaseStatus = { materialId, purchaseStatus ->
            scope.launch {
                projectRepository.updateMaterialPurchaseStatus(
                    materialId = materialId,
                    purchaseStatus = purchaseStatus
                )
            }
        }
    )
