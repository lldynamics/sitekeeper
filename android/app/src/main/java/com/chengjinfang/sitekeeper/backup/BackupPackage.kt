package com.chengjinfang.sitekeeper.backup

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import com.chengjinfang.sitekeeper.database.project.ProjectRepository
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshot
import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

private const val BACKUP_JSON_ENTRY_NAME = "backup.json"
private const val BACKUP_JSON_DATA_ENTRY_NAME = "data/backup.json"
internal const val PROJECT_DOCUMENTS_ARCHIVE_DIR = "project-documents"
internal const val PHOTOS_ARCHIVE_DIR = "files/photos"
internal const val DRAWINGS_ARCHIVE_DIR = "files/drawings"
internal const val QUICK_NOTE_ATTACHMENTS_ARCHIVE_DIR = "files/quick-note-attachments"
private const val PHOTOS_LOCAL_DIR = "photos"
private const val DRAWINGS_LOCAL_DIR = "drawings"
private const val QUICK_NOTE_ATTACHMENTS_LOCAL_DIR = "quick-note-attachments"

internal fun defaultBackupPackageFileName(): String =
    "sitekeeper-android-${SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(Date())}.zip"

internal data class DocumentArchiveUsage(
    val totalFileCount: Int,
    val orphanFileCount: Int
)

internal data class LocalDataHealthSnapshot(
    val projectCount: Int,
    val recordCount: Int,
    val referencedDocumentFileCount: Int,
    val referencedPhotoFileCount: Int,
    val referencedDrawingFileCount: Int,
    val referencedQuickNoteAttachmentCount: Int,
    val missingDocumentFileCount: Int,
    val missingPhotoFileCount: Int,
    val missingDrawingFileCount: Int,
    val missingQuickNoteAttachmentCount: Int,
    val orphanDocumentFileCount: Int,
    val orphanPhotoFileCount: Int,
    val orphanDrawingFileCount: Int,
    val orphanQuickNoteAttachmentCount: Int,
    val orphanFileBytes: Long,
    val fixTodos: List<LocalDataHealthFixTodo> = emptyList()
) {
    val referencedFileCount: Int
        get() = referencedDocumentFileCount +
            referencedPhotoFileCount +
            referencedDrawingFileCount +
            referencedQuickNoteAttachmentCount

    val missingFileCount: Int
        get() = missingDocumentFileCount +
            missingPhotoFileCount +
            missingDrawingFileCount +
            missingQuickNoteAttachmentCount

    val orphanFileCount: Int
        get() = orphanDocumentFileCount +
            orphanPhotoFileCount +
            orphanDrawingFileCount +
            orphanQuickNoteAttachmentCount

    val issueCount: Int
        get() = missingFileCount + orphanFileCount
}

internal data class LocalDataHealthFixTodo(
    val projectId: String,
    val title: String,
    val note: String,
    val priority: String = "高",
    val issueType: String = "资料"
)

internal data class LocalArchiveCleanupResult(
    val deletedFileCount: Int,
    val deletedBytes: Long
)

internal fun documentArchiveUsageText(usage: DocumentArchiveUsage): String =
    if (usage.orphanFileCount > 0) {
        "资料附件 ${usage.totalFileCount} 个，孤立 ${usage.orphanFileCount} 个"
    } else {
        "资料附件 ${usage.totalFileCount} 个"
    }

internal fun localDataHealthSummaryText(snapshot: LocalDataHealthSnapshot): String =
    if (snapshot.issueCount > 0) {
        "发现 ${snapshot.missingFileCount} 个缺失文件、${snapshot.orphanFileCount} 个孤立文件"
    } else {
        "未发现缺失或孤立文件"
    }

internal suspend fun localDataHealth(
    context: Context,
    rawJson: String
): LocalDataHealthSnapshot =
    withContext(Dispatchers.IO) {
        val snapshot = BackupSnapshotJson.decode(rawJson)
        val references = localFileReferences(snapshot)
        val missingDocumentFileCount = references.documentFileDocumentIds.count { documentId ->
            archivedProjectDocumentFiles(context, documentId).isEmpty()
        }
        val missingPhotoFileCount = references.photoFileNames.count { fileName ->
            !archivedProjectPhotoFile(context, fileName).isFile
        }
        val missingDrawingFileCount = references.drawingFileNames.count { fileName ->
            !archivedProjectDrawingFile(context, fileName).isFile
        }
        val missingQuickNoteAttachmentCount = references.quickNoteAttachmentFileNames.count { fileName ->
            !archivedQuickNoteAttachmentFile(context, fileName).isFile
        }
        val orphanDocumentFiles = orphanProjectDocumentFiles(
            context = context,
            documentIds = references.documentIds
        )
        val orphanPhotoFiles = orphanFlatArchiveFiles(
            root = photoArchiveRoot(context),
            referencedFileNames = references.photoFileNames
        )
        val orphanDrawingFiles = orphanFlatArchiveFiles(
            root = drawingArchiveRoot(context),
            referencedFileNames = references.drawingFileNames
        )
        val orphanQuickNoteAttachmentFiles = orphanFlatArchiveFiles(
            root = quickNoteAttachmentArchiveRoot(context),
            referencedFileNames = references.quickNoteAttachmentFileNames
        )

        LocalDataHealthSnapshot(
            projectCount = snapshot.projects.size,
            recordCount = backupRecordCount(snapshot),
            referencedDocumentFileCount = references.documentFileDocumentIds.size,
            referencedPhotoFileCount = references.photoFileNames.size,
            referencedDrawingFileCount = references.drawingFileNames.size,
            referencedQuickNoteAttachmentCount = references.quickNoteAttachmentFileNames.size,
            missingDocumentFileCount = missingDocumentFileCount,
            missingPhotoFileCount = missingPhotoFileCount,
            missingDrawingFileCount = missingDrawingFileCount,
            missingQuickNoteAttachmentCount = missingQuickNoteAttachmentCount,
            orphanDocumentFileCount = orphanDocumentFiles.size,
            orphanPhotoFileCount = orphanPhotoFiles.size,
            orphanDrawingFileCount = orphanDrawingFiles.size,
            orphanQuickNoteAttachmentCount = orphanQuickNoteAttachmentFiles.size,
            orphanFileBytes = (
                orphanDocumentFiles +
                    orphanPhotoFiles +
                    orphanDrawingFiles +
                    orphanQuickNoteAttachmentFiles
                ).sumOf { file -> file.length() },
            fixTodos = missingFileFixTodos(
                context = context,
                snapshot = snapshot
            )
        )
    }

internal suspend fun cleanupOrphanLocalArchives(
    context: Context,
    rawJson: String
): LocalArchiveCleanupResult =
    withContext(Dispatchers.IO) {
        val references = localFileReferences(BackupSnapshotJson.decode(rawJson))
        val orphanDocumentFiles = orphanProjectDocumentFiles(
            context = context,
            documentIds = references.documentIds
        )
        val orphanDocumentDirs = projectDocumentArchiveRoot(context)
            .listFiles()
            ?.filter { it.isDirectory && it.name !in references.documentIds }
            .orEmpty()
        val orphanFlatFiles = orphanFlatArchiveFiles(
            root = photoArchiveRoot(context),
            referencedFileNames = references.photoFileNames
        ) + orphanFlatArchiveFiles(
            root = drawingArchiveRoot(context),
            referencedFileNames = references.drawingFileNames
        ) + orphanFlatArchiveFiles(
            root = quickNoteAttachmentArchiveRoot(context),
            referencedFileNames = references.quickNoteAttachmentFileNames
        )
        val deletedBytes = (orphanDocumentFiles + orphanFlatFiles).sumOf { file -> file.length() }
        var deletedFileCount = 0

        orphanFlatFiles.forEach { file ->
            if (file.delete()) {
                deletedFileCount += 1
            }
        }
        orphanDocumentDirs.forEach { dir ->
            deletedFileCount += countArchiveFiles(dir)
            dir.deleteRecursively()
        }

        LocalArchiveCleanupResult(
            deletedFileCount = deletedFileCount,
            deletedBytes = deletedBytes
        )
    }

internal suspend fun projectDocumentArchiveUsage(
    context: Context,
    rawJson: String
): DocumentArchiveUsage =
    withContext(Dispatchers.IO) {
        val documentIds = currentProjectDocumentIds(rawJson)
        val root = projectDocumentArchiveRoot(context)
        val totalFileCount = countArchiveFiles(root)
        val orphanFileCount = root
            .listFiles()
            ?.filter { it.isDirectory && it.name !in documentIds }
            ?.sumOf { dir -> countArchiveFiles(dir) }
            ?: 0

        DocumentArchiveUsage(
            totalFileCount = totalFileCount,
            orphanFileCount = orphanFileCount
        )
    }

internal suspend fun cleanupOrphanProjectDocumentArchives(
    context: Context,
    rawJson: String
): Int =
    withContext(Dispatchers.IO) {
        val documentIds = currentProjectDocumentIds(rawJson)
        val root = projectDocumentArchiveRoot(context)
        var deletedFileCount = 0

        root
            .listFiles()
            ?.filter { it.isDirectory && it.name !in documentIds }
            ?.forEach { dir ->
                deletedFileCount += countArchiveFiles(dir)
                dir.deleteRecursively()
            }

        deletedFileCount
    }

internal suspend fun deleteProjectDocumentArchive(
    context: Context,
    documentId: String
): Int =
    withContext(Dispatchers.IO) {
        val archiveDir = File(projectDocumentArchiveRoot(context), documentId)
        val deletedFileCount = countArchiveFiles(archiveDir)
        archiveDir.deleteRecursively()
        deletedFileCount
    }

private fun currentProjectDocumentIds(rawJson: String): Set<String> =
    BackupSnapshotJson.decode(rawJson)
        .projectDocuments
        .map { it.id }
        .filter { it.isNotBlank() }
        .toSet()

private fun currentPhotoFileNames(rawJson: String): Set<String> {
    val snapshot = BackupSnapshotJson.decode(rawJson)
    return buildSet {
        snapshot.dailyLogs.forEach { log ->
            log.photoFileName
                ?.takeIf { it.isNotBlank() }
                ?.let { add(it) }
            log.photos
                .map { it.fileName }
                .filter(String::isNotBlank)
                .forEach { add(it) }
        }
        snapshot.siteTodos.forEach { todo ->
            todo.rectificationBeforePhotoFileName
                ?.takeIf { it.isNotBlank() }
                ?.let { add(it) }
            todo.rectificationAfterPhotoFileName
                ?.takeIf { it.isNotBlank() }
                ?.let { add(it) }
        }
    }
}

private fun currentDrawingFileNames(rawJson: String): Set<String> =
    BackupSnapshotJson.decode(rawJson)
        .projectDrawings
        .map { it.fileName }
        .filter { it.isNotBlank() }
        .toSet()

private fun currentDrawingIdByFileName(rawJson: String): Map<String, String> =
    BackupSnapshotJson.decode(rawJson)
        .projectDrawings
        .filter { it.id.isNotBlank() && it.fileName.isNotBlank() }
        .associate { it.fileName to it.id }

private fun currentQuickNoteAttachmentFileNames(rawJson: String): Set<String> =
    BackupSnapshotJson.decode(rawJson)
        .quickNotes
        .flatMap { note -> note.attachments }
        .map { attachment -> attachment.fileName }
        .filter { it.isNotBlank() }
        .toSet()

private fun projectDocumentArchiveRoot(context: Context): File =
    File(context.filesDir, PROJECT_DOCUMENTS_ARCHIVE_DIR)

private fun photoArchiveRoot(context: Context): File =
    File(context.filesDir, PHOTOS_LOCAL_DIR)

private fun drawingArchiveRoot(context: Context): File =
    File(context.filesDir, DRAWINGS_LOCAL_DIR)

private fun quickNoteAttachmentArchiveRoot(context: Context): File =
    File(context.filesDir, QUICK_NOTE_ATTACHMENTS_LOCAL_DIR)

internal fun archivedProjectDocumentFiles(
    context: Context,
    documentId: String
): List<File> =
    File(projectDocumentArchiveRoot(context), documentId)
        .listFiles()
        ?.filter { it.isFile && it.canRead() }
        ?.sortedBy { it.name }
        .orEmpty()

internal fun archivedProjectPhotoFile(
    context: Context,
    fileName: String
): File =
    File(photoArchiveRoot(context), safeArchiveFileName(fileName))

internal fun archivedProjectDrawingFile(
    context: Context,
    fileName: String
): File =
    File(drawingArchiveRoot(context), safeArchiveFileName(fileName))

internal fun archivedQuickNoteAttachmentFile(
    context: Context,
    fileName: String
): File =
    File(quickNoteAttachmentArchiveRoot(context), safeArchiveFileName(fileName))

private fun countArchiveFiles(root: File): Int =
    if (root.exists()) {
        root.walkTopDown().count { file -> file.isFile }
    } else {
        0
    }

private data class LocalFileReferences(
    val documentIds: Set<String>,
    val documentFileDocumentIds: Set<String>,
    val photoFileNames: Set<String>,
    val drawingFileNames: Set<String>,
    val quickNoteAttachmentFileNames: Set<String>
)

private fun localFileReferences(snapshot: BackupSnapshot): LocalFileReferences =
    LocalFileReferences(
        documentIds = snapshot.projectDocuments
            .map { it.id }
            .filter(String::isNotBlank)
            .toSet(),
        documentFileDocumentIds = snapshot.projectDocuments
            .filter { it.id.isNotBlank() && it.fileName.isNotBlank() }
            .map { it.id }
            .toSet(),
        photoFileNames = buildSet {
            snapshot.dailyLogs.forEach { log ->
                log.photoFileName
                    ?.takeIf(String::isNotBlank)
                    ?.let(::add)
                log.photos
                    .map { it.fileName }
                    .filter(String::isNotBlank)
                    .forEach(::add)
            }
            snapshot.siteTodos.forEach { todo ->
                todo.rectificationBeforePhotoFileName
                    ?.takeIf(String::isNotBlank)
                    ?.let(::add)
                todo.rectificationAfterPhotoFileName
                    ?.takeIf(String::isNotBlank)
                    ?.let(::add)
            }
        },
        drawingFileNames = snapshot.projectDrawings
            .map { it.fileName }
            .filter(String::isNotBlank)
            .toSet(),
        quickNoteAttachmentFileNames = snapshot.quickNotes
            .flatMap { note -> note.attachments }
            .map { attachment -> attachment.fileName }
            .filter(String::isNotBlank)
            .toSet()
    )

private fun missingFileFixTodos(
    context: Context,
    snapshot: BackupSnapshot
): List<LocalDataHealthFixTodo> =
    buildList {
        snapshot.projectDocuments.forEach { document ->
            if (
                document.projectId.isNotBlank() &&
                document.id.isNotBlank() &&
                document.fileName.isNotBlank() &&
                archivedProjectDocumentFiles(context, document.id).isEmpty()
            ) {
                val title = document.title.ifBlank { document.fileName }
                add(
                    LocalDataHealthFixTodo(
                        projectId = document.projectId,
                        title = "补齐交付缺失资料：$title",
                        note = listOf(
                            "数据体检发现项目资料原文件缺失",
                            document.category.takeIf(String::isNotBlank),
                            document.fileName.takeIf(String::isNotBlank)
                        ).filterNotNull().joinToString("；")
                    )
                )
            }
        }

        snapshot.projectDrawings.forEach { drawing ->
            if (
                drawing.projectId.isNotBlank() &&
                drawing.fileName.isNotBlank() &&
                !archivedProjectDrawingFile(context, drawing.fileName).isFile
            ) {
                val title = drawing.name.ifBlank { drawing.fileName }
                add(
                    LocalDataHealthFixTodo(
                        projectId = drawing.projectId,
                        title = "补齐交付缺失图纸：$title",
                        note = listOf(
                            "数据体检发现项目图纸原文件缺失",
                            drawing.fileName.takeIf(String::isNotBlank),
                            drawing.version.takeIf(String::isNotBlank)
                        ).filterNotNull().joinToString("；"),
                        issueType = "图纸"
                    )
                )
            }
        }

        snapshot.dailyLogs.forEach { log ->
            val projectId = log.projectId?.takeIf(String::isNotBlank) ?: return@forEach
            val photoNames = buildList {
                log.photoFileName?.takeIf(String::isNotBlank)?.let(::add)
                log.photos.map { it.fileName }.filter(String::isNotBlank).forEach(::add)
            }.distinct()
            photoNames.forEach { fileName ->
                if (!archivedProjectPhotoFile(context, fileName).isFile) {
                    add(
                        LocalDataHealthFixTodo(
                            projectId = projectId,
                            title = "补齐施工日志缺失照片：${log.date.ifBlank { fileName }}",
                            note = listOf(
                                "数据体检发现施工日志照片缺失",
                                log.date.takeIf(String::isNotBlank),
                                fileName,
                                log.content.take(40).takeIf(String::isNotBlank)
                            ).filterNotNull().joinToString("；"),
                            issueType = "现场"
                        )
                    )
                }
            }
        }

        snapshot.siteTodos.forEach { todo ->
            val projectId = todo.projectId?.takeIf(String::isNotBlank) ?: return@forEach
            listOf(
                "整改前照片" to todo.rectificationBeforePhotoFileName,
                "整改后照片" to todo.rectificationAfterPhotoFileName
            ).forEach { (label, fileName) ->
                val normalizedFileName = fileName?.takeIf(String::isNotBlank) ?: return@forEach
                if (!archivedProjectPhotoFile(context, normalizedFileName).isFile) {
                    add(
                        LocalDataHealthFixTodo(
                            projectId = projectId,
                            title = "补齐${label}：${todo.title.ifBlank { normalizedFileName }}",
                            note = listOf(
                                "数据体检发现待办整改照片缺失",
                                label,
                                normalizedFileName,
                                todo.note.take(40).takeIf(String::isNotBlank)
                            ).filterNotNull().joinToString("；"),
                            issueType = todo.issueType.ifBlank { "现场" }
                        )
                    )
                }
            }
        }

        snapshot.quickNotes.forEach { note ->
            val projectId = note.projectId?.takeIf(String::isNotBlank) ?: return@forEach
            note.attachments.forEach { attachment ->
                if (
                    attachment.fileName.isNotBlank() &&
                    !archivedQuickNoteAttachmentFile(context, attachment.fileName).isFile
                ) {
                    val title = attachment.originalName
                        .ifBlank { attachment.fileName }
                    add(
                        LocalDataHealthFixTodo(
                            projectId = projectId,
                            title = "补齐随手记缺失附件：$title",
                            note = listOf(
                                "数据体检发现随手记附件缺失",
                                note.title.takeIf(String::isNotBlank),
                                attachment.fileName
                            ).filterNotNull().joinToString("；")
                        )
                    )
                }
            }
        }
    }
        .distinctBy { todo -> "${todo.projectId}|${todo.title}|${todo.note}" }

private fun orphanProjectDocumentFiles(
    context: Context,
    documentIds: Set<String>
): List<File> =
    projectDocumentArchiveRoot(context)
        .listFiles()
        ?.filter { file -> file.isDirectory && file.name !in documentIds }
        ?.flatMap { dir ->
            dir.walkTopDown()
                .filter { file -> file.isFile && file.canRead() }
                .toList()
        }
        .orEmpty()

private fun orphanFlatArchiveFiles(
    root: File,
    referencedFileNames: Set<String>
): List<File> =
    root
        .listFiles()
        ?.filter { file ->
            file.isFile &&
                file.canRead() &&
                file.name !in referencedFileNames
        }
        ?.sortedBy { it.name }
        .orEmpty()

private fun backupRecordCount(snapshot: BackupSnapshot): Int =
    snapshot.projects.size +
        snapshot.dailyLogs.size +
        snapshot.siteTodos.size +
        snapshot.projectFinancialRecords.size +
        snapshot.materialItems.size +
        snapshot.quickNotes.size +
        snapshot.projectContacts.size +
        snapshot.projectDocuments.size +
        snapshot.progressTasks.size +
        snapshot.projectDrawings.size +
        snapshot.quoteItems.size +
        snapshot.laborRecords.size +
        snapshot.projectWarehouseMovements.size +
        snapshot.materialPriceEntries.size +
        snapshot.supplierProfiles.size +
        snapshot.constructionMethods.size

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

internal data class DocumentFileInfo(
    val name: String,
    val type: String,
    val localUri: String
)

internal data class PhotoFileInfo(
    val name: String,
    val localUri: String
)

internal data class DrawingFileInfo(
    val name: String,
    val type: String,
    val localUri: String
)

internal data class QuickNoteAttachmentFileInfo(
    val name: String,
    val originalName: String,
    val kind: String
)

internal fun archiveDocumentFile(
    context: Context,
    sourceUri: Uri,
    documentId: String
): DocumentFileInfo {
    val name = queryDisplayName(context, sourceUri)
        .ifBlank { sourceUri.lastPathSegment.orEmpty() }
        .ifBlank { "document" }
    val mimeType = context.contentResolver.getType(sourceUri).orEmpty()
    val type = documentFileType(
        fileName = name,
        mimeType = mimeType
    )
    val archiveFile = copyDocumentToArchive(
        context = context,
        sourceUri = sourceUri,
        documentId = documentId,
        fileName = name
    )
    val archiveUri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        archiveFile
    )

    return DocumentFileInfo(
        name = name,
        type = type,
        localUri = archiveUri.toString()
    )
}

internal fun archivePhotoFile(
    context: Context,
    sourceUri: Uri
): PhotoFileInfo {
    val sourceName = queryDisplayName(context, sourceUri)
        .ifBlank { sourceUri.lastPathSegment.orEmpty() }
        .ifBlank { "photo.jpg" }
    val archiveFile = copyPhotoToArchive(
        context = context,
        sourceUri = sourceUri,
        fileName = sourceName
    )
    val archiveUri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        archiveFile
    )

    return PhotoFileInfo(
        name = archiveFile.name,
        localUri = archiveUri.toString()
    )
}

internal fun archiveDrawingFile(
    context: Context,
    sourceUri: Uri
): DrawingFileInfo {
    val sourceName = queryDisplayName(context, sourceUri)
        .ifBlank { sourceUri.lastPathSegment.orEmpty() }
        .ifBlank { "drawing" }
    val mimeType = context.contentResolver.getType(sourceUri).orEmpty()
    val archiveFile = copyDrawingToArchive(
        context = context,
        sourceUri = sourceUri,
        fileName = sourceName
    )
    val archiveUri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        archiveFile
    )

    return DrawingFileInfo(
        name = archiveFile.name,
        type = documentFileType(
            fileName = archiveFile.name,
            mimeType = mimeType
        ),
        localUri = archiveUri.toString()
    )
}

internal fun archiveQuickNoteAttachmentFile(
    context: Context,
    sourceUri: Uri
): QuickNoteAttachmentFileInfo {
    val sourceName = queryDisplayName(context, sourceUri)
        .ifBlank { sourceUri.lastPathSegment.orEmpty() }
        .ifBlank { "attachment" }
    val mimeType = context.contentResolver.getType(sourceUri).orEmpty()
    val archiveFile = copyQuickNoteAttachmentToArchive(
        context = context,
        sourceUri = sourceUri,
        fileName = sourceName
    )

    return QuickNoteAttachmentFileInfo(
        name = archiveFile.name,
        originalName = sourceName,
        kind = quickNoteAttachmentKind(
            fileName = archiveFile.name,
            mimeType = mimeType
        )
    )
}

private fun copyDocumentToArchive(
    context: Context,
    sourceUri: Uri,
    documentId: String,
    fileName: String
): File {
    val archiveDir = File(projectDocumentArchiveRoot(context), documentId)
    archiveDir.mkdirs()
    archiveDir.listFiles()?.forEach { file -> file.delete() }

    val archiveFile = File(archiveDir, safeArchiveFileName(fileName))
    context.contentResolver
        .openInputStream(sourceUri)
        ?.use { input ->
            archiveFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        ?: error("无法读取文件")

    return archiveFile
}

private fun copyQuickNoteAttachmentToArchive(
    context: Context,
    sourceUri: Uri,
    fileName: String
): File {
    val archiveDir = quickNoteAttachmentArchiveRoot(context)
    archiveDir.mkdirs()
    val archiveFile = uniqueArchiveFile(
        directory = archiveDir,
        fileName = fileName
    )
    context.contentResolver
        .openInputStream(sourceUri)
        ?.use { input ->
            archiveFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        ?: error("无法读取随手记附件")

    return archiveFile
}

private fun copyDrawingToArchive(
    context: Context,
    sourceUri: Uri,
    fileName: String
): File {
    val archiveDir = drawingArchiveRoot(context)
    archiveDir.mkdirs()
    val archiveFile = uniqueArchiveFile(
        directory = archiveDir,
        fileName = fileName
    )
    context.contentResolver
        .openInputStream(sourceUri)
        ?.use { input ->
            archiveFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        ?: error("无法读取图纸文件")

    return archiveFile
}

private fun copyPhotoToArchive(
    context: Context,
    sourceUri: Uri,
    fileName: String
): File {
    val archiveDir = photoArchiveRoot(context)
    archiveDir.mkdirs()
    val archiveFile = uniqueArchiveFile(
        directory = archiveDir,
        fileName = fileName
    )
    context.contentResolver
        .openInputStream(sourceUri)
        ?.use { input ->
            archiveFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        ?: error("无法读取照片")

    return archiveFile
}

private fun uniqueArchiveFile(
    directory: File,
    fileName: String
): File {
    val safeName = safeArchiveFileName(fileName)
    val baseName = safeName.substringBeforeLast('.', safeName)
    val extension = safeName.substringAfterLast('.', "")
    var candidate = File(directory, safeName)
    var index = 1
    while (candidate.exists()) {
        val indexedName = if (extension.isBlank()) {
            "$baseName-$index"
        } else {
            "$baseName-$index.$extension"
        }
        candidate = File(directory, indexedName.take(120))
        index += 1
    }
    return candidate
}

internal fun safeArchiveFileName(fileName: String): String {
    val normalizedName = fileName
        .trim()
        .replace(Regex("[/\\\\:\\n\\r\\t]"), "_")
        .ifBlank { "document" }
    return normalizedName.take(120)
}

private fun queryDisplayName(
    context: Context,
    uri: Uri
): String =
    context.contentResolver
        .query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )
        ?.use { cursor ->
            val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (columnIndex >= 0 && cursor.moveToFirst()) {
                cursor.getString(columnIndex).orEmpty()
            } else {
                ""
            }
        }
        .orEmpty()

internal fun documentFileType(
    fileName: String,
    mimeType: String
): String =
    fileName.substringAfterLast('.', "")
        .lowercase(Locale.ROOT)
        .ifBlank {
            mimeType.substringAfter('/', "")
                .substringBefore('+')
                .lowercase(Locale.ROOT)
        }
        .ifBlank { "file" }

private fun quickNoteAttachmentKind(
    fileName: String,
    mimeType: String
): String {
    val normalizedMime = mimeType.lowercase(Locale.ROOT)
    val extension = fileName.substringAfterLast('.', "").lowercase(Locale.ROOT)
    return when {
        normalizedMime.startsWith("image/") ||
            extension in setOf("jpg", "jpeg", "png", "heic", "webp", "gif") -> "photo"
        normalizedMime.startsWith("audio/") ||
            extension in setOf("m4a", "mp3", "wav", "aac", "ogg") -> "audio"
        normalizedMime.startsWith("video/") ||
            extension in setOf("mp4", "mov", "m4v", "avi") -> "video"
        else -> "file"
    }
}

private fun quickNoteAttachmentMimeType(fileName: String): String =
    when (quickNoteAttachmentKind(fileName = fileName, mimeType = "")) {
        "photo" -> "image/*"
        "audio" -> "audio/*"
        "video" -> "video/*"
        else -> "*/*"
    }

internal fun openLocalDocument(
    context: Context,
    localUri: String
) {
    val uri = runCatching { Uri.parse(localUri) }.getOrNull() ?: return
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, context.contentResolver.getType(uri) ?: "*/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No viewer installed for this file type.
    }
}

internal fun openLocalQuickNoteAttachment(
    context: Context,
    fileName: String
) {
    val file = File(quickNoteAttachmentArchiveRoot(context), safeArchiveFileName(fileName))
    if (!file.exists()) {
        return
    }
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, quickNoteAttachmentMimeType(file.name))
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No viewer installed for this attachment type.
    }
}

internal fun openLocalPhoto(
    context: Context,
    fileName: String
) {
    val file = File(photoArchiveRoot(context), safeArchiveFileName(fileName))
    if (!file.exists()) {
        return
    }
    val uri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "image/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No viewer installed for this image type.
    }
}

internal fun canOpenLocalPhoto(
    context: Context,
    fileName: String
): Boolean =
    File(photoArchiveRoot(context), safeArchiveFileName(fileName)).isFile

internal fun deletePhotoArchive(
    context: Context,
    fileName: String
): Boolean =
    File(photoArchiveRoot(context), safeArchiveFileName(fileName)).delete()

internal fun deleteDrawingArchive(
    context: Context,
    fileName: String
): Boolean =
    File(drawingArchiveRoot(context), safeArchiveFileName(fileName)).delete()

internal fun deleteQuickNoteAttachmentArchive(
    context: Context,
    fileName: String
): Boolean =
    File(quickNoteAttachmentArchiveRoot(context), safeArchiveFileName(fileName)).delete()

internal fun canOpenLocalDocument(
    context: Context,
    localUri: String
): Boolean {
    val uri = runCatching { Uri.parse(localUri) }.getOrNull() ?: return false
    return runCatching {
        context.contentResolver
            .openInputStream(uri)
            ?.use { true }
            ?: false
    }.getOrDefault(false)
}
