import Foundation

enum RepositoryWorkspaceExport {
    /// Retain the open-repository lease until archiving is complete. The caller also
    /// holds DataStore's export lease to keep the referenced original assets alive.
    static func prepare(_ entry: RepositoryWorkspaceEntry, catalog: RepositoryWorkspaceCatalog) async throws -> BackupExportOutcome {
        let repository = try await catalog.open(entry)
        do {
            let snapshot = try await repository.exportSnapshot()
            let outcome = try await BackupExportCoordinator.exportBackup(
                snapshot: snapshot,
                suggestedFileName: "\(AppBrand.exportFilePrefix)_\(entry.id.uuidString.prefix(8)).zip",
                progress: { _ in },
                shouldCancel: { Task.isCancelled }
            )
            do { try await repository.close() } catch {
                ExportFileURLPreparer.cleanup(fileURL: outcome.preparedFileURL)
                throw error
            }
            return outcome
        } catch {
            try? await repository.close()
            throw error
        }
    }
}
