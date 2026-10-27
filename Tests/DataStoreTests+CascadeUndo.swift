import Testing
import Foundation
@testable import sitekeeper

extension DataStoreTests {
    @Test func projectCascadeUndoPreservesLaterChangesAcrossEveryRecordCategory() throws {
        var projectA = Project(name: "待撤销删除的 A", location: "")
        var projectB = Project(name: "保留的 B", location: "")
        let projectC = Project(name: "删除后新增的 C", location: "")
        // A 待恢复；B 的第一条编辑、第二条删除；C 随后新增。
        var fixture = ProjectCascadeUndoFixture(projectIDs: [projectA.id, projectB.id, projectB.id, projectC.id])
        testStore.replaceProjects([projectA, projectB])
        fixture.seedRecords(in: testStore)
        let deletion = testStore.removeProjectCascade(projectA.id)

        projectB.status = .archived
        testStore.replaceProjects([projectB, projectC])
        fixture.applyLaterChanges(to: testStore)
        testStore.restoreProjectCascade(deletion)
        try Self.expectSameRecords(testStore.projects, expected: [projectA, projectB, projectC])
        try fixture.expectRestoredRecords(in: testStore)

        // 同 ID 记录再次编辑后，重复恢复不能覆盖新值或增加副本。
        projectA.name = "恢复后修改的 A"
        #expect(testStore.updateProject(projectA))
        fixture.materials[0].quantity = NumericInputSupport.quantity("12")
        #expect(testStore.updateMaterialItem(fixture.materials[0]))
        testStore.restoreProjectCascade(deletion)
        try Self.expectSameRecords(testStore.projects, expected: [projectA, projectB, projectC])
        try fixture.expectRestoredRecords(in: testStore)
    }

    @Test func projectCascadeUndoRestoresOnlyRemovedContactLinksAndKeepsContactEdits() throws {
        let projectA = Project(name: "A", location: "")
        let projectB = Project(name: "B", location: "")
        let projectC = Project(name: "C", location: "")
        let projectD = Project(name: "D", location: "")
        let shared = ProjectContact(
            projectId: projectB.id,
            relatedProjectIds: [projectA.id, projectC.id],
            name: "共享联系人",
            phone: "13000000000"
        )
        let subsequentlyDeleted = ProjectContact(projectId: projectB.id, relatedProjectIds: [projectA.id], name: "随后删除")
        let primary = ProjectContact(projectId: projectA.id, name: "A 主联系人")
        testStore.replaceProjects([projectA, projectB, projectC, projectD])
        testStore.replaceProjectContacts([shared, subsequentlyDeleted, primary])

        let deletion = testStore.removeProjectCascade(projectA.id)
        var editedShared = try #require(testStore.projectContacts.first { $0.id == shared.id })
        #expect(editedShared.relatedProjectIds == [projectC.id])
        editedShared.phone = "13900000000"
        editedShared.name = "更新后的共享联系人"
        editedShared.relatedProjectIds = [projectD.id]
        let added = ProjectContact(projectId: projectB.id, relatedProjectIds: [projectD.id], name: "新增联系人")
        testStore.replaceProjectContacts([editedShared, added])

        testStore.restoreProjectCascade(deletion)
        testStore.restoreProjectCascade(deletion)

        editedShared.relatedProjectIds.append(projectA.id)
        try Self.expectSameRecords(testStore.projectContacts, expected: [editedShared, added, primary])
        let restoredShared = try #require(testStore.projectContacts.first { $0.id == shared.id })
        #expect(restoredShared.relatedProjectIds.filter { $0 == projectA.id }.count == 1)
        #expect(!restoredShared.isLinked(to: projectC.id))
        #expect(!testStore.projectContacts.contains { $0.id == subsequentlyDeleted.id })
    }

    private static func expectSameRecords<Item: Identifiable & Encodable>(
        _ actual: [Item],
        expected: [Item]
    ) throws where Item.ID == UUID {
        #expect(actual.count == expected.count)
        #expect(Set(actual.map(\.id)) == Set(expected.map(\.id)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for expectedRecord in expected {
            let actualRecord = try #require(actual.first { $0.id == expectedRecord.id })
            let actualData = try encoder.encode(actualRecord)
            let expectedData = try encoder.encode(expectedRecord)
            #expect(actualData == expectedData)
        }
    }

    @MainActor
    private struct ProjectCascadeUndoFixture {
        var materials: [MaterialItem]
        var quotes: [QuoteItem]
        var labor: [LaborRecord]
        var logs: [DailyLog]
        var progress: [ProgressTask]
        var todos: [SiteTodo]
        var drawings: [ProjectDrawing]
        var financial: [ProjectFinancialRecord]
        var documents: [ProjectDocument]
        var notes: [QuickNote]
        var movements: [ProjectWarehouseMovement]
        var drafts: [MaterialSheetDraft]

        init(projectIDs: [UUID]) {
            materials = projectIDs.map { MaterialItem(name: "水泥", quantity: NumericInputSupport.quantity("1"), unit: "袋", projectId: $0) }
            quotes = projectIDs.map {
                QuoteItem(name: "报价", unitPrice: NumericInputSupport.money("10"), quantity: NumericInputSupport.quantity("1"), unit: "项", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: $0)
            }
            labor = projectIDs.map { LaborRecord(date: BusinessDateValue(legacyText: "2026-10-13"), workers: NumericInputSupport.quantity("2"), hours: NumericInputSupport.quantity("1"), note: "", projectId: $0) }
            logs = projectIDs.map { DailyLog(date: BusinessDateValue(legacyText: "2026-10-13"), weather: "晴", content: "日志", workers: NumericInputSupport.quantity("2"), projectId: $0) }
            progress = projectIDs.map {
                ProgressTask(projectId: $0, title: "进度", startDate: BusinessDateValue(legacyText: "2026-10-13"), dueDate: BusinessDateValue(legacyText: "2026-10-20"), completion: 0.3, note: "")
            }
            todos = projectIDs.map { SiteTodo(title: "待办", projectId: $0) }
            drawings = projectIDs.map { ProjectDrawing(projectId: $0, name: "图纸", fileName: "undo-\(UUID().uuidString).pdf", fileType: "pdf") }
            financial = projectIDs.map { ProjectFinancialRecord(projectId: $0, amount: NumericInputSupport.money("100")) }
            documents = projectIDs.map { ProjectDocument(projectId: $0, title: "资料", fileName: "undo-\(UUID().uuidString).pdf") }
            notes = projectIDs.map { QuickNote(title: "随手记", projectId: $0) }
            movements = projectIDs.map { ProjectWarehouseMovement(projectId: $0, materialName: "水泥", unit: "袋", quantity: NumericInputSupport.quantity("1")) }
            drafts = projectIDs.map { MaterialSheetDraft(title: "材料单", projectId: $0) }
        }

        func seedRecords(in store: DataStore) {
            store.replaceMaterialItems(Array(materials.prefix(3)))
            store.replaceQuoteItems(Array(quotes.prefix(3)))
            store.replaceLaborRecords(Array(labor.prefix(3)))
            store.replaceDailyLogs(Array(logs.prefix(3)))
            store.replaceProgressTasks(Array(progress.prefix(3)))
            store.replaceSiteTodos(Array(todos.prefix(3)))
            store.replaceProjectDrawings(Array(drawings.prefix(3)))
            store.replaceProjectFinancialRecords(Array(financial.prefix(3)))
            store.replaceProjectDocuments(Array(documents.prefix(3)))
            store.replaceQuickNotes(Array(notes.prefix(3)))
            store.replaceProjectWarehouseMovements(Array(movements.prefix(3)))
            store.replaceMaterialSheetDrafts(Array(drafts.prefix(3)))
        }

        mutating func applyLaterChanges(to store: DataStore) {
            materials[1].quantity = NumericInputSupport.quantity("9")
            quotes[1].unitPrice = NumericInputSupport.money("99")
            labor[1].unitRate = NumericInputSupport.money("350")
            logs[1].content = "更新施工日志"
            progress[1].completion = 0.8
            todos[1].isDone = true
            drawings[1].name = "修订图纸"
            financial[1].amount = NumericInputSupport.money("999")
            documents[1].title = "修订资料"
            notes[1].content = "新增现场情况"
            movements[1].quantity = NumericInputSupport.quantity("9")
            drafts[1].title = "修订材料单"
            store.replaceMaterialItems([materials[1], materials[3]])
            store.replaceQuoteItems([quotes[1], quotes[3]])
            store.replaceLaborRecords([labor[1], labor[3]])
            store.replaceDailyLogs([logs[1], logs[3]])
            store.replaceProgressTasks([progress[1], progress[3]])
            store.replaceSiteTodos([todos[1], todos[3]])
            store.replaceProjectDrawings([drawings[1], drawings[3]])
            store.replaceProjectFinancialRecords([financial[1], financial[3]])
            store.replaceProjectDocuments([documents[1], documents[3]])
            store.replaceQuickNotes([notes[1], notes[3]])
            store.replaceProjectWarehouseMovements([movements[1], movements[3]])
            store.replaceMaterialSheetDrafts([drafts[1], drafts[3]])
        }

        func expectRestoredRecords(in store: DataStore) throws {
            try DataStoreTests.expectSameRecords(store.materialItems, expected: [materials[0], materials[1], materials[3]])
            try DataStoreTests.expectSameRecords(store.quoteItems, expected: [quotes[0], quotes[1], quotes[3]])
            try DataStoreTests.expectSameRecords(store.laborRecords, expected: [labor[0], labor[1], labor[3]])
            try DataStoreTests.expectSameRecords(store.dailyLogs, expected: [logs[0], logs[1], logs[3]])
            try DataStoreTests.expectSameRecords(store.progressTasks, expected: [progress[0], progress[1], progress[3]])
            try DataStoreTests.expectSameRecords(store.siteTodos, expected: [todos[0], todos[1], todos[3]])
            try DataStoreTests.expectSameRecords(store.projectDrawings, expected: [drawings[0], drawings[1], drawings[3]])
            try DataStoreTests.expectSameRecords(store.projectFinancialRecords, expected: [financial[0], financial[1], financial[3]])
            try DataStoreTests.expectSameRecords(store.projectDocuments, expected: [documents[0], documents[1], documents[3]])
            try DataStoreTests.expectSameRecords(store.quickNotes, expected: [notes[0], notes[1], notes[3]])
            try DataStoreTests.expectSameRecords(store.projectWarehouseMovements, expected: [movements[0], movements[1], movements[3]])
            try DataStoreTests.expectSameRecords(store.materialSheetDrafts, expected: [drafts[0], drafts[1], drafts[3]])
        }
    }
}
