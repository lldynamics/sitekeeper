import Testing
import Foundation
import UIKit
@testable import sitekeeper

extension DataStoreTests {
    @Test func projectPhotoCleanupClearsReferencesAndKeepsSharedFiles() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let projectA = UUID()
        let projectB = UUID()
        let targetLog = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-16"),
            weather: "晴",
            content: "日志",
            workers: NumericInputSupport.quantity("2"),
            photoFileName: "legacy.jpg",
            photos: [
                LogPhoto(fileName: "target.jpg"),
                LogPhoto(fileName: "shared.jpg")
            ],
            projectId: projectA
        )
        let otherLog = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-17"),
            weather: "晴",
            content: "其他",
            workers: NumericInputSupport.quantity("1"),
            photos: [LogPhoto(fileName: "shared.jpg")],
            projectId: projectB
        )
        let targetTodo = SiteTodo(
            title: "整改",
            rectificationBeforePhotoFileName: "before.jpg",
            rectificationAfterPhotoFileName: "after.jpg",
            projectId: projectA
        )
        let otherTodo = SiteTodo(
            title: "其他整改",
            rectificationBeforePhotoFileName: "other-before.jpg",
            projectId: projectB
        )
        testStore.replaceDailyLogs([targetLog, otherLog])
        testStore.replaceSiteTodos([targetTodo, otherTodo])

        let result = testStore.clearProjectPhotoReferences(projectId: projectA)

        let cleanedLog = try #require(testStore.dailyLogs.first { $0.id == targetLog.id })
        let untouchedLog = try #require(testStore.dailyLogs.first { $0.id == otherLog.id })
        let cleanedTodo = try #require(testStore.siteTodos.first { $0.id == targetTodo.id })
        let untouchedTodo = try #require(testStore.siteTodos.first { $0.id == otherTodo.id })
        #expect(cleanedLog.photoFileName == nil)
        #expect(cleanedLog.photos.isEmpty)
        #expect(untouchedLog.allPhotoFileNames == ["shared.jpg"])
        #expect(cleanedTodo.rectificationBeforePhotoFileName == nil)
        #expect(cleanedTodo.rectificationAfterPhotoFileName == nil)
        #expect(untouchedTodo.rectificationBeforePhotoFileName == "other-before.jpg")
        #expect(result.photoFileNames == Set(["legacy.jpg", "target.jpg", "before.jpg", "after.jpg"]))
    }

    @Test func updateDailyLogPhotoPromotesLegacyPhotoIntoStructuredPhotos() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let log = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-16"),
            weather: "晴",
            content: "日志",
            workers: NumericInputSupport.quantity("2"),
            photoFileName: "legacy.jpg"
        )
        testStore.replaceDailyLogs([log])

        let updated = testStore.updateDailyLogPhoto(
            logId: log.id,
            photoId: UUID(),
            legacyFileName: "legacy.jpg",
            note: "现场门口",
            tag: .hiddenWork
        )

        #expect(updated)
        let stored = try #require(testStore.dailyLogs.first)
        #expect(stored.photoFileName == "legacy.jpg")
        #expect(stored.photos.count == 1)
        #expect(stored.photos.first?.fileName == "legacy.jpg")
        #expect(stored.photos.first?.note == "现场门口")
        #expect(stored.photos.first?.tag == .hiddenWork)
    }

    @Test func removeDailyLogPhotoRepairsPrimaryPhotoReference() throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let firstPhoto = LogPhoto(fileName: "first.jpg")
        let secondPhoto = LogPhoto(fileName: "second.jpg")
        let log = DailyLog(
            date: BusinessDateValue(legacyText: "2026-05-16"),
            weather: "晴",
            content: "日志",
            workers: NumericInputSupport.quantity("2"),
            photoFileName: "first.jpg",
            photos: [firstPhoto, secondPhoto]
        )
        testStore.replaceDailyLogs([log])

        let deletedFileName = testStore.removeDailyLogPhoto(
            logId: log.id,
            photoId: firstPhoto.id,
            legacyFileName: firstPhoto.fileName
        )

        #expect(deletedFileName == "first.jpg")
        let stored = try #require(testStore.dailyLogs.first)
        #expect(stored.photoFileName == "second.jpg")
        #expect(stored.photos.map(\.fileName) == ["second.jpg"])
    }
}
