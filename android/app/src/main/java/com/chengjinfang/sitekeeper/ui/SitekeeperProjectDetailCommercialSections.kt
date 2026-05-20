package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.unit.dp
import com.chengjinfang.sitekeeper.database.labor.LaborRecordSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary

internal fun LazyListScope.projectCommercialSections(
    detail: ProjectDetail,
    actions: ProjectCommercialActions,
    showQuoteForm: Boolean,
    onShowQuoteFormChange: (Boolean) -> Unit,
    editingQuoteItemId: String?,
    onEditingQuoteItemIdChange: (String?) -> Unit,
    showLaborForm: Boolean,
    onShowLaborFormChange: (Boolean) -> Unit,
    editingLaborRecordId: String?,
    onEditingLaborRecordIdChange: (String?) -> Unit,
    showWarehouseForm: Boolean,
    onShowWarehouseFormChange: (Boolean) -> Unit,
    editingWarehouseMovementId: String?,
    onEditingWarehouseMovementIdChange: (String?) -> Unit,
    confirmingDeleteKey: String?,
    onConfirmingDeleteKeyChange: (String?) -> Unit
) {
    item {
        SectionTitle(
            title = "报价项",
            count = detail.quoteItems.size,
            actionLabel = if (showQuoteForm) "收起" else "添加报价",
            onAction = { onShowQuoteFormChange(!showQuoteForm) }
        )
    }

    if (showQuoteForm) {
        item {
            QuoteItemFormCard(
                onCancel = { onShowQuoteFormChange(false) },
                onSave = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                    actions.onAddQuoteItem(
                        name,
                        unitPrice,
                        quantity,
                        unit,
                        versionName,
                        status,
                        customerConfirmedDate,
                        contractAmount,
                        notes
                    )
                    onShowQuoteFormChange(false)
                }
            )
        }
    }

    if (detail.quoteItems.isEmpty()) {
        item {
            CompactEmptyText("暂无报价项")
        }
    } else {
        items(
            items = detail.quoteItems,
            key = QuoteItemSummary::id
        ) { quote ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                QuoteItemRow(
                    quote = quote,
                    onEdit = {
                        onEditingQuoteItemIdChange(
                            if (editingQuoteItemId == quote.id) {
                                null
                            } else {
                                quote.id
                            }
                        )
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("quote-${quote.id}")
                    }
                )
                if (confirmingDeleteKey == "quote-${quote.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条报价项？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteQuoteItem(quote.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingQuoteItemIdChange(null)
                        }
                    )
                }
                if (editingQuoteItemId == quote.id) {
                    QuoteItemFormCard(
                        formKey = "edit-quote-${quote.id}",
                        titleText = "编辑报价项",
                        initialName = quote.name,
                        initialUnitPrice = quote.unitPrice,
                        initialQuantity = quote.quantity,
                        initialUnit = quote.unit,
                        initialVersionName = quote.versionName,
                        initialStatus = quote.status,
                        initialCustomerConfirmedDate = quote.customerConfirmedDate,
                        initialContractAmount = quote.contractAmount,
                        initialNotes = quote.notes,
                        onCancel = { onEditingQuoteItemIdChange(null) },
                        onSave = { name, unitPrice, quantity, unit, versionName, status, customerConfirmedDate, contractAmount, notes ->
                            actions.onUpdateQuoteItem(
                                quote.id,
                                name,
                                unitPrice,
                                quantity,
                                unit,
                                versionName,
                                status,
                                customerConfirmedDate,
                                contractAmount,
                                notes
                            )
                            onEditingQuoteItemIdChange(null)
                        }
                    )
                }
            }
        }
    }

    item {
        SectionTitle(
            title = "人工记录",
            count = detail.laborRecords.size,
            actionLabel = if (showLaborForm) "收起" else "添加人工",
            onAction = { onShowLaborFormChange(!showLaborForm) }
        )
    }

    if (showLaborForm) {
        item {
            LaborRecordFormCard(
                onCancel = { onShowLaborFormChange(false) },
                onSave = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                    actions.onAddLaborRecord(
                        date,
                        workers,
                        hours,
                        unitRate,
                        workType,
                        teamName,
                        isSettled,
                        note
                    )
                    onShowLaborFormChange(false)
                }
            )
        }
    }

    if (detail.laborRecords.isEmpty()) {
        item {
            CompactEmptyText("暂无人工记录")
        }
    } else {
        items(
            items = detail.laborRecords,
            key = LaborRecordSummary::id
        ) { labor ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                LaborRecordRow(
                    labor = labor,
                    onEdit = {
                        onEditingLaborRecordIdChange(
                            if (editingLaborRecordId == labor.id) {
                                null
                            } else {
                                labor.id
                            }
                        )
                    },
                    onToggleSettled = {
                        actions.onSetLaborRecordSettled(labor.id, !labor.isSettled)
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("labor-${labor.id}")
                    }
                )
                if (confirmingDeleteKey == "labor-${labor.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条人工记录？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteLaborRecord(labor.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingLaborRecordIdChange(null)
                        }
                    )
                }
                if (editingLaborRecordId == labor.id) {
                    LaborRecordFormCard(
                        formKey = "edit-labor-${labor.id}",
                        titleText = "编辑人工记录",
                        initialDate = labor.date,
                        initialWorkers = labor.workers,
                        initialHours = labor.hours,
                        initialUnitRate = labor.unitRate,
                        initialWorkType = labor.workType,
                        initialTeamName = labor.teamName,
                        initialIsSettled = labor.isSettled,
                        initialNote = labor.note,
                        onCancel = { onEditingLaborRecordIdChange(null) },
                        onSave = { date, workers, hours, unitRate, workType, teamName, isSettled, note ->
                            actions.onUpdateLaborRecord(
                                labor.id,
                                date,
                                workers,
                                hours,
                                unitRate,
                                workType,
                                teamName,
                                isSettled,
                                note
                            )
                            onEditingLaborRecordIdChange(null)
                        }
                    )
                }
            }
        }
    }

    item {
        SectionTitle(
            title = "项目仓库",
            count = detail.warehouseMovements.size,
            actionLabel = if (showWarehouseForm) "收起" else "添加出入库",
            onAction = { onShowWarehouseFormChange(!showWarehouseForm) }
        )
    }

    if (detail.warehouseMovements.isNotEmpty()) {
        item {
            WarehouseStockSummaryCard(movements = detail.warehouseMovements)
        }
    }

    if (showWarehouseForm) {
        item {
            WarehouseMovementFormCard(
                onCancel = { onShowWarehouseFormChange(false) },
                onSave = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                    actions.onAddWarehouseMovement(
                        date,
                        movementType,
                        materialName,
                        specification,
                        unit,
                        quantity,
                        counterparty,
                        handler,
                        note
                    )
                    onShowWarehouseFormChange(false)
                }
            )
        }
    }

    if (detail.warehouseMovements.isEmpty()) {
        item {
            CompactEmptyText("暂无出入库记录")
        }
    } else {
        items(
            items = detail.warehouseMovements,
            key = ProjectWarehouseMovementSummary::id
        ) { movement ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                WarehouseMovementRow(
                    movement = movement,
                    onEdit = {
                        onEditingWarehouseMovementIdChange(
                            if (editingWarehouseMovementId == movement.id) {
                                null
                            } else {
                                movement.id
                            }
                        )
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("warehouse-${movement.id}")
                    }
                )
                if (confirmingDeleteKey == "warehouse-${movement.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条出入库记录？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteWarehouseMovement(movement.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingWarehouseMovementIdChange(null)
                        }
                    )
                }
                if (editingWarehouseMovementId == movement.id) {
                    WarehouseMovementFormCard(
                        formKey = "edit-warehouse-${movement.id}",
                        titleText = "编辑出入库",
                        initialDate = movement.date,
                        initialMovementType = movement.movementType,
                        initialMaterialName = movement.materialName,
                        initialSpecification = movement.specification,
                        initialUnit = movement.unit,
                        initialQuantity = movement.quantity,
                        initialCounterparty = movement.counterparty,
                        initialHandler = movement.handler,
                        initialNote = movement.note,
                        onCancel = { onEditingWarehouseMovementIdChange(null) },
                        onSave = { date, movementType, materialName, specification, unit, quantity, counterparty, handler, note ->
                            actions.onUpdateWarehouseMovement(
                                movement.id,
                                date,
                                movementType,
                                materialName,
                                specification,
                                unit,
                                quantity,
                                counterparty,
                                handler,
                                note
                            )
                            onEditingWarehouseMovementIdChange(null)
                        }
                    )
                }
            }
        }
    }
}
