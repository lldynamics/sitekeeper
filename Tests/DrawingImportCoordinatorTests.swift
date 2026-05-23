import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DrawingImportCoordinatorTests {
    @Test func unsupportedSingleFileReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-drawing-\(UUID().uuidString).txt")
        try Data("not a drawing".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [fileURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.unsupported"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == fileURL.lastPathComponent)
        #expect(result.operationMessage.contains(fileURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }

    @Test func zipWithoutDrawingEntriesReturnsFailureWithoutAddingDrawing() throws {
        let store = DataStore()
        let projectId = UUID()
        store.replaceProjects([Project(id: projectId, name: "测试项目", location: "")])

        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "drawing-empty-zip")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: "notes/readme.txt", data: Data("no drawings".utf8))
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        let result = DrawingImportCoordinator.importDrawings(
            [finishedURL],
            projectId: projectId,
            strategy: .createNewVersion,
            store: store,
            replacementCleanupSummary: "drawingImportCoordinatorTests.emptyZip"
        )

        #expect(result.importedCount == 0)
        #expect(result.replacedCount == 0)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.fileName == finishedURL.lastPathComponent)
        #expect(result.failures.first?.reason.contains("ZIP") == true)
        #expect(result.operationMessage.contains(finishedURL.lastPathComponent))
        #expect(store.projectDrawings.isEmpty)
    }
}

@MainActor
struct ConstructionMethodPackImportMappingTests {
    @Test func mappingNormalizesSourceAndKnowledgeReferences() {
        let pack = RemoteConstructionMethodPack(
            id: "method-pack-1",
            sourceSlug: "wireing",
            sourceURL: "/articles/wireing/abc",
            sourceVersion: "2026.05",
            title: "  管内穿线施工  ",
            trade: " 电气 ",
            versionName: "  ",
            publishStatus: "已发布",
            tutorialBody: """
            施工说明
            [查看原文](/articles/wireing/abc)
            """,
            procedureSteps: [" 进场交底 ", " ", "线缆检查"],
            qualityChecklist: ["端子压接", "绝缘测试"],
            safetyChecklist: ["临电断电上锁", "高处防护"],
            relatedStandards: [" GB 50303-2015 ", "", "JGJ 46-2005"],
            relatedTemplates: [
                RemoteConstructionMethodPackLink(title: "施工交底记录", href: "/templates/disclosure"),
                RemoteConstructionMethodPackLink(title: "施工交底记录", href: "/templates/disclosure"),
                RemoteConstructionMethodPackLink(title: "", href: "https://gongchengzhishi.chengjinfang.com/templates/checklist")
            ],
            relatedArticles: [
                RemoteConstructionMethodPackLink(title: "穿线质检要点", href: "/articles/wireing/quality"),
                RemoteConstructionMethodPackLink(title: " ", href: "  ")
            ],
            tags: ["电气"],
            updatedAt: "2026-05-23 10:00"
        )

        let mapped = pack.constructionMethod(existing: nil)

        #expect(mapped.title == "管内穿线施工")
        #expect(mapped.trade == "电气")
        #expect(mapped.versionName == "知识网站 V1")
        #expect(mapped.sourceID == "method-pack-1")
        #expect(mapped.sourceURL == "https://gongchengzhishi.chengjinfang.com/articles/wireing/abc")
        #expect(mapped.tutorialBody.contains("](https://gongchengzhishi.chengjinfang.com/articles/wireing/abc)"))
        #expect(mapped.relatedStandards == ["GB 50303-2015", "JGJ 46-2005"])
        #expect(mapped.relatedTemplates.count == 2)
        #expect(mapped.relatedTemplates.first?.href == "https://gongchengzhishi.chengjinfang.com/templates/disclosure")
        #expect(mapped.relatedArticles.count == 1)
        #expect(mapped.relatedArticles.first?.href == "https://gongchengzhishi.chengjinfang.com/articles/wireing/quality")
    }

    @Test func mappingUpdateKeepsExistingIdentityAndOverwritesKnowledgeFields() {
        let existingID = UUID()
        let existing = ConstructionMethod(
            id: existingID,
            title: "旧工艺",
            trade: "电气",
            versionName: "V1",
            publishStatus: .draft,
            tutorialBody: "旧正文",
            procedureSteps: ["旧步骤"],
            qualityChecklist: ["旧质检"],
            safetyChecklist: ["旧安全"],
            sourceID: "old-id",
            sourceURL: "https://example.com/old",
            sourceVersion: "old",
            sourceUpdatedAt: "2025-01-01 10:00",
            relatedStandards: ["旧规范"],
            relatedTemplates: [ConstructionMethodKnowledgeLink(title: "旧模板", href: "https://example.com/template-old")],
            relatedArticles: [ConstructionMethodKnowledgeLink(title: "旧文章", href: "https://example.com/article-old")]
        )

        let pack = RemoteConstructionMethodPack(
            id: "new-id",
            sourceSlug: "wireing",
            sourceURL: "https://gongchengzhishi.chengjinfang.com/articles/new",
            sourceVersion: "2026.06",
            title: "新版工艺",
            trade: "电气",
            versionName: "V2",
            publishStatus: "无效状态",
            tutorialBody: "新正文",
            procedureSteps: ["新步骤1", "新步骤2"],
            qualityChecklist: ["新质检"],
            safetyChecklist: ["新安全"],
            relatedStandards: ["新规范"],
            relatedTemplates: [RemoteConstructionMethodPackLink(title: "新模板", href: "https://gongchengzhishi.chengjinfang.com/templates/new")],
            relatedArticles: [RemoteConstructionMethodPackLink(title: "新文章", href: "https://gongchengzhishi.chengjinfang.com/articles/new-related")],
            tags: [],
            updatedAt: "2026-05-23 11:00"
        )

        let mapped = pack.constructionMethod(existing: existing)

        #expect(mapped.id == existingID)
        #expect(mapped.publishStatus == .published)
        #expect(mapped.sourceID == "new-id")
        #expect(mapped.sourceVersion == "2026.06")
        #expect(mapped.relatedStandards == ["新规范"])
        #expect(mapped.relatedTemplates.map(\.title) == ["新模板"])
        #expect(mapped.relatedArticles.map(\.title) == ["新文章"])
    }
}
