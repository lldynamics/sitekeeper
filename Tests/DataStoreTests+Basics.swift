import Testing
import Foundation
import UIKit
@testable import sitekeeper

extension DataStoreTests {
    // MARK: - Initial state

    @Test func emptyStoreHasNoBusinessData() {
        #expect(!testStore.hasAnyBusinessData)
    }

    @Test func emptyStoreProjectsEmpty() {
        #expect(testStore.projects.isEmpty)
    }

    // MARK: - Seed data

    @Test func importSampleDataPopulatesProjects() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.projects.isEmpty)
        #expect(testStore.projects.count >= 5)
    }

    @Test func importSampleDataPopulatesMaterials() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.materialItems.isEmpty)
    }

    @Test func importSampleDataReplacingClearsFirst() {
        testStore.importSampleData(replacingExisting: false)
        testStore.importSampleData(replacingExisting: true)
        #expect(testStore.projects.count >= 5)
    }

    @Test func importSampleDataSetsHistory() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.historyRecords.isEmpty)
    }

    @Test func importSampleDataRestoresExpandedFixtureCoverage() throws {
        #expect(testStore.importSampleData(replacingExisting: true))
        #expect(testStore.projects.count >= 5)
        #expect(testStore.materialItems.count >= 10)
        #expect(testStore.quoteItems.count >= 8)
        #expect(testStore.projectDrawings.count >= 3)
        #expect(testStore.projectDocuments.count >= 5)
        #expect(testStore.projectContacts.count >= 8)
        #expect(testStore.projectFinancialRecords.count >= 8)
        #expect(testStore.projectWarehouseMovements.count >= 8)
        #expect(testStore.materialSheetDrafts.count >= 4)
        #expect(testStore.quickNotes.contains { !$0.attachments.isEmpty })
        #expect(testStore.dailyLogs.contains { !$0.allPhotoFileNames.isEmpty })

        let drawing = try #require(testStore.projectDrawings.first)
        let document = try #require(testStore.projectDocuments.first)
        let note = try #require(testStore.quickNotes.first { !$0.attachments.isEmpty })
        let attachment = try #require(note.attachments.first)
        let photoName = try #require(testStore.dailyLogs.first(where: { !$0.allPhotoFileNames.isEmpty })?.allPhotoFileNames.first)

        #expect(DrawingStorage.exists(fileName: drawing.fileName))
        #expect(ProjectDocumentStorage.exists(fileName: document.fileName))
        #expect(QuickNoteAttachmentStorage.exists(fileName: attachment.fileName))
        #expect(PhotoStorage.exists(fileName: photoName))
        let photoData = try #require(PhotoStorage.data(for: photoName))
        #expect(UIImage(data: photoData) != nil)
    }

    @Test func calculationHistoryRemovalReturnsRestorableResult() {
        let first = HistoryRecord(tool: "墙面", input: "A", result: "1", date: BusinessDateValue(legacyText: "2026-05-16 10:00"))
        let second = HistoryRecord(tool: "照明", input: "B", result: "2", date: BusinessDateValue(legacyText: "2026-05-16 10:01"))
        testStore.replaceHistoryRecords([first, second])

        let deletion = testStore.removeCalculationHistory(ids: Set([first.id]))

        #expect(deletion.deletedCount == 1)
        #expect(testStore.historyRecords.map(\.id) == [second.id])
        #expect(deletion.restoredItems(current: testStore.historyRecords, id: \.id).map(\.id) == [first.id, second.id])
    }

    @Test func calculationHistoryClearReturnsRestorableResult() {
        let first = HistoryRecord(tool: "墙面", input: "A", result: "1", date: BusinessDateValue(legacyText: "2026-05-16 10:00"))
        let second = HistoryRecord(tool: "照明", input: "B", result: "2", date: BusinessDateValue(legacyText: "2026-05-16 10:01"))
        testStore.replaceHistoryRecords([first, second])

        let deletion = testStore.clearCalculationHistory()

        #expect(deletion.deletedCount == 2)
        #expect(testStore.historyRecords.isEmpty)
        #expect(deletion.restoredItems(current: testStore.historyRecords, id: \.id).map(\.id) == [first.id, second.id])
    }

    @Test func hasAnyBusinessDataAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(testStore.hasAnyBusinessData)
    }

    // MARK: - Snapshot roundtrip

    @Test func makeSnapshotPreservesData() {
        testStore.importSampleData(replacingExisting: false)
        let snapshot = testStore.makeSnapshot(includePhotoFiles: false)
        #expect(snapshot.projects.count == testStore.projects.count)
        #expect(snapshot.materialItems.count == testStore.materialItems.count)
        #expect(snapshot.quoteItems.count == testStore.quoteItems.count)
    }

    // MARK: - Clear

    @Test func clearAllBusinessDataEmptiesStore() {
        testStore.importSampleData(replacingExisting: false)
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        #expect(!testStore.hasAnyBusinessData)
        #expect(testStore.projects.isEmpty)
    }

    // MARK: - MaterialPriceEntries

    @Test func materialPriceEntriesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.materialPriceEntries.isEmpty)
        #expect(testStore.materialPriceEntries.contains { $0.name.contains("BV") })
    }

    // MARK: - supplierProfiles

    @Test func supplierProfilesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.supplierProfiles.isEmpty)
    }

    // MARK: - templates

    @Test func templatesAfterImport() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.templates.isEmpty)
        #expect(testStore.templates.contains { $0.category == .dailyLog })
    }

    // MARK: - deleteProject full cascade
}
