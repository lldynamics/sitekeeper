package com.chengjinfang.sitekeeper.ui

import android.content.Context
import com.chengjinfang.sitekeeper.backup.deleteProjectDocumentArchive
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

internal fun buildProjectAssetsActions(
    projectId: String,
    projectRepository: ProjectRepository,
    scope: CoroutineScope,
    context: Context
): ProjectAssetsActions =
    ProjectAssetsActions(
        onAddProjectContact = { name, role, company, phone, note ->
            scope.launch {
                projectRepository.addProjectContact(
                    projectId = projectId,
                    name = name,
                    role = role,
                    company = company,
                    phone = phone,
                    note = note
                )
            }
        },
        onUpdateProjectContact = { contactId, name, role, company, phone, note ->
            scope.launch {
                projectRepository.updateProjectContact(
                    contactId = contactId,
                    name = name,
                    role = role,
                    company = company,
                    phone = phone,
                    note = note
                )
            }
        },
        onDeleteProjectContact = { contactId ->
            scope.launch {
                projectRepository.deleteProjectContact(contactId)
            }
        },
        onAddProjectDocument = { title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
            scope.launch {
                projectRepository.addProjectDocument(
                    projectId = projectId,
                    title = title,
                    category = category,
                    fileName = fileName,
                    fileType = fileType,
                    pageCount = pageCount,
                    amount = amount,
                    note = note,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onUpdateProjectDocument = { documentId, title, category, fileName, fileType, pageCount, amount, note, linkedMethodIds ->
            scope.launch {
                projectRepository.updateProjectDocument(
                    documentId = documentId,
                    title = title,
                    category = category,
                    fileName = fileName,
                    fileType = fileType,
                    pageCount = pageCount,
                    amount = amount,
                    note = note,
                    linkedConstructionMethodIds = linkedMethodIds
                )
            }
        },
        onDeleteProjectDocument = { documentId ->
            scope.launch {
                projectRepository.deleteProjectDocument(documentId)
                deleteProjectDocumentArchive(
                    context = context,
                    documentId = documentId
                )
            }
        },
        onAttachProjectDocumentFile = { documentId, fileName, fileType, localUri ->
            scope.launch {
                projectRepository.attachProjectDocumentFile(
                    documentId = documentId,
                    fileName = fileName,
                    fileType = fileType,
                    localUri = localUri
                )
            }
        },
        onAddProjectDrawing = { name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
            scope.launch {
                projectRepository.addProjectDrawing(
                    projectId = projectId,
                    name = name,
                    fileName = fileName,
                    fileType = fileType,
                    version = version,
                    relatedLogDate = relatedLogDate,
                    issueStatus = issueStatus,
                    issueNote = issueNote,
                    note = note
                )
            }
        },
        onUpdateProjectDrawing = { drawingId, name, fileName, fileType, version, relatedLogDate, issueStatus, issueNote, note ->
            scope.launch {
                projectRepository.updateProjectDrawing(
                    drawingId = drawingId,
                    name = name,
                    fileName = fileName,
                    fileType = fileType,
                    version = version,
                    relatedLogDate = relatedLogDate,
                    issueStatus = issueStatus,
                    issueNote = issueNote,
                    note = note
                )
            }
        },
        onDeleteProjectDrawing = { drawingId ->
            scope.launch {
                projectRepository.deleteProjectDrawing(drawingId)
            }
        },
        onAttachProjectDrawingFile = { drawingId, fileName, fileType, localUri ->
            scope.launch {
                projectRepository.attachProjectDrawingFile(
                    drawingId = drawingId,
                    fileName = fileName,
                    fileType = fileType,
                    localUri = localUri
                )
            }
        }
    )
