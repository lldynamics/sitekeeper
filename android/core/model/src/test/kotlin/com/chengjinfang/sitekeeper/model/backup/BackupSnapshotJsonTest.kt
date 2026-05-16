package com.chengjinfang.sitekeeper.model.backup

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BackupSnapshotJsonTest {
    @Test
    fun decodesIosP0Snapshot() {
        val snapshot = BackupSnapshotJson.decode(resourceText("backup/p0-ios-snapshot.json"))

        assertEquals(1, snapshot.schemaVersion)
        assertEquals("ios-fixture", snapshot.exportPlatform)
        assertEquals("project-001", snapshot.projects.single().id)
        assertEquals("进行中", snapshot.projects.single().status)
        assertEquals("部分收款", snapshot.projects.single().paymentStatus)
        assertEquals("118000", snapshot.projects.single().contractAmount)
        assertEquals("site-photo-001.jpg", snapshot.dailyLogs.single().photos.single().fileName)
        assertEquals("method-001", snapshot.dailyLogs.single().linkedConstructionMethodIDs.single())
        assertEquals("高", snapshot.siteTodos.single().priority)
        assertEquals("质量", snapshot.siteTodos.single().issueType)
        assertEquals("method-001", snapshot.siteTodos.single().linkedConstructionMethodIDs.single())
        assertEquals("todo-before-001.jpg", snapshot.siteTodos.single().rectificationBeforePhotoFileName)
        assertEquals("桥架安装", snapshot.progressTasks.single().title)
        assertEquals(0.65, snapshot.progressTasks.single().completion)
        assertEquals("二层电气平面图", snapshot.projectDrawings.single().name)
        assertEquals("pdf", snapshot.projectDrawings.single().fileType)
        assertEquals("method-001", snapshot.projectDocuments.single().linkedConstructionMethodIDs.single())
        assertEquals("收入", snapshot.projectFinancialRecords.single().direction)
        assertEquals("42000", snapshot.projectFinancialRecords.single().amount)
        assertEquals("已进场", snapshot.materialItems.single().purchaseStatus)
        assertEquals("桥架安装", snapshot.quoteItems.single().name)
        assertEquals("电工", snapshot.laborRecords.single().workType)
        assertEquals("入库", snapshot.projectWarehouseMovements.single().movementType)
        assertEquals("热镀锌桥架", snapshot.projectWarehouseMovements.single().materialName)
        assertEquals("热镀锌桥架", snapshot.materialPriceEntries.single().name)
        assertEquals("45", snapshot.materialPriceEntries.single().referencePrice)
        assertEquals("城东建材", snapshot.supplierProfiles.single().name)
        assertEquals("张经理", snapshot.supplierProfiles.single().contact)
        assertEquals("桥架安装工艺", snapshot.constructionMethods.single().title)
        assertEquals("已发布", snapshot.constructionMethods.single().publishStatus)
        assertEquals("弹线定位", snapshot.constructionMethods.single().normalizedProcedureSteps[1])
        assertEquals("confirmed-document-001", snapshot.projectFinancialRecords.single().normalizedLinkedDocumentIds.single())
        assertEquals("note-photo-001.jpg", snapshot.quickNotes.single().attachments.single().fileName)
    }

    @Test
    fun decodesMissingCollectionsAsEmpty() {
        val snapshot = BackupSnapshotJson.decode(
            """
            {
              "schemaVersion": 1,
              "unknownTopLevel": "ignored"
            }
            """.trimIndent()
        )

        assertTrue(snapshot.projects.isEmpty())
        assertTrue(snapshot.dailyLogs.isEmpty())
        assertTrue(snapshot.projectFinancialRecords.isEmpty())
    }

    @Test
    fun reencodesCoreFieldsWithoutChangingRawValues() {
        val original = BackupSnapshotJson.decode(resourceText("backup/p0-ios-snapshot.json"))
        val roundTrip = BackupSnapshotJson.decode(BackupSnapshotJson.encode(original))

        assertEquals(original.projects.single().id, roundTrip.projects.single().id)
        assertEquals(original.projects.single().status, roundTrip.projects.single().status)
        assertEquals(original.projects.single().contractAmount, roundTrip.projects.single().contractAmount)
        assertEquals(original.dailyLogs.single().date, roundTrip.dailyLogs.single().date)
        assertEquals(original.dailyLogs.single().photos.single().fileName, roundTrip.dailyLogs.single().photos.single().fileName)
        assertEquals(original.dailyLogs.single().linkedConstructionMethodIDs, roundTrip.dailyLogs.single().linkedConstructionMethodIDs)
        assertEquals(original.siteTodos.single().rectificationBeforePhotoFileName, roundTrip.siteTodos.single().rectificationBeforePhotoFileName)
        assertEquals(original.siteTodos.single().linkedConstructionMethodIDs, roundTrip.siteTodos.single().linkedConstructionMethodIDs)
        assertEquals(original.projectDocuments.single().linkedConstructionMethodIDs, roundTrip.projectDocuments.single().linkedConstructionMethodIDs)
        assertEquals(original.quoteItems.single().status, roundTrip.quoteItems.single().status)
        assertEquals(original.laborRecords.single().hours, roundTrip.laborRecords.single().hours)
        assertEquals(original.projectWarehouseMovements.single().linkedDocumentIds, roundTrip.projectWarehouseMovements.single().linkedDocumentIds)
        assertEquals(original.materialPriceEntries.single().supplier, roundTrip.materialPriceEntries.single().supplier)
        assertEquals(original.supplierProfiles.single().phone, roundTrip.supplierProfiles.single().phone)
        assertEquals(original.constructionMethods.single().qualityChecklist, roundTrip.constructionMethods.single().qualityChecklist)
        assertEquals(original.projectDrawings.single().issueStatus, roundTrip.projectDrawings.single().issueStatus)
        assertEquals(original.quickNotes.single().attachments.single().originalName, roundTrip.quickNotes.single().attachments.single().originalName)
    }

    private fun resourceText(path: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream(path)) {
            "Missing test resource: $path"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
