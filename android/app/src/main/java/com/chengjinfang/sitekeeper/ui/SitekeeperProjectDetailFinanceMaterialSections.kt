package com.chengjinfang.sitekeeper.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.unit.dp
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail

internal fun LazyListScope.projectFinanceAndMaterialSections(
    detail: ProjectDetail,
    actions: ProjectFinanceMaterialActions,
    showFinancialRecordForm: Boolean,
    onShowFinancialRecordFormChange: (Boolean) -> Unit,
    editingFinancialRecordId: String?,
    onEditingFinancialRecordIdChange: (String?) -> Unit,
    showMaterialItemForm: Boolean,
    onShowMaterialItemFormChange: (Boolean) -> Unit,
    editingMaterialItemId: String?,
    onEditingMaterialItemIdChange: (String?) -> Unit,
    confirmingDeleteKey: String?,
    onConfirmingDeleteKeyChange: (String?) -> Unit
) {
    item {
        SectionTitle(
            title = "收支记录",
            count = detail.financialRecords.size,
            actionLabel = if (showFinancialRecordForm) "收起" else "添加收支",
            onAction = { onShowFinancialRecordFormChange(!showFinancialRecordForm) }
        )
    }

    if (showFinancialRecordForm) {
        item {
            FinancialRecordFormCard(
                onCancel = { onShowFinancialRecordFormChange(false) },
                onSave = { date, direction, category, amount, counterparty, status, dueDate, note ->
                    actions.onAddFinancialRecord(
                        date,
                        direction,
                        category,
                        amount,
                        counterparty,
                        status,
                        dueDate,
                        note
                    )
                    onShowFinancialRecordFormChange(false)
                }
            )
        }
    }

    if (detail.financialRecords.isEmpty()) {
        item {
            CompactEmptyText("暂无收支记录")
        }
    } else {
        items(
            items = detail.financialRecords,
            key = ProjectFinancialRecordSummary::id
        ) { record ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                FinancialRecordRow(
                    record = record,
                    onEdit = {
                        onEditingFinancialRecordIdChange(
                            if (editingFinancialRecordId == record.id) {
                                null
                            } else {
                                record.id
                            }
                        )
                    },
                    onUpdateStatus = { status ->
                        actions.onUpdateFinancialRecordStatus(record.id, status)
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("financial-${record.id}")
                    }
                )
                if (confirmingDeleteKey == "financial-${record.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条收支记录？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteFinancialRecord(record.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingFinancialRecordIdChange(null)
                        }
                    )
                }
                if (editingFinancialRecordId == record.id) {
                    FinancialRecordFormCard(
                        formKey = "edit-financial-${record.id}",
                        title = "编辑收支记录",
                        initialDate = record.date,
                        initialDirection = record.direction,
                        initialCategory = record.category,
                        initialAmount = record.amount,
                        initialCounterparty = record.counterparty,
                        initialStatus = record.status,
                        initialDueDate = record.dueDate,
                        initialNote = record.note,
                        onCancel = { onEditingFinancialRecordIdChange(null) },
                        onSave = { date, direction, category, amount, counterparty, status, dueDate, note ->
                            actions.onUpdateFinancialRecord(
                                record.id,
                                date,
                                direction,
                                category,
                                amount,
                                counterparty,
                                status,
                                dueDate,
                                note
                            )
                            onEditingFinancialRecordIdChange(null)
                        }
                    )
                }
            }
        }
    }

    item {
        SectionTitle(
            title = "材料状态",
            count = detail.materialItems.size,
            actionLabel = if (showMaterialItemForm) "收起" else "添加材料",
            onAction = { onShowMaterialItemFormChange(!showMaterialItemForm) }
        )
    }

    if (showMaterialItemForm) {
        item {
            MaterialItemFormCard(
                onCancel = { onShowMaterialItemFormChange(false) },
                onSave = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                    actions.onAddMaterialItem(
                        name,
                        specification,
                        quantity,
                        unit,
                        unitPrice,
                        supplier,
                        purchaseStatus,
                        arrivalDate
                    )
                    onShowMaterialItemFormChange(false)
                }
            )
        }
    }

    if (detail.materialItems.isEmpty()) {
        item {
            CompactEmptyText("暂无材料记录")
        }
    } else {
        items(
            items = detail.materialItems,
            key = MaterialItemSummary::id
        ) { material ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                MaterialItemRow(
                    material = material,
                    onEdit = {
                        onEditingMaterialItemIdChange(
                            if (editingMaterialItemId == material.id) {
                                null
                            } else {
                                material.id
                            }
                        )
                    },
                    onUpdateStatus = { purchaseStatus ->
                        actions.onUpdateMaterialPurchaseStatus(material.id, purchaseStatus)
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("material-${material.id}")
                    }
                )
                if (confirmingDeleteKey == "material-${material.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条材料记录？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteMaterialItem(material.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingMaterialItemIdChange(null)
                        }
                    )
                }
                if (editingMaterialItemId == material.id) {
                    MaterialItemFormCard(
                        formKey = "edit-material-${material.id}",
                        title = "编辑材料",
                        initialName = material.name,
                        initialSpecification = material.specification,
                        initialQuantity = material.quantity,
                        initialUnit = material.unit,
                        initialUnitPrice = material.unitPrice,
                        initialSupplier = material.supplier,
                        initialPurchaseStatus = material.purchaseStatus,
                        initialArrivalDate = material.arrivalDate,
                        onCancel = { onEditingMaterialItemIdChange(null) },
                        onSave = { name, specification, quantity, unit, unitPrice, supplier, purchaseStatus, arrivalDate ->
                            actions.onUpdateMaterialItem(
                                material.id,
                                name,
                                specification,
                                quantity,
                                unit,
                                unitPrice,
                                supplier,
                                purchaseStatus,
                                arrivalDate
                            )
                            onEditingMaterialItemIdChange(null)
                        }
                    )
                }
            }
        }
    }
}
