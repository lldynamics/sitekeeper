import Foundation

/// The application-import sequence, independent of SwiftUI, archive storage, and
/// business record models. Its live adapter owns those dependencies.
enum BackupImportWorkflowMode: String, Sendable {
    case merge
    case overwrite
}

enum BackupImportWorkflowPhase: String, Sendable {
    case readingMetadata = "reading_metadata"
    case stagingFiles = "staging_files"
    case applyingMetadata = "applying_metadata"
    case committingFiles = "committing_files"
    case persistingMetadata = "persisting_metadata"
    case cleaningOverwrittenFiles = "cleaning_overwritten_files"
}

struct BackupImportWorkflowProgress: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64
    let currentItem: String
}

enum BackupImportWorkflowEvent: Equatable, Sendable {
    case phase(BackupImportWorkflowPhase)
    case progress(BackupImportWorkflowPhase, BackupImportWorkflowProgress)
}

struct BackupImportWorkflowContext<Metadata> {
    let previousMetadata: Metadata
    let mode: BackupImportWorkflowMode
    let overwrittenFileCount: Int
}

struct BackupImportWorkflowResult: Equatable, Sendable {
    let mode: BackupImportWorkflowMode
    let restoredFileCount: Int
    let overwrittenFileCount: Int
}

struct BackupImportWorkflowFailure: Error {
    let phase: BackupImportWorkflowPhase
    let auditExtra: String?
    let underlyingError: Error
    /// Only pre-commit cancellation permits a "data unchanged" presentation.
    /// Once commit starts, its transaction layer owns persistence and recovery.
    let cancelledBeforeCommit: Bool
}

@MainActor
protocol BackupImportWorkflowOperations {
    associatedtype Metadata
    associatedtype StagedFiles

    func readMetadata(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> Metadata
    func captureContext(importedMetadata: Metadata) -> BackupImportWorkflowContext<Metadata>
    func stageFiles(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> StagedFiles
    func stagedFileCount(_ files: StagedFiles) -> Int
    func cancelStagedFiles(_ files: StagedFiles)
    func commit(
        _ files: StagedFiles,
        importedMetadata: Metadata,
        context: BackupImportWorkflowContext<Metadata>,
        sourceFileName: String,
        onPersistingMetadata: @escaping @MainActor () -> Void
    ) async throws -> Int
    func cleanupOverwrittenFiles(context: BackupImportWorkflowContext<Metadata>, importedMetadata: Metadata)
    func isCancellation(_ error: Error) -> Bool
}

extension BackupImportWorkflowOperations {
    func isCancellation(_ error: Error) -> Bool { error is CancellationError }
}

@MainActor
enum BackupImportWorkflow {
    static func run<Operations: BackupImportWorkflowOperations>(
        sourceURL: URL,
        preparedMetadata: Operations.Metadata?,
        operations: Operations,
        onEvent: @escaping @MainActor (BackupImportWorkflowEvent) -> Void
    ) async throws -> BackupImportWorkflowResult {
        let events = EventRelay(onEvent: onEvent)
        defer { events.close() }
        var auditExtra: String?
        var commitStarted = false
        do {
            let metadata = try await resolveMetadata(sourceURL, prepared: preparedMetadata, operations: operations, events: events)
            // Preserve the two cancellation boundaries of the existing apply flow:
            // after metadata and after staging, before any metadata/file commit.
            try Task.checkCancellation()
            let context = operations.captureContext(importedMetadata: metadata)
            auditExtra = "mode=\(context.mode.rawValue)"
            events.transition(to: .stagingFiles)
            let files = try await prepareFiles(sourceURL, operations: operations, events: events)
            events.transition(to: .applyingMetadata)
            auditExtra = "restore=\(operations.stagedFileCount(files))"
            events.transition(to: .committingFiles)
            commitStarted = true
            let restoredCount = try await operations.commit(
                files,
                importedMetadata: metadata,
                context: context,
                sourceFileName: sourceURL.lastPathComponent,
                onPersistingMetadata: {
                    auditExtra = nil
                    events.transition(to: .persistingMetadata)
                }
            )
            // A successful transaction may finish after cancellation was requested.
            // Continue its success path; never relabel committed data as unchanged.
            auditExtra = "remove=\(context.overwrittenFileCount)"
            events.transition(to: .cleaningOverwrittenFiles)
            if context.mode == .overwrite {
                operations.cleanupOverwrittenFiles(context: context, importedMetadata: metadata)
            }
            return BackupImportWorkflowResult(
                mode: context.mode,
                restoredFileCount: restoredCount,
                overwrittenFileCount: context.overwrittenFileCount
            )
        } catch {
            throw BackupImportWorkflowFailure(
                phase: events.phase,
                auditExtra: auditExtra,
                underlyingError: error,
                cancelledBeforeCommit: !commitStarted && (Task.isCancelled || operations.isCancellation(error))
            )
        }
    }

    private static func resolveMetadata<Operations: BackupImportWorkflowOperations>(
        _ sourceURL: URL,
        prepared: Operations.Metadata?,
        operations: Operations,
        events: EventRelay
    ) async throws -> Operations.Metadata {
        if let prepared { return prepared }
        return try await operations.readMetadata(from: sourceURL) { progress in
            events.progress(progress, for: .readingMetadata)
        }
    }

    private static func prepareFiles<Operations: BackupImportWorkflowOperations>(
        _ sourceURL: URL,
        operations: Operations,
        events: EventRelay
    ) async throws -> Operations.StagedFiles {
        let files = try await operations.stageFiles(from: sourceURL) { progress in
            events.progress(progress, for: .stagingFiles)
        }
        if Task.isCancelled {
            operations.cancelStagedFiles(files)
            throw CancellationError()
        }
        return files
    }

    /// Archive workers can enqueue progress before a stage completes. Ignore those
    /// callbacks once the workflow advances or terminates, so late progress cannot
    /// overwrite the final result or a later stage's presentation.
    @MainActor
    private final class EventRelay {
        private(set) var phase = BackupImportWorkflowPhase.readingMetadata
        private var isOpen = true
        private let onEvent: @MainActor (BackupImportWorkflowEvent) -> Void

        init(onEvent: @escaping @MainActor (BackupImportWorkflowEvent) -> Void) {
            self.onEvent = onEvent
        }

        func transition(to phase: BackupImportWorkflowPhase) {
            guard isOpen else { return }
            self.phase = phase
            onEvent(.phase(phase))
        }

        func progress(_ progress: BackupImportWorkflowProgress, for phase: BackupImportWorkflowPhase) {
            guard isOpen, self.phase == phase else { return }
            onEvent(.progress(phase, progress))
        }

        func close() { isOpen = false }
    }
}
