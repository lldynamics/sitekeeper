import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
struct ProjectDocumentChecklistTests {
    @Test func projectDocumentRecommendationFollowsProjectStage() throws {
        let referenceDate = try #require(Formatters.date.date(from: "2026-05-17"))
        let futureProject = Project(
            name: "开工前项目",
            location: "",
            status: .active,
            startDate: "2026-06-01"
        )
        let startedProject = Project(
            name: "施工中项目",
            location: "",
            status: .active,
            startDate: "2026-05-01"
        )
        let nearlyDoneTask = ProgressTask(
            projectId: startedProject.id,
            title: "收尾",
            startDate: "2026-05-01",
            dueDate: "2026-05-20",
            completion: 0.9,
            note: ""
        )
        let completedProject = Project(name: "完工项目", location: "", status: .completed)

        #expect(ProjectDocumentCategory.recommendedStage(
            for: futureProject,
            referenceDate: referenceDate
        ) == .preConstruction)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: startedProject,
            referenceDate: referenceDate
        ) == .construction)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: startedProject,
            progressTasks: [nearlyDoneTask],
            referenceDate: referenceDate
        ) == .acceptance)
        #expect(ProjectDocumentCategory.recommendedStage(
            for: completedProject,
            referenceDate: referenceDate
        ) == .acceptance)
    }

    @Test func projectDocumentRecommendationCategoriesMatchConstructionStages() {
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .preConstruction) == [
            .constructionTechnical,
            .constructionManagement
        ])
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .construction) == [
            .constructionMaterial,
            .constructionSurvey,
            .constructionRecord,
            .constructionTest
        ])
        #expect(ProjectDocumentCategory.recommendedConstructionArchiveRequirements(for: .acceptance) == [
            .processAcceptance,
            .completionAcceptance
        ])
    }

    @Test func projectDocumentChecklistPresetsProvideReusableProjectTypeTemplates() {
        let presets = ProjectDocumentChecklistTemplate.builtInPresets

        #expect(presets.map(\.name) == ["土建", "装饰", "机电", "消防"])
        #expect(presets.first(where: { $0.name == "土建" })?.categories == ProjectDocumentCategory.defaultConstructionArchiveRequirements)
        #expect(presets.first(where: { $0.name == "装饰" })?.categories.contains(.constructionSurvey) == false)
        #expect(presets.allSatisfy { !$0.categories.isEmpty })
    }

    @Test func projectDocumentChecklistTemplateParsesSavedProjectTemplate() throws {
        let template = ProjectTemplate.documentChecklistTemplate(
            name: "机电复用模板",
            categories: [.completionAcceptance, .constructionMaterial, .constructionRecord]
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(ProjectTemplate.self, from: data)

        #expect(decoded.category == .projectDocumentChecklist)
        #expect(decoded.documentChecklistCategories == [
            .constructionMaterial,
            .constructionRecord,
            .completionAcceptance
        ])
        let customTemplates = ProjectDocumentChecklistTemplate.customTemplates(from: [decoded])
        let customTemplate = try #require(customTemplates.first)
        #expect(customTemplate.name == "机电复用模板")
        #expect(customTemplate.categories == decoded.documentChecklistCategories)
    }

    @Test func projectFileHealthFilterMatchesIncompleteDocumentLedger() {
        let item = ProjectFileItem(
            id: "document-ledger",
            title: "施工方案",
            subtitle: "施工技术",
            fileType: "pdf",
            url: URL(fileURLWithPath: "/tmp/document-ledger.pdf"),
            exists: true,
            size: 1_024,
            category: .documents,
            systemImage: "doc.richtext",
            thumbnailToken: nil,
            sortDate: Date(),
            documentStatus: .submitted,
            documentLedgerIssueCount: 1
        )

        #expect(ProjectFileHealthFilter.incompleteDocumentLedger.matches(item))
        #expect(!ProjectFileHealthFilter.missing.matches(item))
    }

    @Test func projectDocumentStatusHistoryPersistsAndLegacyDecodeDefaultsEmpty() throws {
        let projectId = UUID()
        let entryId = UUID()
        let changedAt = "2026-05-17 10:30"
        let document = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method.pdf",
            submissionStatus: .submitted,
            statusHistory: [
                ProjectDocumentStatusHistoryEntry(
                    id: entryId,
                    fromStatus: .pending,
                    toStatus: .submitted,
                    operatorName: "张工",
                    changedAt: changedAt,
                    reason: "报验完成"
                )
            ],
            versionNumber: 2,
            versionState: .superseded,
            replacesDocumentId: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            replacedByDocumentId: UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)

        #expect(decoded.versionNumber == 2)
        #expect(decoded.versionState == .superseded)
        #expect(decoded.replacesDocumentId == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(decoded.replacedByDocumentId == UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        #expect(decoded.statusHistory.count == 1)
        let entry = try #require(decoded.statusHistory.first)
        #expect(entry.id == entryId)
        #expect(entry.fromStatus == .pending)
        #expect(entry.toStatus == .submitted)
        #expect(entry.operatorName == "张工")
        #expect(entry.changedAt == changedAt)
        #expect(entry.reason == "报验完成")

        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "projectId": "\(projectId.uuidString)",
          "title": "旧资料",
          "category": "施工记录",
          "fileName": "legacy.pdf"
        }
        """
        let legacyDocument = try JSONDecoder().decode(ProjectDocument.self, from: Data(legacyJSON.utf8))
        #expect(legacyDocument.statusHistory.isEmpty)
        #expect(legacyDocument.versionNumber == 1)
        #expect(legacyDocument.versionState == .current)
        #expect(legacyDocument.replacesDocumentId == nil)
        #expect(legacyDocument.replacedByDocumentId == nil)
    }

    @Test func projectDocumentVersionReplacementMarksPreviousVersion() throws {
        let store = DataStore()
        let projectId = UUID()
        let original = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method-v1.pdf",
            versionNumber: 1
        )
        let replacement = ProjectDocument(
            projectId: projectId,
            title: "施工方案",
            fileName: "method-v2.pdf",
            versionNumber: 1,
            replacesDocumentId: original.id
        )
        store.replaceProjectDocuments([original, replacement])

        ProjectDetailFinanceDocumentActions.saveDocumentEdit(replacement, store: store)

        let savedOriginal = try #require(store.projectDocuments.first { $0.id == original.id })
        let savedReplacement = try #require(store.projectDocuments.first { $0.id == replacement.id })
        #expect(savedReplacement.versionNumber == 2)
        #expect(savedReplacement.replacesDocumentId == original.id)
        #expect(savedOriginal.replacedByDocumentId == replacement.id)
        #expect(savedOriginal.versionState == .superseded)

        var detachedReplacement = savedReplacement
        detachedReplacement.replacesDocumentId = nil
        ProjectDetailFinanceDocumentActions.saveDocumentEdit(detachedReplacement, store: store)

        let detachedOriginal = try #require(store.projectDocuments.first { $0.id == original.id })
        let savedDetachedReplacement = try #require(store.projectDocuments.first { $0.id == replacement.id })
        #expect(savedDetachedReplacement.replacesDocumentId == nil)
        #expect(detachedOriginal.replacedByDocumentId == nil)
        #expect(detachedOriginal.versionState == .current)
    }
}
