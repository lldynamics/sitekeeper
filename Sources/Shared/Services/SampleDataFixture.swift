import Foundation

#if DEBUG
@MainActor
extension DataStore {
    func seedDefaults() {
        guard let snapshot = SampleDataFixtureLoader.loadSnapshot() else {
            StorageIssueLog.recordEvent(
                "sample_data.fixture_missing",
                category: .dataStore,
                details: ["file": "SampleDataFixture.json"]
            )
            return
        }
        applySampleSnapshot(snapshot)
    }

    private func applySampleSnapshot(_ snapshot: BackupSnapshot) {
        projects = snapshot.projects
        materialItems = snapshot.materialItems
        quoteItems = snapshot.quoteItems
        laborRecords = snapshot.laborRecords
        dailyLogs = snapshot.dailyLogs
        historyRecords = snapshot.historyRecords
        progressTasks = snapshot.progressTasks
        lightingCircuitPlans = snapshot.lightingCircuitPlans
        siteTodos = snapshot.siteTodos
        projectDrawings = snapshot.projectDrawings
        projectDocuments = snapshot.projectDocuments
        projectContacts = snapshot.projectContacts
        projectFinancialRecords = snapshot.projectFinancialRecords
        quickNotes = snapshot.quickNotes
        projectWarehouseMovements = snapshot.projectWarehouseMovements
        templates = snapshot.templates
        materialPriceEntries = snapshot.materialPriceEntries
        materialSheetDrafts = snapshot.materialSheetDrafts
        supplierProfiles = snapshot.supplierProfiles
        constructionMethods = snapshot.constructionMethods
        userMaterials = snapshot.userMaterials
        deletedUserMaterials = snapshot.deletedUserMaterials
        favoriteMaterialKeys = snapshot.favoriteMaterialKeys
        recentMaterialKeys = snapshot.recentMaterialKeys
    }
}

private enum SampleDataFixtureLoader {
    static func loadSnapshot() -> BackupSnapshot? {
        guard let data = loadFixtureData() else { return nil }
        do {
            return try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            StorageIssueLog.recordEvent(
                "sample_data.decode_failed",
                category: .dataStore,
                details: ["file": "SampleDataFixture.json"],
                error: error
            )
            return nil
        }
    }

    private static func loadFixtureData() -> Data? {
        if let sourceURL = sourceFixtureURL,
           let data = try? Data(contentsOf: sourceURL) {
            return data
        }
        for bundle in candidateBundles {
            if let url = bundle.url(
                forResource: "SampleDataFixture",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    private static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]
        if let allFrameworks = Bundle.allFrameworks as [Bundle]? {
            bundles.append(contentsOf: allFrameworks)
        }
        return bundles
    }

    private static var sourceFixtureURL: URL? {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = sourceDirectory
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("SampleDataFixture.json", isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private final class BundleToken {}
}
#endif
