import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectPreDeliveryInspectionExportTests {
    @Test func preDeliveryInspectionTSVListsActionableIssues() throws {
        let project = Project(name: "交付体检", location: "工地", status: .active)
        let missingDrawing = ProjectDrawing(
            projectId: project.id,
            name: "一层平面",
            fileName: "missing-current-\(UUID().uuidString).pdf",
            fileType: "pdf",
            version: "V1",
            isCurrentVersion: false
        )
        let todo = SiteTodo(
            title: "整改收口",
            owner: "李工",
            dueDate: "2026-05-20",
            priority: .high,
            issueType: .quality,
            projectId: project.id
        )
        let financialRecord = ProjectFinancialRecord(
            projectId: project.id,
            date: "2026-05-19",
            direction: .expense,
            category: .material,
            amount: "1200",
            counterparty: "材料商"
        )
        let backupState = ReportBuilder.ProjectDeliveryPackageBackupState(
            latestBackupDate: nil,
            reminderDays: 7,
            referenceDate: Date()
        )

        let text = ReportBuilder.projectPreDeliveryInspectionTSVText(
            project: project,
            financialRecords: [financialRecord],
            documents: [],
            drawings: [missingDrawing],
            todos: [todo],
            logs: [],
            quickNotes: [],
            backupState: backupState
        )

        #expect(text.contains("missing_drawing_original\t缺图纸原件\tfailed\t未通过\tblocker\tdrawing"))
        #expect(text.contains("open_todo\t未结待办\tfailed\t未通过\tblocker\ttodo"))
        #expect(text.contains("missing_receipt\t缺票据\tfailed\t未通过\twarning\tfinancial_record"))
        #expect(text.contains("backup_freshness\t未备份\tfailed\t未通过\twarning\tproject"))
        #expect(text.contains("missing_current_drawing_version\t当前版缺失\tfailed\t未通过\twarning\tdrawing_group"))
        #expect(text.contains("在图纸台账中确认最终版本"))
    }

    @Test func preDeliveryInspectionStandaloneExportUsesReadableChecklistColumns() throws {
        let project = Project(name: "交付体检/甲方核对", location: "工地", status: .active)
        let missingDrawing = ProjectDrawing(
            projectId: project.id,
            name: "一层平面",
            fileName: "missing-current-\(UUID().uuidString).pdf",
            fileType: "pdf",
            version: "V1",
            isCurrentVersion: false
        )
        let todo = SiteTodo(
            title: "整改收口",
            owner: "李工",
            dueDate: "2026-05-20",
            priority: .high,
            issueType: .quality,
            projectId: project.id
        )
        let financialRecord = ProjectFinancialRecord(
            projectId: project.id,
            date: "2026-05-19",
            direction: .expense,
            category: .material,
            amount: "1200",
            counterparty: "材料商"
        )
        let backupState = ReportBuilder.ProjectDeliveryPackageBackupState(
            latestBackupDate: nil,
            reminderDays: 7,
            referenceDate: Date()
        )

        let payload = ProjectDetailExportWorkflow.makePreDeliveryInspectionPayload(
            project: project,
            financialRecords: [financialRecord],
            documents: [],
            drawings: [missingDrawing],
            todos: [todo],
            logs: [],
            quickNotes: [],
            backupState: backupState
        )
        let text = String(decoding: payload.data, as: UTF8.self)
        let expectedHeader = ReportBuilder.tsv([
            String(localized: "project.preDeliveryInspection.export.column.check"),
            String(localized: "project.preDeliveryInspection.export.column.status"),
            String(localized: "project.preDeliveryInspection.export.column.severity"),
            String(localized: "project.preDeliveryInspection.export.column.objectType"),
            String(localized: "project.preDeliveryInspection.export.column.object"),
            String(localized: "project.preDeliveryInspection.export.column.owner"),
            String(localized: "project.preDeliveryInspection.export.column.dueDate"),
            String(localized: "project.preDeliveryInspection.export.column.fileName"),
            String(localized: "project.preDeliveryInspection.export.column.detail"),
            String(localized: "project.preDeliveryInspection.export.column.action")
        ])

        #expect(payload.defaultFilename.contains("交付体检_甲方核对"))
        #expect(payload.defaultFilename.hasSuffix(".tsv"))
        #expect(text.contains(expectedHeader))
        #expect(text.contains(ReportBuilder.tsv([
            String(localized: "缺图纸原件"),
            String(localized: "未通过"),
            String(localized: "project.preDeliveryInspection.export.severity.blocker"),
            String(localized: "project.preDeliveryInspection.export.object.drawing"),
            "一层平面"
        ])))
        #expect(text.contains(ReportBuilder.tsv([
            String(localized: "未结待办"),
            String(localized: "未通过"),
            String(localized: "project.preDeliveryInspection.export.severity.blocker"),
            String(localized: "project.preDeliveryInspection.export.object.todo"),
            "整改收口",
            "李工",
            "2026-05-20"
        ])))
        #expect(text.contains(ReportBuilder.tsv([
            String(localized: "缺票据"),
            String(localized: "未通过"),
            String(localized: "project.preDeliveryInspection.export.severity.warning"),
            String(localized: "project.preDeliveryInspection.export.object.financialRecord")
        ])))
        #expect(text.contains(ReportBuilder.tsv([
            String(localized: "未备份"),
            String(localized: "未通过"),
            String(localized: "project.preDeliveryInspection.export.severity.warning"),
            String(localized: "project.preDeliveryInspection.export.object.project"),
            "交付体检/甲方核对"
        ])))
        #expect(text.contains(ReportBuilder.tsv([
            String(localized: "当前版缺失"),
            String(localized: "未通过"),
            String(localized: "project.preDeliveryInspection.export.severity.warning"),
            String(localized: "project.preDeliveryInspection.export.object.drawingGroup"),
            "一层平面"
        ])))
    }
}
