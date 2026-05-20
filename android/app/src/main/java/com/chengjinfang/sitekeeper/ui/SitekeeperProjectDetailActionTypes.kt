package com.chengjinfang.sitekeeper.ui

import com.chengjinfang.sitekeeper.database.project.SiteTodoPhotoTarget

internal data class ProjectOverviewActions(
    val onUpdateProject: (
        name: String,
        location: String,
        managerName: String,
        contractAmount: String,
        expectedEndDate: String
    ) -> Unit,
    val onSetProjectArchived: (archived: Boolean) -> Unit
)

internal data class ProjectDailyTodoActions(
    val onAddDailyLog: (date: String, content: String, workers: String, weather: String, linkedMethodIds: List<String>) -> Unit,
    val onUpdateDailyLog: (dailyLogId: String, date: String, content: String, workers: String, weather: String, linkedMethodIds: List<String>) -> Unit,
    val onDeleteDailyLog: (dailyLogId: String) -> Unit,
    val onAttachDailyLogPhoto: (dailyLogId: String, fileName: String) -> Unit,
    val onDeleteDailyLogPhoto: (dailyLogId: String, fileName: String) -> Unit,
    val onAddProgressTask: (title: String, startDate: String, dueDate: String, completion: String, note: String) -> Unit,
    val onUpdateProgressTask: (taskId: String, title: String, startDate: String, dueDate: String, completion: String, note: String) -> Unit,
    val onSetProgressTaskCompletion: (taskId: String, completion: Double) -> Unit,
    val onDeleteProgressTask: (taskId: String) -> Unit,
    val onAddSiteTodo: (title: String, owner: String, dueDate: String, priority: String, issueType: String, linkedMethodIds: List<String>) -> Unit,
    val onUpdateSiteTodo: (todoId: String, title: String, owner: String, dueDate: String, priority: String, issueType: String, linkedMethodIds: List<String>) -> Unit,
    val onDeleteSiteTodo: (todoId: String) -> Unit,
    val onAttachSiteTodoPhoto: (todoId: String, target: SiteTodoPhotoTarget, fileName: String) -> Unit,
    val onDeleteSiteTodoPhoto: (todoId: String, target: SiteTodoPhotoTarget) -> Unit,
    val onSetSiteTodoDone: (todoId: String, isDone: Boolean) -> Unit
)

internal data class ProjectFinanceMaterialActions(
    val onAddFinancialRecord: (
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) -> Unit,
    val onUpdateFinancialRecord: (
        recordId: String,
        date: String,
        direction: String,
        category: String,
        amount: String,
        counterparty: String,
        status: String,
        dueDate: String,
        note: String
    ) -> Unit,
    val onDeleteFinancialRecord: (recordId: String) -> Unit,
    val onAddMaterialItem: (
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) -> Unit,
    val onUpdateMaterialItem: (
        materialId: String,
        name: String,
        specification: String,
        quantity: String,
        unit: String,
        unitPrice: String,
        supplier: String,
        purchaseStatus: String,
        arrivalDate: String
    ) -> Unit,
    val onDeleteMaterialItem: (materialId: String) -> Unit,
    val onUpdateFinancialRecordStatus: (recordId: String, status: String) -> Unit,
    val onUpdateMaterialPurchaseStatus: (materialId: String, purchaseStatus: String) -> Unit
)

internal data class ProjectAssetsActions(
    val onAddProjectContact: (
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) -> Unit,
    val onUpdateProjectContact: (
        contactId: String,
        name: String,
        role: String,
        company: String,
        phone: String,
        note: String
    ) -> Unit,
    val onDeleteProjectContact: (contactId: String) -> Unit,
    val onAddProjectDocument: (
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedMethodIds: List<String>
    ) -> Unit,
    val onUpdateProjectDocument: (
        documentId: String,
        title: String,
        category: String,
        fileName: String,
        fileType: String,
        pageCount: String,
        amount: String,
        note: String,
        linkedMethodIds: List<String>
    ) -> Unit,
    val onDeleteProjectDocument: (documentId: String) -> Unit,
    val onAttachProjectDocumentFile: (
        documentId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit,
    val onAddProjectDrawing: (
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) -> Unit,
    val onUpdateProjectDrawing: (
        drawingId: String,
        name: String,
        fileName: String,
        fileType: String,
        version: String,
        relatedLogDate: String,
        issueStatus: String,
        issueNote: String,
        note: String
    ) -> Unit,
    val onDeleteProjectDrawing: (drawingId: String) -> Unit,
    val onAttachProjectDrawingFile: (
        drawingId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit
)

internal data class ProjectCommercialActions(
    val onAddQuoteItem: (
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) -> Unit,
    val onUpdateQuoteItem: (
        quoteItemId: String,
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        versionName: String,
        status: String,
        customerConfirmedDate: String,
        contractAmount: String,
        notes: String
    ) -> Unit,
    val onDeleteQuoteItem: (quoteItemId: String) -> Unit,
    val onAddLaborRecord: (
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) -> Unit,
    val onUpdateLaborRecord: (
        recordId: String,
        date: String,
        workers: String,
        hours: String,
        unitRate: String,
        workType: String,
        teamName: String,
        isSettled: Boolean,
        note: String
    ) -> Unit,
    val onSetLaborRecordSettled: (recordId: String, isSettled: Boolean) -> Unit,
    val onDeleteLaborRecord: (recordId: String) -> Unit,
    val onAddWarehouseMovement: (
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) -> Unit,
    val onUpdateWarehouseMovement: (
        movementId: String,
        date: String,
        movementType: String,
        materialName: String,
        specification: String,
        unit: String,
        quantity: String,
        counterparty: String,
        handler: String,
        note: String
    ) -> Unit,
    val onDeleteWarehouseMovement: (movementId: String) -> Unit
)
