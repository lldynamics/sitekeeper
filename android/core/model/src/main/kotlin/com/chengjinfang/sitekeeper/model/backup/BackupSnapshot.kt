package com.chengjinfang.sitekeeper.model.backup

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

object BackupSnapshotJson {
    val format = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
    }

    fun decode(rawJson: String): BackupSnapshot =
        format.decodeFromString(BackupSnapshot.serializer(), rawJson)

    fun encode(snapshot: BackupSnapshot): String =
        format.encodeToString(snapshot)
}

@Serializable
data class BackupSnapshot(
    val schemaVersion: Int? = null,
    val exportedAt: String? = null,
    val exportPlatform: String? = null,
    val materialItems: List<MaterialItem> = emptyList(),
    val quoteItems: List<QuoteItem> = emptyList(),
    val laborRecords: List<LaborRecord> = emptyList(),
    val projects: List<Project> = emptyList(),
    val dailyLogs: List<DailyLog> = emptyList(),
    val historyRecords: List<JsonObject> = emptyList(),
    val progressTasks: List<ProgressTask> = emptyList(),
    val lightingCircuitPlans: List<JsonObject> = emptyList(),
    val siteTodos: List<SiteTodo> = emptyList(),
    @SerialName("paymentRecords") val legacyPaymentRecords: List<JsonObject> = emptyList(),
    val projectDrawings: List<ProjectDrawing> = emptyList(),
    val projectContacts: List<ProjectContact> = emptyList(),
    val projectFinancialRecords: List<ProjectFinancialRecord> = emptyList(),
    val projectDocuments: List<ProjectDocument> = emptyList(),
    val quickNotes: List<QuickNote> = emptyList(),
    val projectWarehouseMovements: List<JsonObject> = emptyList(),
    val templates: List<JsonObject> = emptyList(),
    val materialPriceEntries: List<JsonObject> = emptyList(),
    val materialSheetDrafts: List<JsonObject> = emptyList(),
    val supplierProfiles: List<JsonObject> = emptyList(),
    val constructionMethods: List<JsonObject> = emptyList(),
    val favoriteMaterialKeys: List<String> = emptyList(),
    val recentMaterialKeys: List<String> = emptyList(),
    val userMaterials: List<JsonObject> = emptyList(),
    val deletedUserMaterials: List<JsonObject> = emptyList(),
    val hiddenPresetKeys: List<String> = emptyList(),
    val photoFiles: List<JsonObject> = emptyList(),
    val drawingFiles: List<JsonObject> = emptyList(),
    val documentFiles: List<JsonObject> = emptyList(),
    val quickNoteAttachmentFiles: List<JsonObject> = emptyList()
)

@Serializable
data class Project(
    val id: String = "",
    val name: String = "",
    val location: String = "",
    val status: String = "进行中",
    val customerName: String = "",
    val customerPhone: String = "",
    val startDate: String = "",
    val expectedEndDate: String = "",
    val managerName: String = "",
    val contractAmount: String = "",
    val paidAmount: String = "",
    val paymentStatus: String = "未收款",
    val materialCost: String = "",
    val laborCost: String = "",
    val cadFontMappings: List<JsonObject> = emptyList()
)

@Serializable
data class DailyLog(
    val id: String = "",
    val date: String = "",
    val weather: String = "",
    val content: String = "",
    val workers: String = "",
    val photoFileName: String? = null,
    val photos: List<LogPhoto> = emptyList(),
    val safety: String = "",
    val materials: String = "",
    val tomorrowPlan: String = "",
    val qualityIssue: String = "",
    val rectification: String = "",
    val confirmer: String = "",
    val linkedConstructionMethodIDs: List<String> = emptyList(),
    val projectId: String? = null
)

@Serializable
data class LogPhoto(
    val id: String = "",
    val fileName: String = "",
    val note: String = "",
    val tag: String = "现场"
)

@Serializable
data class SiteTodo(
    val id: String = "",
    val title: String = "",
    val owner: String = "",
    val dueDate: String = "",
    val priority: String = "中",
    val issueType: String = "其他",
    val rectificationBeforePhotoFileName: String? = null,
    val rectificationAfterPhotoFileName: String? = null,
    val isDone: Boolean = false,
    val completedAt: String? = null,
    val note: String = "",
    val linkedConstructionMethodIDs: List<String> = emptyList(),
    val projectId: String? = null
)

@Serializable
data class ProgressTask(
    val id: String = "",
    val projectId: String = "",
    val title: String = "",
    val startDate: String = "",
    val dueDate: String = "",
    val completion: Double = 0.0,
    val note: String = ""
)

@Serializable
data class ProjectContact(
    val id: String = "",
    val projectId: String = "",
    val relatedProjectIds: List<String> = emptyList(),
    val name: String = "",
    val role: String = "业主",
    val company: String = "",
    val phone: String = "",
    val note: String = ""
)

@Serializable
data class ProjectDrawing(
    val id: String = "",
    val projectId: String = "",
    val name: String = "",
    val fileName: String = "",
    val fileType: String = "",
    val version: String = "V1",
    val isCurrentVersion: Boolean = true,
    val relatedLogDate: String = "",
    val issueStatus: String = "无问题",
    val issueNote: String = "",
    val textEncoding: String = "auto",
    val textBigFont: String = "auto",
    val textSchemeSnapshot: JsonObject = JsonObject(emptyMap()),
    val cadViewState: JsonObject = JsonObject(emptyMap()),
    val importedAt: String = "",
    val note: String = "",
    val cadOverlaySnapshotData: String = ""
)

@Serializable
data class ProjectDocument(
    val id: String = "",
    val projectId: String = "",
    val title: String = "",
    val category: String = "施工资料",
    val fileName: String = "",
    val fileType: String = "pdf",
    val pageCount: Int = 1,
    val amount: String = "",
    val linkedFinancialRecordId: String? = null,
    val linkedConstructionMethodIDs: List<String> = emptyList(),
    val createdAt: String = "",
    val note: String = ""
)

@Serializable
data class ProjectFinancialRecord(
    val id: String = "",
    val projectId: String = "",
    val date: String = "",
    val direction: String = "支出",
    val category: String = "材料",
    val amount: String = "",
    val counterparty: String = "",
    val invoiceNumber: String = "",
    val linkedDocumentIds: List<String> = emptyList(),
    @SerialName("linkedDocumentId") val legacyLinkedDocumentId: String? = null,
    val status: String = "正式",
    val dueDate: String = "",
    val reminderStatus: String = "不提醒",
    val note: String = ""
) {
    val normalizedLinkedDocumentIds: List<String>
        get() = if (linkedDocumentIds.isNotEmpty()) {
            linkedDocumentIds
        } else {
            listOfNotNull(legacyLinkedDocumentId)
        }
}

@Serializable
data class MaterialItem(
    val id: String = "",
    val name: String = "",
    val quantity: String = "",
    val unit: String = "",
    val unitPrice: String = "",
    val specification: String = "",
    val brand: String = "",
    val supplier: String = "",
    val purchaseStatus: String = "未采购",
    val arrivalDate: String = "",
    val projectId: String? = null
)

@Serializable
data class QuoteItem(
    val id: String = "",
    val name: String = "",
    val unitPrice: String = "",
    val quantity: String = "",
    val unit: String = "",
    val notes: String = "",
    val taxRate: String = "0",
    val discountRate: String = "0",
    val versionName: String = "V1",
    val status: String = "草稿",
    val customerConfirmedDate: String = "",
    val contractAmount: String = "",
    val projectId: String? = null
)

@Serializable
data class LaborRecord(
    val id: String = "",
    val date: String = "",
    val workers: String = "",
    val hours: String = "",
    val unitRate: String = "",
    val workType: String = "",
    val teamName: String = "",
    val isSettled: Boolean = false,
    val note: String = "",
    val projectId: String? = null
)

@Serializable
data class QuickNote(
    val id: String = "",
    val title: String = "",
    val content: String = "",
    val projectId: String? = null,
    val createdAt: String = "",
    val updatedAt: String = "",
    val attachments: List<QuickNoteAttachment> = emptyList()
)

@Serializable
data class QuickNoteAttachment(
    val id: String = "",
    val kind: String = "photo",
    val fileName: String = "",
    val originalName: String = "",
    val createdAt: String = "",
    val durationSeconds: Double? = null
)
