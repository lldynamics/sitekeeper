import Foundation

struct RepositoryWorkspaceEntry: Identifiable, Sendable {
    let id: UUID
    let directory: URL
    let createdAt: Date
    var byteCount: Int64 = 0
}

/// Disk discovery and opening (including schema upgrades) stay off MainActor.
actor RepositoryWorkspaceCatalog {
    func entries(beside source: URL) throws -> [RepositoryWorkspaceEntry] {
        let root = source.deletingLastPathComponent().appendingPathComponent(".sqlite-candidates", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RepositoryError.invalidCandidate }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]).compactMap { directory in
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                  let id = UUID(uuidString: directory.lastPathComponent) else { return nil }
            let data = try? CandidateFiles.readRegularFile(directory.appendingPathComponent("candidate.json"))
            guard let data, let manifest = try? JSONDecoder().decode(SQLiteCandidateManifest.self, from: data),
                  manifest.id == id, manifest.version == 1, manifest.phase == .ready else { return nil }
            return RepositoryWorkspaceEntry(id: id, directory: directory, createdAt: manifest.createdAt, byteCount: try RepositoryWorkspaceMaintenance.byteCount(in: directory))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func open(_ entry: RepositoryWorkspaceEntry) throws -> SQLiteBusinessRepository {
        try SQLiteBusinessRepository(candidateDirectory: entry.directory)
    }

    func create(source: URL, assets: [RepositoryAssetFamily: URL]) async throws -> RepositoryWorkspaceEntry {
        let result = try await SQLiteCandidateBuilder().build(sourceURL: source, assetDirectories: assets)
        return RepositoryWorkspaceEntry(id: result.manifest.id, directory: result.directory, createdAt: result.manifest.createdAt)
    }
}
