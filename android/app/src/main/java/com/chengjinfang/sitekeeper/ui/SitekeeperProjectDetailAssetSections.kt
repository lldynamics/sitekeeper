package com.chengjinfang.sitekeeper.ui

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.unit.dp
import com.chengjinfang.sitekeeper.backup.deleteDrawingArchive
import com.chengjinfang.sitekeeper.backup.openLocalDocument
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentSummary
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail

internal fun LazyListScope.projectDocumentsAndDrawingsSections(
    detail: ProjectDetail,
    context: Context,
    mediaState: ProjectDetailMediaState,
    actions: ProjectAssetsActions,
    showDocumentForm: Boolean,
    onShowDocumentFormChange: (Boolean) -> Unit,
    editingDocumentId: String?,
    onEditingDocumentIdChange: (String?) -> Unit,
    showDrawingForm: Boolean,
    onShowDrawingFormChange: (Boolean) -> Unit,
    editingDrawingId: String?,
    onEditingDrawingIdChange: (String?) -> Unit,
    confirmingDeleteKey: String?,
    onConfirmingDeleteKeyChange: (String?) -> Unit
) {
    item {
        SectionTitle(
            title = "项目资料",
            count = detail.documents.size,
            actionLabel = if (showDocumentForm) "收起" else "添加资料",
            onAction = { onShowDocumentFormChange(!showDocumentForm) }
        )
    }

    if (showDocumentForm) {
        item {
            ProjectDocumentFormCard(
                availableMethods = detail.constructionMethods,
                onCancel = { onShowDocumentFormChange(false) },
                onSave = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                    actions.onAddProjectDocument(
                        title,
                        category,
                        fileName,
                        fileType,
                        pageCount,
                        amount,
                        note,
                        linkedMethodIds
                    )
                    onShowDocumentFormChange(false)
                }
            )
        }
    }

    if (detail.documents.isEmpty()) {
        item {
            CompactEmptyText("暂无项目资料")
        }
    } else {
        items(
            items = detail.documents,
            key = ProjectDocumentSummary::id
        ) { document ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ProjectDocumentRow(
                    document = document,
                    linkedMethodTitles = linkedMethodTitles(
                        detail.constructionMethods,
                        document.linkedConstructionMethodIds
                    ),
                    onOpenFile = {
                        openLocalDocument(
                            context = context,
                            localUri = document.localUri
                        )
                    },
                    onPickFile = {
                        mediaState.pickDocumentFor(document.id)
                    },
                    onEdit = {
                        onEditingDocumentIdChange(
                            if (editingDocumentId == document.id) {
                                null
                            } else {
                                document.id
                            }
                        )
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("document-${document.id}")
                    }
                )
                if (confirmingDeleteKey == "document-${document.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条项目资料？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            actions.onDeleteProjectDocument(document.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingDocumentIdChange(null)
                        }
                    )
                }
                if (editingDocumentId == document.id) {
                    ProjectDocumentFormCard(
                        formKey = "edit-document-${document.id}",
                        titleText = "编辑项目资料",
                        availableMethods = detail.constructionMethods,
                        initialTitle = document.title,
                        initialCategory = document.category,
                        initialFileName = document.fileName,
                        initialFileType = document.fileType,
                        initialPageCount = document.pageCount.toString(),
                        initialAmount = document.amount,
                        initialNote = document.note,
                        initialLinkedMethodIds = document.linkedConstructionMethodIds,
                        onCancel = { onEditingDocumentIdChange(null) },
                        onSave = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
                            actions.onUpdateProjectDocument(
                                document.id,
                                title,
                                category,
                                fileName,
                                fileType,
                                pageCount,
                                amount,
                                note,
                                linkedMethodIds
                            )
                            onEditingDocumentIdChange(null)
                        }
                    )
                }
            }
        }
    }

    item {
        SectionTitle(
            title = "项目图纸",
            count = detail.drawings.size,
            actionLabel = if (showDrawingForm) "收起" else "添加图纸",
            onAction = { onShowDrawingFormChange(!showDrawingForm) }
        )
    }

    if (showDrawingForm) {
        item {
            ProjectDrawingFormCard(
                onCancel = { onShowDrawingFormChange(false) },
                onSave = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                    actions.onAddProjectDrawing(
                        name,
                        fileName,
                        fileType,
                        version,
                        relatedLogDate,
                        issueStatus,
                        issueNote,
                        note
                    )
                    onShowDrawingFormChange(false)
                }
            )
        }
    }

    if (detail.drawings.isEmpty()) {
        item {
            CompactEmptyText("暂无项目图纸")
        }
    } else {
        items(
            items = detail.drawings,
            key = ProjectDrawingSummary::id
        ) { drawing ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                ProjectDrawingRow(
                    drawing = drawing,
                    onOpenFile = {
                        openLocalDocument(context, drawing.localUri)
                    },
                    onPickFile = {
                        mediaState.pickDrawingFor(drawing.id)
                    },
                    onEdit = {
                        onEditingDrawingIdChange(
                            if (editingDrawingId == drawing.id) {
                                null
                            } else {
                                drawing.id
                            }
                        )
                    },
                    onDeleteRequest = {
                        onConfirmingDeleteKeyChange("drawing-${drawing.id}")
                    }
                )
                if (confirmingDeleteKey == "drawing-${drawing.id}") {
                    ConfirmDeleteRow(
                        label = "删除这条项目图纸？",
                        onCancel = { onConfirmingDeleteKeyChange(null) },
                        onConfirm = {
                            if (drawing.localUri.isNotBlank() && drawing.fileName.isNotBlank()) {
                                deleteDrawingArchive(context, drawing.fileName)
                            }
                            actions.onDeleteProjectDrawing(drawing.id)
                            onConfirmingDeleteKeyChange(null)
                            onEditingDrawingIdChange(null)
                        }
                    )
                }
                if (editingDrawingId == drawing.id) {
                    ProjectDrawingFormCard(
                        formKey = "edit-drawing-${drawing.id}",
                        titleText = "编辑项目图纸",
                        initialName = drawing.name,
                        initialFileName = drawing.fileName,
                        initialFileType = drawing.fileType,
                        initialVersion = drawing.version,
                        initialRelatedLogDate = drawing.relatedLogDate,
                        initialIssueStatus = drawing.issueStatus,
                        initialIssueNote = drawing.issueNote,
                        initialNote = drawing.note,
                        onCancel = { onEditingDrawingIdChange(null) },
                        onSave = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
                            actions.onUpdateProjectDrawing(
                                drawing.id,
                                name,
                                fileName,
                                fileType,
                                version,
                                relatedLogDate,
                                issueStatus,
                                issueNote,
                                note
                            )
                            onEditingDrawingIdChange(null)
                        }
                    )
                }
            }
        }
    }
}
