import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DataHealthPhotoTests {

    // 待办整改照片缺失检测
    @Test func missingRectificationPhotosAreDetected() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "test project", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        store.appendProject(project)

        // 创建一个有待办但没有实际照片文件的待办
        var todo = SiteTodo(title: "整改检查", priority: .high, issueType: .safety, projectId: pid)
        todo.rectificationBeforePhotoFileName = "nonexistent_before.jpg"
        todo.rectificationAfterPhotoFileName = "nonexistent_after.jpg"
        store.appendSiteTodo(todo)

        // 验证缺失检测逻辑
        let logPhotoNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotoNames = store.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }.compactMap { $0 }
        let allNames = logPhotoNames + todoPhotoNames

        let missing = allNames.filter { !PhotoStorage.exists(fileName: $0) }
        #expect(missing.contains("nonexistent_before.jpg"))
        #expect(missing.contains("nonexistent_after.jpg"))
    }

    // 修复后照片引用被清空
    @Test func repairClearsMissingRectificationPhotoReferences() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "repair test", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        store.appendProject(project)

        var todo = SiteTodo(title: "安全整改", priority: .high, issueType: .safety, projectId: pid)
        todo.rectificationBeforePhotoFileName = "ghost_photo.jpg"
        store.appendSiteTodo(todo)

        // 模拟修复：清除缺失的照片引用
        var repairedTodos = store.siteTodos
        for index in repairedTodos.indices {
            if let fileName = repairedTodos[index].rectificationBeforePhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationBeforePhotoFileName = nil
            }
            if let fileName = repairedTodos[index].rectificationAfterPhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationAfterPhotoFileName = nil
            }
        }
        store.replaceSiteTodos(repairedTodos)

        #expect(store.siteTodos[0].rectificationBeforePhotoFileName == nil)
    }

    // 日志 + 待办照片统一收集
    @Test func combinedPhotoNamesIncludesRectificationPhotos() throws {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)

        let pid = UUID()
        let project = Project(id: pid, name: "combined test", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        store.appendProject(project)

        var todo = SiteTodo(title: "整改项", priority: .medium, issueType: .quality, projectId: pid)
        todo.rectificationBeforePhotoFileName = "rect_before_combined.jpg"
        store.appendSiteTodo(todo)

        let logPhotos = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotos = store.siteTodos.compactMap(\.rectificationBeforePhotoFileName) + store.siteTodos.compactMap(\.rectificationAfterPhotoFileName)
        let combined = Set(logPhotos + todoPhotos)

        #expect(combined.contains("rect_before_combined.jpg"))
        #expect(!combined.contains("rect_after_combined.jpg")) // 没有设置 after
    }

    @Test func scannerSummarizesTriggeredHealthIssues() {
        let validProjectId = UUID()
        let invalidProjectId = UUID()
        let missingDocumentId = UUID()
        let missingFinancialRecordId = UUID()
        let document = ProjectDocument(
            projectId: validProjectId,
            title: "Receipt",
            fileName: "missing-receipt.pdf",
            linkedFinancialRecordId: missingFinancialRecordId
        )
        let financialRecord = ProjectFinancialRecord(
            projectId: validProjectId,
            linkedDocumentIds: [missingDocumentId]
        )
        let log = DailyLog(
            date: "2026-05-21",
            weather: "",
            content: "",
            workers: "",
            photoFileName: "missing-log.jpg",
            projectId: invalidProjectId
        )
        let todo = SiteTodo(
            title: "Fix",
            rectificationBeforePhotoFileName: "missing-before.jpg",
            projectId: invalidProjectId
        )
        let material = MaterialItem(
            name: "Cement",
            quantity: "1",
            unit: "bag",
            projectId: invalidProjectId
        )
        let warehouseMovement = ProjectWarehouseMovement(
            projectId: invalidProjectId,
            linkedDocumentIds: [missingDocumentId]
        )
        let input = DataHealthScanInput(
            projects: [Project(id: validProjectId, name: "Project", location: "")],
            dailyLogs: [log],
            siteTodos: [todo],
            projectDocuments: [document],
            projectFinancialRecords: [financialRecord],
            projectWarehouseMovements: [warehouseMovement],
            materialItems: [material],
            storageIssues: ["photo.save_failed"]
        )
        var storage = DataHealthScanStorage()
        storage.photoExists = { _ in false }
        storage.projectDocumentExists = { _ in false }
        storage.quickNoteAttachmentExists = { _ in true }
        storage.orphanPhotoFileNames = { _, _ in ["orphan-photo.jpg"] }
        storage.orphanDrawingFileNames = { _ in [] }
        storage.orphanProjectDocumentFileNames = { _ in [] }
        storage.orphanQuickNoteAttachmentFileNames = { _, _ in [] }

        let summary = DataHealthScanner.scan(
            input: input,
            reason: .dataChanged,
            scannedAt: Date(timeIntervalSince1970: 1_800_000_000),
            storage: storage
        )

        #expect(summary.reason == .dataChanged)
        #expect(summary.missingPhotoFiles == 2)
        #expect(summary.missingDocumentFiles == 1)
        #expect(summary.orphanPhotoFiles == 1)
        #expect(summary.orphanAttachmentMappings == 1)
        #expect(summary.orphanWarehouseAttachmentMappings == 1)
        #expect(summary.danglingDocumentLinks == 1)
        #expect(summary.invalidProjectRefs == 4)
        #expect(summary.storageIssues == 1)
        #expect(summary.totalIssues == 12)
        #expect(summary.hasIssues)
    }
}
