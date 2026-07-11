import Foundation

@MainActor
extension DataStore {
    func loadSampleFixtureSnapshot() -> BackupSnapshot? {
#if DEBUG
        guard let snapshot = SampleDataFixtureLoader.loadSnapshot() else {
            StorageIssueLog.recordEvent(
                "sample_data.fixture_missing",
                category: .dataStore,
                details: ["file": "SampleDataFixture.json"]
            )
            return nil
        }
        return snapshot
#else
        return nil
#endif
    }

    func applySampleFixtureSnapshot(_ snapshot: BackupSnapshot) {
        applyLoadedSnapshot(snapshot)
        restoreSampleFixtureFiles(snapshot)
    }

    private func restoreSampleFixtureFiles(_ snapshot: BackupSnapshot) {
        PhotoStorage.restore(snapshot.photoFiles)
        DrawingStorage.restore(snapshot.drawingFiles)
        ProjectDocumentStorage.restore(snapshot.documentFiles)
        QuickNoteAttachmentStorage.restore(snapshot.quickNoteAttachmentFiles)
    }
}

#if DEBUG
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
        for sourceURL in sourceFixtureURLs {
            if let data = try? Data(contentsOf: sourceURL) {
                return data
            }
        }
        for bundle in candidateBundles {
            if let url = bundledFixtureURL(in: bundle) {
                return try? Data(contentsOf: url)
            }
        }
        return nil
    }

    private static func bundledFixtureURL(in bundle: Bundle) -> URL? {
        if let url = bundle.url(
            forResource: "SampleDataFixture",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) {
            return url
        }
        return bundle.url(forResource: "SampleDataFixture", withExtension: "json")
    }

    private static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: BundleToken.self)]
        bundles.append(contentsOf: Bundle.allBundles)
        if let allFrameworks = Bundle.allFrameworks as [Bundle]? {
            bundles.append(contentsOf: allFrameworks)
        }
        return bundles
    }

    private static var sourceFixtureURLs: [URL] {
        let sourceDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryDirectory = sourceDirectory.deletingLastPathComponent()
        return [
            repositoryDirectory
                .appendingPathComponent("Tests", isDirectory: true)
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("SampleDataFixture.json", isDirectory: false),
            sourceDirectory
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("SampleDataFixture.json", isDirectory: false)
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private final class BundleToken {}
}
#endif
