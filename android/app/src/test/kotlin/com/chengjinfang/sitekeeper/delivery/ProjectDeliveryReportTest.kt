package com.chengjinfang.sitekeeper.delivery

import com.chengjinfang.sitekeeper.database.contact.ProjectContactSummary
import com.chengjinfang.sitekeeper.database.document.ProjectDocumentSummary
import com.chengjinfang.sitekeeper.database.drawing.ProjectDrawingSummary
import com.chengjinfang.sitekeeper.database.finance.ProjectFinancialRecordSummary
import com.chengjinfang.sitekeeper.database.labor.LaborRecordSummary
import com.chengjinfang.sitekeeper.database.material.MaterialItemSummary
import com.chengjinfang.sitekeeper.database.method.ConstructionMethodSummary
import com.chengjinfang.sitekeeper.database.progress.ProgressTaskSummary
import com.chengjinfang.sitekeeper.database.project.ProjectDetail
import com.chengjinfang.sitekeeper.database.project.ProjectSummary
import com.chengjinfang.sitekeeper.database.quote.QuoteItemSummary
import com.chengjinfang.sitekeeper.database.record.DailyLogSummary
import com.chengjinfang.sitekeeper.database.record.SiteTodoSummary
import com.chengjinfang.sitekeeper.database.warehouse.ProjectWarehouseMovementSummary
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ProjectDeliveryReportTest {
    @Test
    fun defaultProjectDeliveryFileNameSanitizesProjectName() {
        assertEquals(
            "华庭-一标段-交付报告-20260517-0100.md",
            defaultProjectDeliveryFileName(" 华庭/一标段 ", "20260517-0100")
        )
        assertEquals(
            "sitekeeper-project-交付报告-20260517-0100.md",
            defaultProjectDeliveryFileName("   ", "20260517-0100")
        )
        assertEquals(
            "华庭-一标段-交付包-20260517-0100.zip",
            defaultProjectDeliveryPackageFileName(" 华庭/一标段 ", "20260517-0100")
        )
    }

    @Test
    fun buildProjectDeliveryMarkdownIncludesProjectRiskTimelineAndAssets() {
        val report = buildProjectDeliveryMarkdown(
            detail = sampleProjectDetail(),
            exportedAt = "2026-05-17 01:00"
        )

        assertTrue(report.contains("# 项目交付报告"))
        assertTrue(report.contains("## 项目概况"))
        assertTrue(report.contains("项目名称：华庭精装"))
        assertTrue(report.contains("风险提示：逾期待办 1 项；到期待收 2 项；未到货材料 3 项"))
        assertTrue(report.contains("资料附件：1/1 份"))
        assertTrue(report.contains("图纸附件：1/1 份"))
        assertTrue(report.contains("现场照片：2 张"))
        assertTrue(report.contains("工艺：墙地砖铺贴"))
        assertTrue(report.contains("## 关键时间线"))
        assertTrue(report.contains("## 仓库流水"))
        assertTrue(report.contains("入库 水泥"))
    }

    @Test
    fun buildProjectDeliveryPackageManifestShowsCountsAndMissingFiles() {
        val manifest = buildProjectDeliveryPackageManifest(
            detail = sampleProjectDetail(),
            result = ProjectDeliveryPackageExportResult(
                documentFileCount = 1,
                drawingFileCount = 1,
                photoFileCount = 2,
                missingFileCount = 1
            ),
            exportedFiles = listOf(
                "项目资料/签证/material.pdf",
                "项目图纸/plan.dwg"
            ),
            missingFiles = listOf("照片：missing.jpg")
        )

        assertTrue(manifest.contains("# 项目交付包文件清单"))
        assertTrue(manifest.contains("项目名称：华庭精装"))
        assertTrue(manifest.contains("资料文件：1"))
        assertTrue(manifest.contains("现场照片：2"))
        assertTrue(manifest.contains("项目资料/签证/material.pdf"))
        assertTrue(manifest.contains("照片：missing.jpg"))
    }

    private fun sampleProjectDetail(): ProjectDetail =
        ProjectDetail(
            project = ProjectSummary(
                id = "p1",
                name = "华庭精装",
                location = "A座 12层",
                status = "施工中",
                managerName = "王工",
                expectedEndDate = "2026-06-01",
                contractAmount = "120000",
                paidAmount = "60000",
                paymentStatus = "部分收款",
                overdueTodoCount = 1,
                dueIncomeCount = 2,
                unarrivedMaterialCount = 3
            ),
            dailyLogs = listOf(
                DailyLogSummary(
                    id = "log1",
                    date = "2026-05-16",
                    weather = "晴",
                    content = "铺贴样板间",
                    workers = "6",
                    safety = "正常",
                    materials = "瓷砖",
                    tomorrowPlan = "闭水检查",
                    photoFileNames = listOf("site.jpg"),
                    linkedConstructionMethodIds = listOf("method-tile")
                )
            ),
            siteTodos = listOf(
                SiteTodoSummary(
                    id = "todo1",
                    title = "补齐阳角保护",
                    owner = "李工",
                    dueDate = "2026-05-18",
                    priority = "高",
                    issueType = "质量",
                    isDone = false,
                    note = "交付前完成",
                    rectificationBeforePhotoFileName = "before.jpg",
                    rectificationAfterPhotoFileName = null,
                    linkedConstructionMethodIds = listOf("method-tile")
                )
            ),
            financialRecords = listOf(
                ProjectFinancialRecordSummary(
                    id = "finance1",
                    date = "2026-05-10",
                    direction = "收入",
                    category = "进度款",
                    amount = "30000",
                    counterparty = "业主",
                    status = "待收",
                    dueDate = "2026-05-20",
                    note = "二期"
                )
            ),
            materialItems = listOf(
                MaterialItemSummary(
                    id = "material1",
                    name = "瓷砖",
                    quantity = "100",
                    unit = "片",
                    unitPrice = "35",
                    specification = "600x600",
                    supplier = "材料商",
                    purchaseStatus = "已到货",
                    arrivalDate = "2026-05-09"
                )
            ),
            progressTasks = listOf(
                ProgressTaskSummary(
                    id = "progress1",
                    title = "泥工完成",
                    startDate = "2026-05-01",
                    dueDate = "2026-05-25",
                    completion = 0.8,
                    note = "客厅已完成"
                )
            ),
            contacts = listOf(
                ProjectContactSummary(
                    id = "contact1",
                    projectId = "p1",
                    name = "张三",
                    role = "业主",
                    company = "",
                    phone = "13800000000",
                    note = ""
                )
            ),
            documents = listOf(
                ProjectDocumentSummary(
                    id = "doc1",
                    projectId = "p1",
                    title = "主材确认单",
                    category = "签证",
                    fileName = "material.pdf",
                    fileType = "PDF",
                    pageCount = 2,
                    amount = "3500",
                    createdAt = "2026-05-11",
                    note = "已签字",
                    localUri = "content://doc/material",
                    linkedConstructionMethodIds = listOf("method-tile")
                )
            ),
            drawings = listOf(
                ProjectDrawingSummary(
                    id = "drawing1",
                    projectId = "p1",
                    name = "平面布置图",
                    fileName = "plan.dwg",
                    fileType = "DWG",
                    version = "V2",
                    isCurrentVersion = true,
                    relatedLogDate = "2026-05-12",
                    issueStatus = "已下发",
                    issueNote = "",
                    importedAt = "2026-05-12",
                    note = "",
                    localUri = "content://drawing/plan"
                )
            ),
            quoteItems = listOf(
                QuoteItemSummary(
                    id = "quote1",
                    name = "墙砖铺贴",
                    unitPrice = "45",
                    quantity = "80",
                    unit = "m2",
                    notes = "含辅材",
                    versionName = "V1",
                    status = "已确认",
                    customerConfirmedDate = "2026-05-08",
                    contractAmount = "3600"
                )
            ),
            laborRecords = listOf(
                LaborRecordSummary(
                    id = "labor1",
                    date = "2026-05-15",
                    workers = "3",
                    hours = "2",
                    unitRate = "350",
                    workType = "泥工",
                    teamName = "李班组",
                    isSettled = false,
                    note = ""
                )
            ),
            warehouseMovements = listOf(
                ProjectWarehouseMovementSummary(
                    id = "warehouse1",
                    date = "2026-05-13",
                    movementType = "入库",
                    materialName = "水泥",
                    specification = "P.O 42.5",
                    unit = "袋",
                    quantity = "20",
                    counterparty = "材料商",
                    handler = "王工",
                    note = "",
                    linkedDocumentCount = 1,
                    createdAt = "2026-05-13"
                )
            ),
            constructionMethods = listOf(
                ConstructionMethodSummary(
                    id = "method-tile",
                    title = "墙地砖铺贴",
                    trade = "泥工",
                    versionName = "V1",
                    publishStatus = "已发布",
                    tutorialBody = "基层处理",
                    tutorialAttachmentCount = 0,
                    procedureSteps = listOf("找平", "铺贴"),
                    qualityChecklist = listOf("空鼓检查"),
                    safetyChecklist = listOf("切割防护"),
                    attachmentCount = 0,
                    updatedAt = "2026-05-01"
                )
            )
        )
}
