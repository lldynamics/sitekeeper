import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct DataStoreTests {

    let testStore: DataStore

    init() {
        let store = DataStore()
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
        guard let project = testStore.projects.first else {
            throw TestFailure("No project to delete")
        }
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
        guard testStore.projects.count >= 2 else {
            throw TestFailure("Need at least 2 projects")
        }
        let firstPid = testStore.projects[0].id
        let secondPid = testStore.projects[1].id
        let otherMaterialCount = testStore.materialItems.filter { $0.projectId == secondPid }.count

        testStore.deleteProject(firstPid)

        #expect(testStore.projects.contains { $0.id == secondPid })
        #expect(testStore.materialItems.filter { $0.projectId == secondPid }.count == otherMaterialCount)
    }

    // MARK: - flushSave

    @Test func flushSaveWritesToDisk() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        // Force a save that we can await
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: true)
        let project = Project(name: "flush test", location: "", status: ProjectStatus.active.rawValue, startDate: "2025-01-01", expectedEndDate: "2025-06-01")
        store.projects.append(project)
        await store.flushSave()

        let restored = DataStore()
        #expect(restored.projects.contains { $0.name == "flush test" })
    }

    @Test func flushSaveReplacesPendingScheduleSave() async throws {
        testStore.clearAllBusinessData(deleteStoredFiles: true)
        testStore.projects.append(Project(name: "flush pending", location: "", status: ProjectStatus.active.rawValue, startDate: "2025-01-01", expectedEndDate: "2025-06-01"))
        testStore.scheduleSave()
        await testStore.flushSave()

        let restored = DataStore()
        #expect(restored.projects.contains { $0.name == "flush pending" })
    }
}
