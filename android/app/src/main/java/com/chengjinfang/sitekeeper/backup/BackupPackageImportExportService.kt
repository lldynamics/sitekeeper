package com.chengjinfang.sitekeeper.backup

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

private const val BACKUP_JSON_ENTRY_NAME = "backup.json"
private const val BACKUP_JSON_DATA_ENTRY_NAME = "data/backup.json"

internal data class BackupPackageExportResult(
    val documentFileCount: Int,
    val photoFileCount: Int = 0,
    val drawingFileCount: Int = 0,
    val quickNoteAttachmentFileCount: Int = 0
)

internal data class BackupPackageImportContent(
    val rawJson: String,
    val attachmentCount: Int = 0,
    val attachmentTempDir: File? = null,
    val preflightWarnings: List<String> = emptyList(),
    val restorableDocumentIds: Set<String> = emptySet(),
    val restorablePhotoFileNames: Set<String> = emptySet(),
    val restorableDrawingIdsByFileName: Map<String, String> = emptyMap(),
    val restorableQuickNoteAttachmentFileNames: Set<String> = emptySet()
)

internal suspend fun writeBackupPackageToUri(
    context: Context,
    uri: Uri,
    rawJson: String
): BackupPackageExportResult =
    withContext(Dispatchers.IO) {
        var documentFileCount = 0
        var photoFileCount = 0
        var drawingFileCount = 0
        var quickNoteAttachmentFileCount = 0
        val exportedDocumentIds = runCatching {
            BackupSnapshotJson.decode(rawJson).projectDocuments
                .map { it.id }
                .filter { it.isNotBlank() }
                .toSet()
        }.getOrNull()
        val exportedPhotoFileNames = runCatching {
            currentPhotoFileNames(rawJson)
        }.getOrNull()
        val exportedDrawingFileNames = runCatching {
            currentDrawingFileNames(rawJson)
        }.getOrNull()
        val exportedQuickNoteAttachmentFileNames = runCatching {
            currentQuickNoteAttachmentFileNames(rawJson)
        }.getOrNull()
        context.contentResolver
            .openOutputStream(uri)
            ?.use { rawOutput ->
                ZipOutputStream(BufferedOutputStream(rawOutput)).use { zip ->
                    zip.putNextEntry(ZipEntry(BACKUP_JSON_ENTRY_NAME))
                    zip.write(rawJson.toByteArray(Charsets.UTF_8))
                    zip.closeEntry()
                    zip.putNextEntry(ZipEntry(BACKUP_JSON_DATA_ENTRY_NAME))
                    zip.write(rawJson.toByteArray(Charsets.UTF_8))
                    zip.closeEntry()

                    val documentRoot = projectDocumentArchiveRoot(context)
                    documentRoot
                        .listFiles()
                        ?.filter { documentDir ->
                            documentDir.isDirectory &&
                                (exportedDocumentIds == null || documentDir.name in exportedDocumentIds)
                        }
                        ?.sortedBy { it.name }
                        ?.forEach { documentDir ->
                            documentDir
                                .listFiles()
                                ?.filter { it.isFile && it.canRead() }
                                ?.sortedBy { it.name }
                                ?.forEach { file ->
                                    val entryName = listOf(
                                        PROJECT_DOCUMENTS_ARCHIVE_DIR,
                                        safeZipPathSegment(documentDir.name),
                                        safeArchiveFileName(file.name)
                                    ).joinToString("/")
                                    zip.putNextEntry(ZipEntry(entryName))
                                    file.inputStream().use { input ->
                                        input.copyTo(zip)
                                    }
                                    zip.closeEntry()
                                    documentFileCount += 1
                                }
                        }

                    val photoRoot = photoArchiveRoot(context)
                    photoRoot
                        .listFiles()
                        ?.filter { file ->
                            file.isFile &&
                                file.canRead() &&
                                (exportedPhotoFileNames == null || file.name in exportedPhotoFileNames)
                        }
                        ?.sortedBy { it.name }
                        ?.forEach { file ->
                            val entryName = listOf(
                                PHOTOS_ARCHIVE_DIR,
                                safeArchiveFileName(file.name)
                            ).joinToString("/")
                            zip.putNextEntry(ZipEntry(entryName))
                            file.inputStream().use { input ->
                                input.copyTo(zip)
                            }
                            zip.closeEntry()
                            photoFileCount += 1
                        }

                    val drawingRoot = drawingArchiveRoot(context)
                    drawingRoot
                        .listFiles()
                        ?.filter { file ->
                            file.isFile &&
                                file.canRead() &&
                                (exportedDrawingFileNames == null || file.name in exportedDrawingFileNames)
                        }
                        ?.sortedBy { it.name }
                        ?.forEach { file ->
                            val entryName = listOf(
                                DRAWINGS_ARCHIVE_DIR,
                                safeArchiveFileName(file.name)
                            ).joinToString("/")
                            zip.putNextEntry(ZipEntry(entryName))
                            file.inputStream().use { input ->
                                input.copyTo(zip)
                            }
                            zip.closeEntry()
                            drawingFileCount += 1
                        }

                    val quickNoteAttachmentRoot = quickNoteAttachmentArchiveRoot(context)
                    quickNoteAttachmentRoot
                        .listFiles()
                        ?.filter { file ->
                            file.isFile &&
                                file.canRead() &&
                                (
                                    exportedQuickNoteAttachmentFileNames == null ||
                                        file.name in exportedQuickNoteAttachmentFileNames
                                    )
                        }
                        ?.sortedBy { it.name }
                        ?.forEach { file ->
                            val entryName = listOf(
                                QUICK_NOTE_ATTACHMENTS_ARCHIVE_DIR,
                                safeArchiveFileName(file.name)
                            ).joinToString("/")
                            zip.putNextEntry(ZipEntry(entryName))
                            file.inputStream().use { input ->
                                input.copyTo(zip)
                            }
                            zip.closeEntry()
                            quickNoteAttachmentFileCount += 1
                        }
                }
            }
            ?: error("无法写入文件")

        BackupPackageExportResult(
            documentFileCount = documentFileCount,
            photoFileCount = photoFileCount,
            drawingFileCount = drawingFileCount,
            quickNoteAttachmentFileCount = quickNoteAttachmentFileCount
        )
    }

internal suspend fun readBackupImportFromUri(
    context: Context,
    uri: Uri
): BackupPackageImportContent =
    if (isBackupPackageUri(context, uri)) {
        readBackupPackageFromUri(context, uri)
    } else {
        val rawJson = readTextFromUri(
            context = context,
            uri = uri
        )
        BackupPackageImportContent(
            rawJson = rawJson,
            preflightWarnings = legacyJsonImportWarnings(rawJson)
        )
    }

private suspend fun readTextFromUri(
    context: Context,
    uri: Uri
): String =
    withContext(Dispatchers.IO) {
        context.contentResolver
            .openInputStream(uri)
            ?.bufferedReader()
            ?.use { it.readText() }
            ?: error("无法读取文件")
    }

private fun isBackupPackageUri(
    context: Context,
    uri: Uri
): Boolean {
    val mimeType = context.contentResolver.getType(uri).orEmpty().lowercase(Locale.ROOT)
    val displayName = queryDisplayName(context, uri).lowercase(Locale.ROOT)
    return mimeType.contains("zip") || displayName.endsWith(".zip")
}

internal fun legacyJsonImportWarnings(rawJson: String): List<String> {
    val documentCount = BackupSnapshotJson.decode(rawJson).projectDocuments.size
    val photoCount = currentPhotoFileNames(rawJson).size
    val drawingCount = currentDrawingFileNames(rawJson).size
    val quickNoteAttachmentCount = currentQuickNoteAttachmentFileNames(rawJson).size
    return buildList {
        if (documentCount > 0) {
            add("旧 JSON 不包含资料附件，资料记录导入后需要重新选择文件")
        }
        if (photoCount > 0) {
            add("旧 JSON 不包含照片文件，日志/待办照片导入后需要重新选择文件")
        }
        if (drawingCount > 0) {
            add("旧 JSON 不包含图纸文件，图纸记录导入后需要重新选择文件")
        }
        if (quickNoteAttachmentCount > 0) {
            add("旧 JSON 不包含随手记附件文件，随手记附件导入后需要重新选择文件")
        }
    }
}

internal data class BackupImportPreflight(
    val warnings: List<String>,
    val restorableDocumentIds: Set<String>,
    val restorablePhotoFileNames: Set<String> = emptySet(),
    val restorableDrawingIdsByFileName: Map<String, String> = emptyMap(),
    val restorableQuickNoteAttachmentFileNames: Set<String> = emptySet()
)

internal fun backupImportPreflight(
    rawJson: String,
    attachmentCountsByDocumentId: Map<String, Int>,
    invalidAttachmentCount: Int,
    duplicateEntryCount: Int,
    isZipPackage: Boolean,
    incomingPhotoFileNames: Set<String> = emptySet(),
    incomingDrawingFileNames: Set<String> = emptySet(),
    incomingQuickNoteAttachmentFileNames: Set<String> = emptySet()
): BackupImportPreflight {
    val documentIds = currentProjectDocumentIds(rawJson)
    val photoFileNames = currentPhotoFileNames(rawJson)
    val drawingFileNames = currentDrawingFileNames(rawJson)
    val drawingIdByFileName = currentDrawingIdByFileName(rawJson)
    val quickNoteAttachmentFileNames = currentQuickNoteAttachmentFileNames(rawJson)
    val attachmentDocumentIds = attachmentCountsByDocumentId.keys
    val restorableDocumentIds = attachmentDocumentIds
        .filter { it in documentIds }
        .toSet()
    val restorablePhotoFileNames = incomingPhotoFileNames
        .filter { it in photoFileNames }
        .toSet()
    val restorableDrawingIdsByFileName = incomingDrawingFileNames
        .filter { it in drawingFileNames }
        .associateWith { fileName -> drawingIdByFileName[fileName].orEmpty() }
        .filterValues(String::isNotBlank)
    val restorableQuickNoteAttachmentFileNames = incomingQuickNoteAttachmentFileNames
        .filter { it in quickNoteAttachmentFileNames }
        .toSet()
    val orphanAttachmentCount = attachmentCountsByDocumentId
        .filterKeys { it !in documentIds }
        .values
        .sum()
    val orphanPhotoFileCount = incomingPhotoFileNames.count { it !in photoFileNames }
    val orphanDrawingFileCount = incomingDrawingFileNames.count { it !in drawingFileNames }
    val orphanQuickNoteAttachmentFileCount = incomingQuickNoteAttachmentFileNames.count {
        it !in quickNoteAttachmentFileNames
    }
    val duplicateDocumentCount = attachmentCountsByDocumentId.count { (_, count) -> count > 1 }
    val missingAttachmentDocumentCount = if (isZipPackage) {
        documentIds.count { it !in attachmentDocumentIds }
    } else {
        0
    }
    val missingPhotoFileCount = if (isZipPackage) {
        photoFileNames.count { it !in incomingPhotoFileNames }
    } else {
        0
    }
    val missingDrawingFileCount = if (isZipPackage) {
        drawingFileNames.count { it !in incomingDrawingFileNames }
    } else {
        0
    }
    val missingQuickNoteAttachmentFileCount = if (isZipPackage) {
        quickNoteAttachmentFileNames.count { it !in incomingQuickNoteAttachmentFileNames }
    } else {
        0
    }
    val warnings = buildList {
        if (invalidAttachmentCount > 0) {
            add("有 $invalidAttachmentCount 个附件路径不符合备份包结构，导入时会跳过")
        }
        if (duplicateEntryCount > 0) {
            add("有 $duplicateEntryCount 个重复附件条目，导入时只保留第一份")
        }
        if (orphanAttachmentCount > 0) {
            add("有 $orphanAttachmentCount 个附件没有匹配的资料记录，导入时不会恢复")
        }
        if (orphanPhotoFileCount > 0) {
            add("有 $orphanPhotoFileCount 个照片文件没有匹配的日志或待办记录，导入时不会恢复")
        }
        if (orphanDrawingFileCount > 0) {
            add("有 $orphanDrawingFileCount 个图纸文件没有匹配的图纸记录，导入时不会恢复")
        }
        if (orphanQuickNoteAttachmentFileCount > 0) {
            add("有 $orphanQuickNoteAttachmentFileCount 个随手记附件文件没有匹配的随手记记录，导入时不会恢复")
        }
        if (duplicateDocumentCount > 0) {
            add("有 $duplicateDocumentCount 条资料记录带有多个附件，导入时只恢复每条第一份")
        }
        if (missingAttachmentDocumentCount > 0) {
            add("有 $missingAttachmentDocumentCount 条资料记录没有随包附件，导入后会显示未归档或需重新选择文件")
        }
        if (missingPhotoFileCount > 0) {
            add("有 $missingPhotoFileCount 个照片引用没有随包文件，导入后需要重新选择照片")
        }
        if (missingDrawingFileCount > 0) {
            add("有 $missingDrawingFileCount 个图纸引用没有随包文件，导入后需要重新选择图纸文件")
        }
        if (missingQuickNoteAttachmentFileCount > 0) {
            add("有 $missingQuickNoteAttachmentFileCount 个随手记附件引用没有随包文件，导入后需要重新选择附件")
        }
        if (documentIds.isEmpty() && attachmentCountsByDocumentId.isNotEmpty()) {
            add("备份包包含附件，但 backup.json 没有项目资料记录")
        }
        if (photoFileNames.isEmpty() && incomingPhotoFileNames.isNotEmpty()) {
            add("备份包包含照片，但 backup.json 没有日志或待办照片引用")
        }
        if (drawingFileNames.isEmpty() && incomingDrawingFileNames.isNotEmpty()) {
            add("备份包包含图纸文件，但 backup.json 没有图纸文件引用")
        }
        if (quickNoteAttachmentFileNames.isEmpty() && incomingQuickNoteAttachmentFileNames.isNotEmpty()) {
            add("备份包包含随手记附件文件，但 backup.json 没有随手记附件引用")
        }
    }

    return BackupImportPreflight(
        warnings = warnings,
        restorableDocumentIds = restorableDocumentIds,
        restorablePhotoFileNames = restorablePhotoFileNames,
        restorableDrawingIdsByFileName = restorableDrawingIdsByFileName,
        restorableQuickNoteAttachmentFileNames = restorableQuickNoteAttachmentFileNames
    )
}

private suspend fun readBackupPackageFromUri(
    context: Context,
    uri: Uri
): BackupPackageImportContent =
    withContext(Dispatchers.IO) {
        val tempDir = File(context.cacheDir, "sitekeeper-backup-import-${System.currentTimeMillis()}")
        var rawJson: String? = null
        var attachmentCount = 0
        var invalidAttachmentCount = 0
        var duplicateEntryCount = 0
        val copiedEntries = mutableSetOf<String>()
        val attachmentCountsByDocumentId = mutableMapOf<String, Int>()
        val incomingPhotoFileNames = mutableSetOf<String>()
        val incomingDrawingFileNames = mutableSetOf<String>()
        val incomingQuickNoteAttachmentFileNames = mutableSetOf<String>()

        try {
            context.contentResolver
                .openInputStream(uri)
                ?.use { rawInput ->
                    ZipInputStream(BufferedInputStream(rawInput)).use { zip ->
                        while (true) {
                            val entry = zip.nextEntry ?: break
                            val entryName = normalizedZipEntryName(entry.name)
                            if (!entry.isDirectory && entryName != null) {
                                when {
                                    entryName == BACKUP_JSON_ENTRY_NAME ||
                                        entryName == BACKUP_JSON_DATA_ENTRY_NAME -> {
                                        rawJson = readCurrentZipEntry(zip).toString(Charsets.UTF_8)
                                    }

                                    entryName.startsWith("$PROJECT_DOCUMENTS_ARCHIVE_DIR/") -> {
                                        val parts = entryName.split("/")
                                        if (parts.size == 3 && parts[1].isNotBlank() && parts[2].isNotBlank()) {
                                            val documentId = parts[1]
                                            val fileName = parts.last()
                                            if (!copiedEntries.add(entryName)) {
                                                duplicateEntryCount += 1
                                            } else {
                                                val outputFile = File(
                                                    File(tempDir, "$PROJECT_DOCUMENTS_ARCHIVE_DIR/$documentId"),
                                                    safeArchiveFileName(fileName)
                                                )
                                                outputFile.parentFile?.mkdirs()
                                                outputFile.outputStream().use { output ->
                                                    zip.copyTo(output)
                                                }
                                                attachmentCountsByDocumentId[documentId] =
                                                    (attachmentCountsByDocumentId[documentId] ?: 0) + 1
                                                attachmentCount += 1
                                            }
                                        } else {
                                            invalidAttachmentCount += 1
                                        }
                                    }

                                    entryName.startsWith("$PHOTOS_ARCHIVE_DIR/") -> {
                                        val parts = entryName.split("/")
                                        if (parts.size == 3 && parts[2].isNotBlank()) {
                                            val fileName = safeArchiveFileName(parts[2])
                                            if (!copiedEntries.add(entryName)) {
                                                duplicateEntryCount += 1
                                            } else {
                                                val outputFile = File(
                                                    File(tempDir, PHOTOS_ARCHIVE_DIR),
                                                    fileName
                                                )
                                                outputFile.parentFile?.mkdirs()
                                                outputFile.outputStream().use { output ->
                                                    zip.copyTo(output)
                                                }
                                                incomingPhotoFileNames.add(fileName)
                                                attachmentCount += 1
                                            }
                                        } else {
                                            invalidAttachmentCount += 1
                                        }
                                    }

                                    entryName.startsWith("$DRAWINGS_ARCHIVE_DIR/") -> {
                                        val parts = entryName.split("/")
                                        if (parts.size == 3 && parts[2].isNotBlank()) {
                                            val fileName = safeArchiveFileName(parts[2])
                                            if (!copiedEntries.add(entryName)) {
                                                duplicateEntryCount += 1
                                            } else {
                                                val outputFile = File(
                                                    File(tempDir, DRAWINGS_ARCHIVE_DIR),
                                                    fileName
                                                )
                                                outputFile.parentFile?.mkdirs()
                                                outputFile.outputStream().use { output ->
                                                    zip.copyTo(output)
                                                }
                                                incomingDrawingFileNames.add(fileName)
                                                attachmentCount += 1
                                            }
                                        } else {
                                            invalidAttachmentCount += 1
                                        }
                                    }

                                    entryName.startsWith("$QUICK_NOTE_ATTACHMENTS_ARCHIVE_DIR/") -> {
                                        val parts = entryName.split("/")
                                        if (parts.size == 3 && parts[2].isNotBlank()) {
                                            val fileName = safeArchiveFileName(parts[2])
                                            if (!copiedEntries.add(entryName)) {
                                                duplicateEntryCount += 1
                                            } else {
                                                val outputFile = File(
                                                    File(tempDir, QUICK_NOTE_ATTACHMENTS_ARCHIVE_DIR),
                                                    fileName
                                                )
                                                outputFile.parentFile?.mkdirs()
                                                outputFile.outputStream().use { output ->
                                                    zip.copyTo(output)
                                                }
                                                incomingQuickNoteAttachmentFileNames.add(fileName)
                                                attachmentCount += 1
                                            }
                                        } else {
                                            invalidAttachmentCount += 1
                                        }
                                    }
                                }
                            }
                            zip.closeEntry()
                        }
                    }
                }
                ?: error("无法读取文件")

            val resolvedJson = rawJson ?: error("备份包缺少 $BACKUP_JSON_ENTRY_NAME")
            val preflight = backupImportPreflight(
                rawJson = resolvedJson,
                attachmentCountsByDocumentId = attachmentCountsByDocumentId,
                invalidAttachmentCount = invalidAttachmentCount,
                duplicateEntryCount = duplicateEntryCount,
                isZipPackage = true,
                incomingPhotoFileNames = incomingPhotoFileNames,
                incomingDrawingFileNames = incomingDrawingFileNames,
                incomingQuickNoteAttachmentFileNames = incomingQuickNoteAttachmentFileNames
            )
            BackupPackageImportContent(
                rawJson = resolvedJson,
                attachmentCount = attachmentCount,
                attachmentTempDir = tempDir.takeIf { attachmentCount > 0 },
                preflightWarnings = preflight.warnings,
                restorableDocumentIds = preflight.restorableDocumentIds,
                restorablePhotoFileNames = preflight.restorablePhotoFileNames,
                restorableDrawingIdsByFileName = preflight.restorableDrawingIdsByFileName,
                restorableQuickNoteAttachmentFileNames = preflight.restorableQuickNoteAttachmentFileNames
            )
        } catch (error: Throwable) {
            tempDir.deleteRecursively()
            throw error
        }
    }

internal suspend fun restoreBackupPackageFiles(
    context: Context,
    tempDir: File?,
    projectRepository: ProjectRepository,
    replaceExistingFiles: Boolean,
    restorableDocumentIds: Set<String>,
    restorablePhotoFileNames: Set<String> = emptySet(),
    restorableDrawingIdsByFileName: Map<String, String> = emptyMap(),
    restorableQuickNoteAttachmentFileNames: Set<String> = emptySet()
): Int =
    withContext(Dispatchers.IO) {
        if (tempDir == null || !tempDir.exists()) {
            return@withContext 0
        }

        val targetRoot = projectDocumentArchiveRoot(context)
        if (replaceExistingFiles) {
            targetRoot.deleteRecursively()
            photoArchiveRoot(context).deleteRecursively()
            drawingArchiveRoot(context).deleteRecursively()
            quickNoteAttachmentArchiveRoot(context).deleteRecursively()
        }

        var restoredFileCount = 0
        val sourceRoot = File(tempDir, PROJECT_DOCUMENTS_ARCHIVE_DIR)
        sourceRoot
            .listFiles()
            ?.filter { it.isDirectory && it.name in restorableDocumentIds }
            ?.sortedBy { it.name }
            ?.forEach { documentDir ->
                val sourceFile = documentDir
                    .listFiles()
                    ?.filter { it.isFile && it.canRead() }
                    ?.sortedBy { it.name }
                    ?.firstOrNull()
                    ?: return@forEach
                val documentId = documentDir.name
                val targetDir = File(targetRoot, documentId)
                targetDir.mkdirs()
                targetDir.listFiles()?.forEach { file -> file.delete() }
                val targetFile = File(targetDir, safeArchiveFileName(sourceFile.name))
                sourceFile.copyTo(targetFile, overwrite = true)
                val archiveUri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    targetFile
                )
                projectRepository.attachProjectDocumentFile(
                    documentId = documentId,
                    fileName = targetFile.name,
                    fileType = documentFileType(
                        fileName = targetFile.name,
                        mimeType = ""
                    ),
                    localUri = archiveUri.toString()
                )
                restoredFileCount += 1
            }

        val sourcePhotoRoot = File(tempDir, PHOTOS_ARCHIVE_DIR)
        val targetPhotoRoot = photoArchiveRoot(context)
        sourcePhotoRoot
            .listFiles()
            ?.filter { file ->
                file.isFile &&
                    file.canRead() &&
                    file.name in restorablePhotoFileNames
            }
            ?.sortedBy { it.name }
            ?.forEach { sourceFile ->
                targetPhotoRoot.mkdirs()
                sourceFile.copyTo(
                    target = File(targetPhotoRoot, safeArchiveFileName(sourceFile.name)),
                    overwrite = true
                )
                restoredFileCount += 1
            }

        val sourceDrawingRoot = File(tempDir, DRAWINGS_ARCHIVE_DIR)
        val targetDrawingRoot = drawingArchiveRoot(context)
        sourceDrawingRoot
            .listFiles()
            ?.filter { file ->
                file.isFile &&
                    file.canRead() &&
                    file.name in restorableDrawingIdsByFileName.keys
            }
            ?.sortedBy { it.name }
            ?.forEach { sourceFile ->
                targetDrawingRoot.mkdirs()
                val targetFile = File(targetDrawingRoot, safeArchiveFileName(sourceFile.name))
                sourceFile.copyTo(
                    target = targetFile,
                    overwrite = true
                )
                val archiveUri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    targetFile
                )
                projectRepository.attachProjectDrawingFile(
                    drawingId = restorableDrawingIdsByFileName[sourceFile.name].orEmpty(),
                    fileName = targetFile.name,
                    fileType = documentFileType(
                        fileName = targetFile.name,
                        mimeType = ""
                    ),
                    localUri = archiveUri.toString()
                )
                restoredFileCount += 1
            }

        val sourceQuickNoteAttachmentRoot = File(tempDir, QUICK_NOTE_ATTACHMENTS_ARCHIVE_DIR)
        val targetQuickNoteAttachmentRoot = quickNoteAttachmentArchiveRoot(context)
        sourceQuickNoteAttachmentRoot
            .listFiles()
            ?.filter { file ->
                file.isFile &&
                    file.canRead() &&
                    file.name in restorableQuickNoteAttachmentFileNames
            }
            ?.sortedBy { it.name }
            ?.forEach { sourceFile ->
                targetQuickNoteAttachmentRoot.mkdirs()
                sourceFile.copyTo(
                    target = File(targetQuickNoteAttachmentRoot, safeArchiveFileName(sourceFile.name)),
                    overwrite = true
                )
                restoredFileCount += 1
            }

        restoredFileCount
    }

private fun readCurrentZipEntry(zip: ZipInputStream): ByteArray {
    val output = ByteArrayOutputStream()
    zip.copyTo(output)
    return output.toByteArray()
}

private fun normalizedZipEntryName(rawName: String): String? {
    val name = rawName
        .replace('\\', '/')
        .trimStart('/')
    return if (
        name.isBlank() ||
        name == ".." ||
        name.startsWith("../") ||
        name.contains("/../") ||
        name.startsWith("__MACOSX/")
    ) {
        null
    } else {
        name
    }
}

private fun safeZipPathSegment(value: String): String =
    safeArchiveFileName(value).ifBlank { "item" }
