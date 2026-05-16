package com.chengjinfang.sitekeeper.delivery

import android.content.Context
import android.net.Uri
import com.chengjinfang.sitekeeper.backup.archivedProjectDocumentFiles
import com.chengjinfang.sitekeeper.backup.archivedProjectDrawingFile
import com.chengjinfang.sitekeeper.backup.archivedProjectPhotoFile
import com.chengjinfang.sitekeeper.backup.safeArchiveFileName
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal fun defaultProjectDeliveryPackageFileName(
    projectName: String,
    timestamp: String = SimpleDateFormat("yyyyMMdd-HHmm", Locale.US).format(Date())
): String =
    "${safeProjectFileName(projectName)}-交付包-$timestamp.zip"

internal data class ProjectDeliveryPackageExportResult(
    val documentFileCount: Int,
    val drawingFileCount: Int,
    val photoFileCount: Int,
    val missingFileCount: Int
)

internal suspend fun writeProjectDeliveryPackageToUri(
    context: Context,
    uri: Uri,
    detail: ProjectDetail
): ProjectDeliveryPackageExportResult =
    withContext(Dispatchers.IO) {
        val filePlan = projectDeliveryPackageFilePlan(
            context = context,
            detail = detail
        )
        val result = ProjectDeliveryPackageExportResult(
            documentFileCount = filePlan.files.count { it.kind == DeliveryPackageFileKind.Document },
            drawingFileCount = filePlan.files.count { it.kind == DeliveryPackageFileKind.Drawing },
            photoFileCount = filePlan.files.count { it.kind == DeliveryPackageFileKind.Photo },
            missingFileCount = filePlan.missingFiles.size
        )
        val usedEntryNames = mutableSetOf<String>()
        val reportEntryName = uniqueZipEntryName("交付报告.md", usedEntryNames)
        val manifestEntryName = uniqueZipEntryName("文件清单.md", usedEntryNames)
        val resolvedFiles = filePlan.files.map { entry ->
            entry.copy(entryName = uniqueZipEntryName(entry.entryName, usedEntryNames))
        }
        val report = buildProjectDeliveryMarkdown(detail)
        val manifest = buildProjectDeliveryPackageManifest(
            detail = detail,
            result = result,
            exportedFiles = resolvedFiles.map { it.entryName },
            missingFiles = filePlan.missingFiles
        )

        context.contentResolver
            .openOutputStream(uri)
            ?.use { rawOutput ->
                ZipOutputStream(BufferedOutputStream(rawOutput)).use { zip ->
                    zip.writeTextEntry(
                        entryName = reportEntryName,
                        text = report
                    )
                    zip.writeTextEntry(
                        entryName = manifestEntryName,
                        text = manifest
                    )
                    resolvedFiles.forEach { entry ->
                        zip.writeFileEntry(
                            entryName = entry.entryName,
                            file = entry.file
                        )
                    }
                }
            }
            ?: error("无法写入交付包")

        result
    }

internal fun buildProjectDeliveryPackageManifest(
    detail: ProjectDetail,
    result: ProjectDeliveryPackageExportResult,
    exportedFiles: List<String>,
    missingFiles: List<String>
): String =
    buildString {
        appendLine("# 项目交付包文件清单")
        appendLine()
        appendLine("- 项目名称：${detail.project.name.ifBlank { "-" }}")
        appendLine("- 资料文件：${result.documentFileCount}")
        appendLine("- 图纸文件：${result.drawingFileCount}")
        appendLine("- 现场照片：${result.photoFileCount}")
        appendLine("- 缺失文件：${result.missingFileCount}")
        appendLine()
        appendLine("## 已打包文件")
        if (exportedFiles.isEmpty()) {
            appendLine("- 暂无原文件")
        } else {
            exportedFiles.sorted().forEach { entryName ->
                appendLine("- $entryName")
            }
        }
        appendLine()
        appendLine("## 缺失文件")
        if (missingFiles.isEmpty()) {
            appendLine("- 无")
        } else {
            missingFiles.sorted().forEach { fileName ->
                appendLine("- $fileName")
            }
        }
    }

private data class ProjectDeliveryPackageFilePlan(
    val files: List<ProjectDeliveryPackageFile>,
    val missingFiles: List<String>
)

private data class ProjectDeliveryPackageFile(
    val kind: DeliveryPackageFileKind,
    val entryName: String,
    val file: File
)

private enum class DeliveryPackageFileKind {
    Document,
    Drawing,
    Photo
}

private fun projectDeliveryPackageFilePlan(
    context: Context,
    detail: ProjectDetail
): ProjectDeliveryPackageFilePlan {
    val files = mutableListOf<ProjectDeliveryPackageFile>()
    val missingFiles = mutableListOf<String>()

    detail.documents.forEach { document ->
        val documentFiles = archivedProjectDocumentFiles(
            context = context,
            documentId = document.id
        )
        if (documentFiles.isEmpty()) {
            if (document.localUri.isNotBlank()) {
                missingFiles += "资料：${document.title.ifBlank { document.fileName.ifBlank { document.id } }}"
            }
        } else {
            documentFiles.forEach { file ->
                files += ProjectDeliveryPackageFile(
                    kind = DeliveryPackageFileKind.Document,
                    entryName = listOf(
                        "项目资料",
                        document.category.ifBlank { "未分类" },
                        "${document.title.ifBlank { document.id }}-${file.name}"
                    ).joinToString("/"),
                    file = file
                )
            }
        }
    }

    detail.drawings.forEach { drawing ->
        val fileName = drawing.fileName
        if (fileName.isBlank()) {
            return@forEach
        }
        val file = archivedProjectDrawingFile(context, fileName)
        if (file.isFile && file.canRead()) {
            files += ProjectDeliveryPackageFile(
                kind = DeliveryPackageFileKind.Drawing,
                entryName = listOf(
                    "项目图纸",
                    "${drawing.name.ifBlank { drawing.id }}-${file.name}"
                ).joinToString("/"),
                file = file
            )
        } else if (drawing.localUri.isNotBlank()) {
            missingFiles += "图纸：${drawing.name.ifBlank { fileName }}"
        }
    }

    projectPhotoFileNames(detail).forEach { fileName ->
        val file = archivedProjectPhotoFile(context, fileName)
        if (file.isFile && file.canRead()) {
            files += ProjectDeliveryPackageFile(
                kind = DeliveryPackageFileKind.Photo,
                entryName = listOf(
                    "现场照片",
                    file.name
                ).joinToString("/"),
                file = file
            )
        } else {
            missingFiles += "照片：$fileName"
        }
    }

    return ProjectDeliveryPackageFilePlan(
        files = files,
        missingFiles = missingFiles.distinct()
    )
}

private fun projectPhotoFileNames(detail: ProjectDetail): List<String> =
    buildList {
        detail.dailyLogs.flatMap { it.photoFileNames }.forEach(::add)
        detail.siteTodos.forEach { todo ->
            todo.rectificationBeforePhotoFileName
                ?.takeIf(String::isNotBlank)
                ?.let(::add)
            todo.rectificationAfterPhotoFileName
                ?.takeIf(String::isNotBlank)
                ?.let(::add)
        }
    }
        .map { safeArchiveFileName(it) }
        .filter(String::isNotBlank)
        .distinct()
        .sorted()

private fun ZipOutputStream.writeTextEntry(
    entryName: String,
    text: String
) {
    putNextEntry(ZipEntry(entryName))
    write(text.toByteArray(Charsets.UTF_8))
    closeEntry()
}

private fun ZipOutputStream.writeFileEntry(
    entryName: String,
    file: File
) {
    putNextEntry(ZipEntry(entryName))
    file.inputStream().use { input ->
        input.copyTo(this)
    }
    closeEntry()
}

private fun uniqueZipEntryName(
    rawEntryName: String,
    usedEntryNames: MutableSet<String>
): String {
    val normalized = rawEntryName
        .split("/")
        .map { safePackagePathSegment(it) }
        .filter(String::isNotBlank)
        .joinToString("/")
        .ifBlank { "file" }
    if (usedEntryNames.add(normalized)) {
        return normalized
    }

    val directory = normalized.substringBeforeLast("/", "")
    val fileName = normalized.substringAfterLast("/")
    val baseName = fileName.substringBeforeLast('.', fileName)
    val extension = fileName.substringAfterLast('.', "")
    var index = 1
    while (true) {
        val indexedFileName = if (extension.isBlank()) {
            "$baseName-$index"
        } else {
            "$baseName-$index.$extension"
        }
        val candidate = listOf(directory, indexedFileName)
            .filter(String::isNotBlank)
            .joinToString("/")
        if (usedEntryNames.add(candidate)) {
            return candidate
        }
        index += 1
    }
}

private fun safePackagePathSegment(value: String): String =
    safeArchiveFileName(value)
        .replace(Regex("\\s+"), " ")
        .trim()
        .ifBlank { "未命名" }
