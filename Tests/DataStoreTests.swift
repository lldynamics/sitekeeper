import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DataStoreTests {

    let testStore: DataStore
    let storageDirectory: URL

    init() {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageDirectory = directory
        let store = DataStore(storageDirectory: directory)
        store.clearAllBusinessData(deleteStoredFiles: false)
        self.testStore = store
    }

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
        #expect(testStore.projects.count >= 2)
    }

    @Test func importSampleDataPopulatesMaterials() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.materialItems.isEmpty)
    }

    @Test func importSampleDataReplacingClearsFirst() {
        testStore.importSampleData(replacingExisting: false)
        testStore.importSampleData(replacingExisting: true)
        #expect(testStore.projects.count >= 2)
    }

    @Test func importSampleDataSetsHistory() {
        testStore.importSampleData(replacingExisting: false)
        #expect(!testStore.historyRecords.isEmpty)
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

    @Test func deleteProjectRemovesProjectAndAllRelatedData() async throws {
        testStore.importSampleData(replacingExisting: true)
        let project = try #require(testStore.projects.first)
        let pid = project.id

        testStore.deleteProject(pid)

        #expect(!testStore.projects.contains { $0.id == pid })
        #expect(!testStore.materialItems.contains { $0.projectId == pid })
        #expect(!testStore.quoteItems.contains { $0.projectId == pid })
        #expect(!testStore.laborRecords.contains { $0.projectId == pid })
        #expect(!testStore.dailyLogs.contains { $0.projectId == pid })
        #expect(!testStore.progressTasks.contains { $0.projectId == pid })
        #expect(!testStore.lightingCircuitPlans.contains { $0.projectId == pid })
        #expect(!testStore.siteTodos.contains { $0.projectId == pid })
        #expect(!testStore.paymentRecords.contains { $0.projectId == pid })
        #expect(!testStore.projectDrawings.contains { $0.projectId == pid })
        #expect(!testStore.projectContacts.contains { $0.projectId == pid })
        #expect(!testStore.projectFinancialRecords.contains { $0.projectId == pid })
        #expect(!testStore.projectDocuments.contains { $0.projectId == pid })
        #expect(!testStore.quickNotes.contains { $0.projectId == pid })
        #expect(!testStore.projectWarehouseMovements.contains { $0.projectId == pid })
    }

    @Test func deleteProjectDoesNotAffectOtherProjects() async throws {
        testStore.importSampleData(replacingExisting: true)
        try #require(testStore.projects.count >= 2)
        let firstPid = testStore.projects[0].id
        let secondPid = testStore.projects[1].id
        let otherMaterialCount = testStore.materialItems.filter { $0.projectId == secondPid }.count

        testStore.deleteProject(firstPid)

        #expect(testStore.projects.contains { $0.id == secondPid })
        #expect(testStore.materialItems.filter { $0.projectId == secondPid }.count == otherMaterialCount)
    }

    @Test func deleteProjectRemovesOnlyMaterialSheetDraftsUnderProject() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: false)
        let first = Project(name: "A", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        let second = Project(name: "B", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.projects = [first, second]
        testStore.materialSheetDrafts = [
            MaterialSheetDraft(title: "A 草稿", projectId: first.id),
            MaterialSheetDraft(title: "B 草稿", projectId: second.id),
            MaterialSheetDraft(title: "无归属草稿", projectId: nil)
        ]

        testStore.deleteProject(first.id)

        #expect(!testStore.materialSheetDrafts.contains { $0.projectId == first.id })
        #expect(testStore.materialSheetDrafts.contains { $0.projectId == second.id })
        #expect(testStore.materialSheetDrafts.contains { $0.projectId == nil })
    }

    // MARK: - flushSave

    @Test func flushSaveWritesToDisk() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        let project = Project(name: "flush test", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        testStore.projects.append(project)
        await testStore.flushSave()

        let restored = DataStore(storageDirectory: storageDirectory)
        await restored.awaitInitialLoad()
        #expect(restored.projects.contains { $0.name == "flush test" })
    }

    @Test func flushSaveReplacesPendingScheduleSave() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        testStore.projects.append(Project(name: "flush pending", location: "", status: .active, startDate: "2025-01-01", expectedEndDate: "2025-06-01"))
        testStore.scheduleSave()
        await testStore.flushSave()

        let restored = DataStore(storageDirectory: storageDirectory)
        await restored.awaitInitialLoad()
        #expect(restored.projects.contains { $0.name == "flush pending" })
    }
}
