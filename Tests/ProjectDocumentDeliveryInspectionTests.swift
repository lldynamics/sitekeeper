import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectDocumentDeliveryInspectionTests {
    @Test func projectDeliveryInspectionReportsChecklistAndLedgerIssues() {
        let projectId = UUID()
        let project = Project(
            id: projectId,
            name: "交付项目",
            location: "",
            requiredDocumentCategories: [.constructionTechnical, .completionAcceptance]
        )
        let returnedDocument = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            category: .constructionTechnical,
            fileName: "missing-\(UUID().uuidString).pdf",
            submissionStatus: .returned,
            createdAt: BusinessDateValue(legacyText: "2026-05-17 10:00")
        )
        let unarchivedDocument = ProjectDocument(
            projectId: projectId,
            title: "材料报验",
            category: .constructionMaterial,
            fileName: "",
            submissionStatus: .submitted,
            responsiblePerson: "王工",
            formedAt: BusinessDateValue(legacyText: "2026-05-01"),
            createdAt: BusinessDateValue(legacyText: "2026-05-17 09:00")
        )

        let inspection = ProjectDocumentDeliveryInspection(
            project: project,
            documents: [returnedDocument, unarchivedDocument],
            drawings: [],
            logs: [],
            quickNotes: []
        )

        #expect(inspection.missingCategories == [.completionAcceptance])
        #expect(inspection.missingFiles.contains("资料 施工方案"))
        #expect(inspection.returnedDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.unarchivedDocuments.map(\.title) == ["施工方案", "材料报验"])
        #expect(inspection.missingResponsibleDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.missingFormedDateDocuments.map(\.title) == ["施工方案"])
        #expect(inspection.issues.map(\.kind) == [
            .missingCategories,
            .missingFiles,
            .returnedDocuments,
            .unarchivedDocuments,
            .missingResponsiblePerson,
            .missingFormedDate
        ])
        #expect(ProjectDocumentDeliveryInspectionIssueKind.missingFormedDate.preferredHealthFilter == .incompleteDocumentLedger)
        #expect(ProjectDocumentDeliveryInspectionIssueKind.returnedDocuments.preferredCategory == .documents)

        let csv = String(decoding: ProjectDocumentDeliveryInspectionExport.csvData(for: [inspection]), as: UTF8.self)
        #expect(csv.contains("缺类别"))
        #expect(csv.contains("文件丢失"))
        #expect(csv.contains("退回修改"))
        #expect(csv.contains("未归档"))
        #expect(csv.contains("缺责任人"))
        #expect(csv.contains("缺形成日期"))
        #expect(ProjectDocumentDeliveryInspectionExport.pdfData(for: [inspection]).starts(with: Data("%PDF".utf8)))

        let todoTitles = inspection.remediationTodoDrafts.map(\.title)
        #expect(todoTitles.contains("补齐交付缺失文件：资料 施工方案"))
        #expect(todoTitles.contains("处理退回资料：施工方案"))
        #expect(todoTitles.contains("归档项目资料：材料报验"))
        #expect(todoTitles.contains("补录资料责任人：施工方案"))
        #expect(todoTitles.contains("补录资料形成日期：施工方案"))
    }

    @Test func projectDeliveryHealthSummarizesDeliverabilityBlockers() throws {
        let referenceDate = try #require(Formatters.dateTime.date(from: "2026-05-16 12:00"))
        let backupState = ProjectDeliveryBackupState(
            latestBackupDate: nil,
            reminderDays: 7,
            referenceDate: referenceDate
        )

        let health = ProjectDeliveryHealth(
            missingReceiptCount: 2,
            drawingCount: 0,
            openTodoCount: 3,
            backupState: backupState,
            missingOriginalCount: 1,
            drawingWithoutCurrentCount: 1
        )

        #expect(health.score == 0)
        #expect(!health.isDeliverable)
        #expect(health.failedIssues == ProjectDeliveryHealth.Issue.allCases)
        #expect(health.summary.contains("缺票据"))
        #expect(health.summary.contains("未备份"))
    }

    @Test func projectDeliveryHealthPassesWhenCoreDeliveryChecksPass() throws {
        let referenceDate = try #require(Formatters.dateTime.date(from: "2026-05-16 12:00"))
        let latestBackup = try #require(Formatters.dateTime.date(from: "2026-05-15 09:00"))
        let backupState = ProjectDeliveryBackupState(
            latestBackupDate: latestBackup,
            reminderDays: 7,
            referenceDate: referenceDate
        )

        let health = ProjectDeliveryHealth(
            missingReceiptCount: 0,
            drawingCount: 2,
            openTodoCount: 0,
            backupState: backupState,
            missingOriginalCount: 0,
            drawingWithoutCurrentCount: 0
        )

        #expect(health.score == 100)
        #expect(health.isDeliverable)
        #expect(health.failedIssues.isEmpty)
    }

    @Test func siteTodoDecodesLegacyDrawingIssueFieldsAsEmpty() throws {
        let data = Data("""
        {
          "title": "旧待办",
          "owner": "李工",
          "dueDate": "2026-05-20",
          "priority": "高",
          "issueType": "质量"
        }
        """.utf8)

        let todo = try JSONDecoder().decode(SiteTodo.self, from: data)

        #expect(todo.drawingIssueLocation.isEmpty)
        #expect(todo.drawingIssueLayerOrPage.isEmpty)
        #expect(todo.drawingIssueMeasurement.isEmpty)
        #expect(todo.drawingIssueCloseEvidence.isEmpty)
    }
}
