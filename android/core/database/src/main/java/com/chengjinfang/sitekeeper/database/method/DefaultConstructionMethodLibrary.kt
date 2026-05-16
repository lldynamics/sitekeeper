package com.chengjinfang.sitekeeper.database.method

import com.chengjinfang.sitekeeper.model.backup.BackupSnapshotJson

object DefaultConstructionMethodLibrary {
    private const val UPDATED_AT = "2026-05-17T00:00:00+0800"

    val methods: List<ConstructionMethodEntity> = listOf(
        method(
            id = "method-cable-tray-install",
            title = "桥架安装工艺",
            trade = "电气",
            publishStatus = "已发布",
            tutorialBody = "适用于强弱电桥架安装。现场先复核图纸标高、走向和支吊架间距，再按样板段确认后展开。",
            procedureSteps = listOf(
                "复核图纸、综合管线和现场标高",
                "弹线定位，确认支吊架间距和转角做法",
                "安装支吊架并复核水平度",
                "分段安装桥架，连接片和跨接线同步完成",
                "转弯、变径、穿墙处补齐防火封堵和标识"
            ),
            qualityChecklist = listOf(
                "桥架水平顺直，转角过渡自然",
                "支吊架间距符合方案要求",
                "跨接接地连续可靠",
                "盖板、螺栓、封堵齐全"
            ),
            safetyChecklist = listOf(
                "高处作业系好安全带",
                "切割打磨佩戴护目镜",
                "临边和洞口区域先确认防护"
            )
        ),
        method(
            id = "method-wire-pulling",
            title = "管内穿线工艺",
            trade = "电气",
            publishStatus = "已发布",
            tutorialBody = "适用于照明、插座和控制线路管内穿线。穿线前必须确认管路畅通、盒箱清理完成。",
            procedureSteps = listOf(
                "清扫管路，检查护口和接线盒",
                "按回路核对线色、线径和绝缘等级",
                "穿引线后分回路拉线，避免硬拉损伤绝缘",
                "预留接线长度并及时标识回路编号",
                "完成后做绝缘电阻测试"
            ),
            qualityChecklist = listOf(
                "同一回路线色一致",
                "导线无破皮、死弯和接头",
                "盒内预留长度满足接线要求",
                "绝缘测试记录完整"
            ),
            safetyChecklist = listOf(
                "确认相关回路未带电",
                "穿线机具专人操作",
                "梯凳站位稳固"
            )
        ),
        method(
            id = "method-distribution-box",
            title = "配电箱安装工艺",
            trade = "电气",
            publishStatus = "已发布",
            tutorialBody = "适用于户内照明箱、动力箱和小型配电柜安装。重点控制箱体标高、垂直度、回路标识和接地。",
            procedureSteps = listOf(
                "按图纸复核箱体位置、标高和预留洞口",
                "固定箱体，校正垂直度和平整度",
                "整理进出线，端子压接牢固",
                "粘贴回路标识和警示标识",
                "通电前完成绝缘、接地和空载检查"
            ),
            qualityChecklist = listOf(
                "箱体安装牢固，面板平整",
                "回路编号清楚，与图纸一致",
                "PE 排、N 排连接规范",
                "箱内整洁，无杂物和裸露铜丝"
            ),
            safetyChecklist = listOf(
                "送电前执行挂牌确认",
                "调试时一人操作一人监护",
                "严禁带电整理线束"
            )
        ),
        method(
            id = "method-hidden-acceptance",
            title = "隐蔽工程验收要点",
            trade = "资料/验收",
            publishStatus = "已发布",
            tutorialBody = "适用于管线封闭前的现场自检和资料留痕。重点是照片、尺寸、测试记录和责任人确认。",
            procedureSteps = listOf(
                "封闭前通知项目负责人和监理验收",
                "拍摄走向、节点、管线编号和关键尺寸",
                "核对材料规格、回路编号和测试记录",
                "问题整改后补拍复验照片",
                "同步归档验收单和现场照片"
            ),
            qualityChecklist = listOf(
                "隐蔽部位照片完整",
                "测试数据和验收日期一致",
                "整改项有前后对比",
                "验收单签字齐全"
            ),
            safetyChecklist = listOf(
                "封闭前确认无遗留工具和临时线",
                "井道、吊顶内作业注意防坠落",
                "验收后未批准不得私自封闭"
            )
        )
    )

    private fun method(
        id: String,
        title: String,
        trade: String,
        publishStatus: String,
        tutorialBody: String,
        procedureSteps: List<String>,
        qualityChecklist: List<String>,
        safetyChecklist: List<String>
    ): ConstructionMethodEntity =
        ConstructionMethodEntity(
            id = id,
            title = title,
            trade = trade,
            versionName = "V1",
            publishStatus = publishStatus,
            tutorialBody = tutorialBody,
            tutorialTextSize = "normal",
            tutorialAttachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(emptyList()),
            procedureStepsJson = BackupSnapshotJson.encodeStringList(procedureSteps),
            qualityChecklistJson = BackupSnapshotJson.encodeStringList(qualityChecklist),
            safetyChecklistJson = BackupSnapshotJson.encodeStringList(safetyChecklist),
            attachmentsJson = BackupSnapshotJson.encodeQuickNoteAttachments(emptyList()),
            updatedAt = UPDATED_AT
        )
}
