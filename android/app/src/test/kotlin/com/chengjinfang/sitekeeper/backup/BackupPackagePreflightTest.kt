package com.chengjinfang.sitekeeper.backup

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BackupPackagePreflightTest {
    @Test
    fun cleanPackageHasNoPreflightWarnings() {
        val preflight = backupImportPreflight(
            rawJson = backupJson("doc-1", "doc-2"),
            attachmentCountsByDocumentId = mapOf(
                "doc-1" to 1,
                "doc-2" to 1
            ),
            invalidAttachmentCount = 0,
            duplicateEntryCount = 0,
            isZipPackage = true
        )

        assertTrue(preflight.warnings.isEmpty())
        assertEquals(setOf("doc-1", "doc-2"), preflight.restorableDocumentIds)
    }

    @Test
    fun mismatchedPackageReportsSpecificWarnings() {
        val preflight = backupImportPreflight(
            rawJson = backupJson("doc-1", "doc-2", "doc-3"),
            attachmentCountsByDocumentId = mapOf(
                "doc-1" to 1,
                "doc-2" to 2,
                "ghost-doc" to 1
            ),
            invalidAttachmentCount = 1,
            duplicateEntryCount = 1,
            isZipPackage = true
        )

        assertEquals(setOf("doc-1", "doc-2"), preflight.restorableDocumentIds)
        assertTrue(preflight.warnings.any { it.contains("1 个附件路径不符合备份包结构") })
        assertTrue(preflight.warnings.any { it.contains("1 个重复附件条目") })
        assertTrue(preflight.warnings.any { it.contains("1 个附件没有匹配的资料记录") })
        assertTrue(preflight.warnings.any { it.contains("1 条资料记录带有多个附件") })
        assertTrue(preflight.warnings.any { it.contains("1 条资料记录没有随包附件") })
    }

    @Test
    fun photoPackageReportsRestorableAndMissingFiles() {
        val preflight = backupImportPreflight(
            rawJson = """{"dailyLogs":[{"photos":[{"fileName":"site-1.jpg"}]}],"siteTodos":[{"rectificationBeforePhotoFileName":"before-1.jpg"}]}""",
            attachmentCountsByDocumentId = emptyMap(),
            invalidAttachmentCount = 0,
            duplicateEntryCount = 0,
            isZipPackage = true,
            incomingPhotoFileNames = setOf("site-1.jpg", "ghost.jpg")
        )

        assertEquals(setOf("site-1.jpg"), preflight.restorablePhotoFileNames)
        assertTrue(preflight.warnings.any { it.contains("1 个照片文件没有匹配") })
        assertTrue(preflight.warnings.any { it.contains("1 个照片引用没有随包文件") })
    }

    @Test
    fun drawingPackageReportsRestorableAndMissingFiles() {
        val preflight = backupImportPreflight(
            rawJson = """{"projectDrawings":[{"id":"drawing-1","fileName":"floor.dwg"},{"id":"drawing-2","fileName":"ceiling.pdf"}]}""",
            attachmentCountsByDocumentId = emptyMap(),
            invalidAttachmentCount = 0,
            duplicateEntryCount = 0,
            isZipPackage = true,
            incomingDrawingFileNames = setOf("floor.dwg", "ghost.dwg")
        )

        assertEquals(mapOf("floor.dwg" to "drawing-1"), preflight.restorableDrawingIdsByFileName)
        assertTrue(preflight.warnings.any { it.contains("1 个图纸文件没有匹配") })
        assertTrue(preflight.warnings.any { it.contains("1 个图纸引用没有随包文件") })
    }

    @Test
    fun quickNoteAttachmentPackageReportsRestorableAndMissingFiles() {
        val preflight = backupImportPreflight(
            rawJson = """{"quickNotes":[{"id":"note-1","attachments":[{"fileName":"note-photo.jpg"},{"fileName":"voice.m4a"}]}]}""",
            attachmentCountsByDocumentId = emptyMap(),
            invalidAttachmentCount = 0,
            duplicateEntryCount = 0,
            isZipPackage = true,
            incomingQuickNoteAttachmentFileNames = setOf("note-photo.jpg", "ghost.jpg")
        )

        assertEquals(setOf("note-photo.jpg"), preflight.restorableQuickNoteAttachmentFileNames)
        assertTrue(preflight.warnings.any { it.contains("1 个随手记附件文件没有匹配") })
        assertTrue(preflight.warnings.any { it.contains("1 个随手记附件引用没有随包文件") })
    }

    @Test
    fun cleanQuickNoteAttachmentPackageHasNoPreflightWarnings() {
        val preflight = backupImportPreflight(
            rawJson = quickNoteBackupJson("note-photo.jpg", "voice.m4a"),
            attachmentCountsByDocumentId = emptyMap(),
            invalidAttachmentCount = 0,
            duplicateEntryCount = 0,
            isZipPackage = true,
            incomingQuickNoteAttachmentFileNames = setOf("note-photo.jpg", "voice.m4a")
        )

        assertTrue(preflight.warnings.isEmpty())
        assertEquals(
            setOf("note-photo.jpg", "voice.m4a"),
            preflight.restorableQuickNoteAttachmentFileNames
        )
    }

    @Test
    fun legacyJsonWarnsWhenQuickNoteMetadataHasNoPackageFiles() {
        assertEquals(
            listOf("旧 JSON 不包含随手记附件文件，随手记附件导入后需要重新选择文件"),
            legacyJsonImportWarnings(quickNoteBackupJson("note-photo.jpg"))
        )
    }

    @Test
    fun legacyJsonWarnsWhenDocumentMetadataHasNoPackageFiles() {
        assertEquals(
            listOf("旧 JSON 不包含资料附件，资料记录导入后需要重新选择文件"),
            legacyJsonImportWarnings(backupJson("doc-1"))
        )
        assertTrue(legacyJsonImportWarnings(backupJson()).isEmpty())
    }

    private fun backupJson(vararg documentIds: String): String {
        val documents = documentIds.joinToString(",") { id ->
            """{"id":"$id"}"""
        }
        return """{"projectDocuments":[$documents]}"""
    }

    private fun quickNoteBackupJson(vararg fileNames: String): String {
        val attachments = fileNames.joinToString(",") { fileName ->
            """{"fileName":"$fileName"}"""
        }
        return """{"quickNotes":[{"id":"note-1","attachments":[$attachments]}]}"""
    }
}
