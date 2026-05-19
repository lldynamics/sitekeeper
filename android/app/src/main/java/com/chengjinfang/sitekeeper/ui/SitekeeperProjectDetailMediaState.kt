package com.chengjinfang.sitekeeper.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.chengjinfang.sitekeeper.backup.archiveDocumentFile
import com.chengjinfang.sitekeeper.backup.archiveDrawingFile
import com.chengjinfang.sitekeeper.backup.archivePhotoFile
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.SiteTodoPhotoTarget
import com.chengjinfang.sitekeeper.delivery.ProjectDeliveryPackagePreflight
import com.chengjinfang.sitekeeper.delivery.defaultProjectDeliveryPackageFileName
import com.chengjinfang.sitekeeper.delivery.projectDeliveryPackagePreflight
import com.chengjinfang.sitekeeper.delivery.writeProjectDeliveryPackageToUri
import kotlinx.coroutines.launch

internal data class ProjectDetailMediaState(
    val deliveryExportStatus: String,
    val deliveryPreflight: ProjectDeliveryPackagePreflight?,
    val launchDeliveryExport: () -> Unit,
    val pickDocumentFor: (String) -> Unit,
    val pickDrawingFor: (String) -> Unit,
    val pickDailyLogPhotoFor: (String) -> Unit,
    val pickTodoBeforePhotoFor: (String) -> Unit,
    val pickTodoAfterPhotoFor: (String) -> Unit
)

@Composable
internal fun rememberProjectDetailMediaState(
    detail: ProjectDetail,
    onAttachProjectDocumentFile: (
        documentId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit,
    onAttachProjectDrawingFile: (
        drawingId: String,
        fileName: String,
        fileType: String,
        localUri: String
    ) -> Unit,
    onAttachDailyLogPhoto: (dailyLogId: String, fileName: String) -> Unit,
    onAttachSiteTodoPhoto: (todoId: String, target: SiteTodoPhotoTarget, fileName: String) -> Unit
): ProjectDetailMediaState {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var documentPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var drawingPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var photoPickerTargetKind by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var photoPickerTargetId by rememberSaveable(detail.project.id) { mutableStateOf<String?>(null) }
    var deliveryExportStatus by rememberSaveable(detail.project.id) { mutableStateOf("") }
    var deliveryPreflight by remember(detail.project.id) { mutableStateOf<ProjectDeliveryPackagePreflight?>(null) }

    fun refreshDeliveryPreflight() {
        scope.launch {
            runCatching {
                projectDeliveryPackagePreflight(
                    context = context,
                    detail = detail
                )
            }.onSuccess { preflight ->
                deliveryPreflight = preflight
            }
        }
    }

    LaunchedEffect(detail) {
        refreshDeliveryPreflight()
    }

    val deliveryExportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/zip")
    ) { uri ->
        if (uri == null) {
            deliveryExportStatus = "已取消导出"
            return@rememberLauncherForActivityResult
        }

        scope.launch {
            deliveryExportStatus = "正在导出交付包"
            runCatching {
                writeProjectDeliveryPackageToUri(
                    context = context,
                    uri = uri,
                    detail = detail
                )
            }.onSuccess { result ->
                deliveryExportStatus = "已导出交付包，含 ${result.documentFileCount} 份资料、${result.drawingFileCount} 份图纸、${result.photoFileCount} 张照片，缺失 ${result.missingFileCount} 个文件"
                refreshDeliveryPreflight()
            }.onFailure { error ->
                deliveryExportStatus = "导出失败：${error.message ?: "无法写入文件"}"
            }
        }
    }

    val documentFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val documentId = documentPickerTargetId
        if (uri != null && documentId != null) {
            runCatching {
                archiveDocumentFile(
                    context = context,
                    sourceUri = uri,
                    documentId = documentId
                )
            }.onSuccess { fileInfo ->
                onAttachProjectDocumentFile(
                    documentId,
                    fileInfo.name,
                    fileInfo.type,
                    fileInfo.localUri
                )
            }
        }
        documentPickerTargetId = null
    }

    val drawingFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val drawingId = drawingPickerTargetId
        if (uri != null && drawingId != null) {
            runCatching {
                archiveDrawingFile(
                    context = context,
                    sourceUri = uri
                )
            }.onSuccess { fileInfo ->
                onAttachProjectDrawingFile(
                    drawingId,
                    fileInfo.name,
                    fileInfo.type,
                    fileInfo.localUri
                )
            }
        }
        drawingPickerTargetId = null
    }

    val photoFilePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        val targetKind = photoPickerTargetKind
        val targetId = photoPickerTargetId
        if (uri != null && targetKind != null && targetId != null) {
            runCatching {
                archivePhotoFile(
                    context = context,
                    sourceUri = uri
                )
            }.onSuccess { fileInfo ->
                when (targetKind) {
                    "daily" -> onAttachDailyLogPhoto(targetId, fileInfo.name)
                    "todo-before" -> onAttachSiteTodoPhoto(targetId, SiteTodoPhotoTarget.Before, fileInfo.name)
                    "todo-after" -> onAttachSiteTodoPhoto(targetId, SiteTodoPhotoTarget.After, fileInfo.name)
                }
            }
        }
        photoPickerTargetKind = null
        photoPickerTargetId = null
    }

    return ProjectDetailMediaState(
        deliveryExportStatus = deliveryExportStatus,
        deliveryPreflight = deliveryPreflight,
        launchDeliveryExport = {
            deliveryExportLauncher.launch(defaultProjectDeliveryPackageFileName(detail.project.name))
        },
        pickDocumentFor = { documentId ->
            documentPickerTargetId = documentId
            documentFilePicker.launch(arrayOf("*/*"))
        },
        pickDrawingFor = { drawingId ->
            drawingPickerTargetId = drawingId
            drawingFilePicker.launch(
                arrayOf(
                    "application/pdf",
                    "image/*",
                    "application/dxf",
                    "application/dwg",
                    "application/octet-stream",
                    "*/*"
                )
            )
        },
        pickDailyLogPhotoFor = { dailyLogId ->
            photoPickerTargetKind = "daily"
            photoPickerTargetId = dailyLogId
            photoFilePicker.launch(arrayOf("image/*"))
        },
        pickTodoBeforePhotoFor = { todoId ->
            photoPickerTargetKind = "todo-before"
            photoPickerTargetId = todoId
            photoFilePicker.launch(arrayOf("image/*"))
        },
        pickTodoAfterPhotoFor = { todoId ->
            photoPickerTargetKind = "todo-after"
            photoPickerTargetId = todoId
            photoFilePicker.launch(arrayOf("image/*"))
        }
    )
}
