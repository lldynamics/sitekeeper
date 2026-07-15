import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct LargeDataPerformanceTests {
    @Test func projectFileSearchVersionAdvancesOnceForLargeBatch() {
        let store = ProjectStore()
        let initialVersion = store.fileSearchVersion
        let projects = (0..<10_000).map { index in
            Project(name: "性能项目 \(index)", location: "区域 \(index % 20)", status: .active)
        }

        store.setProjects(projects)

        #expect(store.projects.count == 10_000)
        #expect(store.fileSearchVersion == initialVersion + 1)
    }

    @Test func searchableCollectionMutationsInvalidateFileSearchVersion() {
        let store = ProjectStore()
        let projectID = UUID()
        let initialVersion = store.fileSearchVersion

        store.setProjects([Project(id: projectID, name: "项目", location: "", status: .active)])
        store.setDailyLogs([DailyLog(date: "2026-07-13", weather: "晴", content: "日志", workers: "1", projectId: projectID)])
        store.setSiteTodos([SiteTodo(title: "待办", projectId: projectID)])
        store.setProjectDrawings([ProjectDrawing(projectId: projectID, name: "图纸", fileName: "a.pdf", fileType: "pdf")])
        store.setProjectDocuments([ProjectDocument(projectId: projectID, title: "资料", fileName: "b.pdf")])
        store.setQuickNotes([QuickNote(title: "随手记", projectId: projectID)])

        #expect(store.fileSearchVersion == initialVersion + 6)
    }

    @Test func bigramIndexFindsRareMatchInLargeFileCollection() async {
        let service = ProjectFileSearchIndexService()
        let rows = (0..<10_000).map { index in
            ProjectFileSearchIndexRow(
                id: "row-\(index)",
                searchableText: index == 7_777 ? "地下室防水验收 报告" : "常规资料 项目 \(index)",
                sortDate: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        await service.rebuild(signature: 0, rows: rows)
        let ids = await service.search(keyword: "防水验收")

        #expect(ids == ["row-7777"])
    }

    @Test func persistenceSkipsIdenticalSnapshotWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("datastore-identical-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let actor = DataStorePersistenceActor(storeURL: directory.appendingPathComponent("store.json"))
        let snapshot = makeSnapshot(projectName: "相同内容")

        #expect(try await actor.persist(snapshot: snapshot))
        #expect(try await !actor.persist(snapshot: snapshot))
        #expect(try await actor.persist(snapshot: makeSnapshot(projectName: "更新内容")))
    }

    private func makeSnapshot(projectName: String) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: projectName, location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
    }
}
