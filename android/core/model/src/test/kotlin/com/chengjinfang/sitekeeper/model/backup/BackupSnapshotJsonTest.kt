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
        assertEquals("高", snapshot.siteTodos.single().priority)
        assertEquals("质量", snapshot.siteTodos.single().issueType)
        assertEquals("收入", snapshot.projectFinancialRecords.single().direction)
        assertEquals("42000", snapshot.projectFinancialRecords.single().amount)
        assertEquals("已进场", snapshot.materialItems.single().purchaseStatus)
        assertEquals("confirmed-document-001", snapshot.projectFinancialRecords.single().normalizedLinkedDocumentIds.single())
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
        assertEquals(original.quoteItems.single().status, roundTrip.quoteItems.single().status)
        assertEquals(original.laborRecords.single().hours, roundTrip.laborRecords.single().hours)
    }

    private fun resourceText(path: String): String {
        val stream = checkNotNull(javaClass.classLoader?.getResourceAsStream(path)) {
            "Missing test resource: $path"
        }
        return stream.bufferedReader().use { it.readText() }
    }
}
