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
}
