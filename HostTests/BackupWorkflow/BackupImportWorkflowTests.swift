import Foundation
import Testing
@testable import BackupWorkflowCore

@MainActor
struct BackupImportWorkflowTests {
    private let sourceURL = URL(fileURLWithPath: "/unopened-fixture/import.zip")

    @Test func preparedMetadataSkipsArchiveReadAndMergeKeepsLocalFiles() async throws {
        let operations = WorkflowOperationsFake()
        var events: [BackupImportWorkflowEvent] = []
        let result = try await BackupImportWorkflow.run(
            sourceURL: sourceURL,
            preparedMetadata: "preview metadata",
            operations: operations,
            onEvent: { events.append($0) }
        )
        #expect(operations.calls == ["capture", "stage", "commit", "persist"])
        #expect(operations.importedMetadata == "preview metadata")
        #expect(operations.committedContext?.previousMetadata == "local metadata")
        #expect(operations.committedSourceName == "import.zip")
        #expect(result == BackupImportWorkflowResult(mode: .merge, restoredFileCount: 4, overwrittenFileCount: 0))
        #expect(events == [
            .phase(.stagingFiles), .phase(.applyingMetadata), .phase(.committingFiles),
            .phase(.persistingMetadata), .phase(.cleaningOverwrittenFiles)
        ])
        #expect(operations.cancelledStagingCount == 0)
    }

    @Test func fallbackMetadataIsReadBeforeCapturingCurrentLocalStateAndMode() async throws {
        let operations = WorkflowOperationsFake()
        operations.afterReading = {
            operations.localMetadata = "state after archive read"
            operations.mode = .overwrite
        }
        let result = try await BackupImportWorkflow.run(
            sourceURL: sourceURL, preparedMetadata: nil, operations: operations, onEvent: { _ in }
        )
        #expect(operations.calls == ["read", "capture", "stage", "commit", "persist", "cleanup"])
        #expect(operations.importedMetadata == "archive metadata")
        #expect(operations.committedContext?.previousMetadata == "state after archive read")
        #expect(result.mode == .overwrite)
        #expect(result.overwrittenFileCount == 7)
        #expect(operations.cleanedContext?.previousMetadata == "state after archive read")
        #expect(operations.cleanedMetadata == "archive metadata")
    }

    @Test func failuresKeepTheStageAndOriginalErrorAndNeverCleanup() async {
        for phase in [BackupImportWorkflowPhase.readingMetadata, .stagingFiles, .committingFiles, .persistingMetadata] {
            let operations = WorkflowOperationsFake()
            operations.failurePhase = phase
            do {
                _ = try await BackupImportWorkflow.run(
                    sourceURL: sourceURL, preparedMetadata: nil, operations: operations, onEvent: { _ in }
                )
                Issue.record("Expected a failure at \(phase.rawValue)")
            } catch let failure as BackupImportWorkflowFailure {
                #expect(failure.phase == phase)
                #expect(failure.underlyingError as? WorkflowTestError == .injected)
                #expect(!failure.cancelledBeforeCommit)
                switch phase {
                case .readingMetadata, .persistingMetadata:
                    #expect(failure.auditExtra == nil)
                case .stagingFiles:
                    #expect(failure.auditExtra == "mode=merge")
                case .committingFiles:
                    #expect(failure.auditExtra == "restore=4")
                default:
                    Issue.record("Unexpected test phase")
                }
            } catch {
                Issue.record("Lost the workflow failure context: \(error)")
            }
            #expect(!operations.calls.contains("cleanup"))
            // Commit/rollback belongs to the existing transaction implementation.
            #expect(operations.cancelledStagingCount == 0)
        }
    }

    @Test func cancellationAfterMetadataNeverCapturesOrStages() async {
        let operations = WorkflowOperationsFake()
        operations.cancelDuring = .readingMetadata
        let task = Task { @MainActor in
            try await BackupImportWorkflow.run(
                sourceURL: sourceURL, preparedMetadata: nil, operations: operations, onEvent: { _ in }
            )
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch let failure as BackupImportWorkflowFailure {
            #expect(failure.cancelledBeforeCommit)
            #expect(failure.phase == .readingMetadata)
        } catch {
            Issue.record("Lost cancellation context: \(error)")
        }
        #expect(operations.calls == ["read"])
    }

    @Test func cancellationAfterStagingCancelsOnlyThePreparedFiles() async {
        let operations = WorkflowOperationsFake()
        operations.cancelDuring = .stagingFiles
        let task = Task { @MainActor in
            try await BackupImportWorkflow.run(
                sourceURL: sourceURL, preparedMetadata: "preview", operations: operations, onEvent: { _ in }
            )
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch let failure as BackupImportWorkflowFailure {
            #expect(failure.cancelledBeforeCommit)
            #expect(failure.phase == .stagingFiles)
            #expect(failure.auditExtra == "mode=merge")
        } catch {
            Issue.record("Lost cancellation context: \(error)")
        }
        #expect(operations.calls == ["capture", "stage", "cancel-stage"])
        #expect(operations.cancelledStagingCount == 1)
        #expect(operations.committedContext == nil)
    }

    @Test func archiveCancellationBeforeCommitRemainsCancellation() async {
        let operations = WorkflowOperationsFake()
        operations.archiveCancellation = true
        do {
            _ = try await BackupImportWorkflow.run(
                sourceURL: sourceURL, preparedMetadata: "preview", operations: operations, onEvent: { _ in }
            )
            Issue.record("Expected archive cancellation")
        } catch let failure as BackupImportWorkflowFailure {
            #expect(failure.cancelledBeforeCommit)
            #expect(failure.phase == .stagingFiles)
            #expect(failure.underlyingError as? WorkflowTestError == .archiveCancelled)
        } catch {
            Issue.record("Lost archive cancellation context: \(error)")
        }
        #expect(!operations.calls.contains("commit"))
    }

    @Test func successfulCommitWinsOverLateCancellationAndStillCleansOverwriteFiles() async throws {
        for phase in [BackupImportWorkflowPhase.committingFiles, .persistingMetadata] {
            let operations = WorkflowOperationsFake()
            operations.mode = .overwrite
            operations.cancelDuring = phase
            let task = Task { @MainActor in
                try await BackupImportWorkflow.run(
                    sourceURL: sourceURL, preparedMetadata: "preview", operations: operations, onEvent: { _ in }
                )
            }
            let result = try await task.value
            #expect(result.restoredFileCount == 4)
            #expect(result.overwrittenFileCount == 7)
            #expect(operations.calls == ["capture", "stage", "commit", "persist", "cleanup"])
            #expect(operations.cancelledStagingCount == 0)
        }
    }

    @Test func commitFailureDuringCancellationKeepsRecoveryFailureInsteadOfClaimingUnchangedData() async {
        for phase in [BackupImportWorkflowPhase.committingFiles, .persistingMetadata] {
            let operations = WorkflowOperationsFake()
            operations.cancelDuring = phase
            operations.failurePhase = phase
            let task = Task { @MainActor in
                try await BackupImportWorkflow.run(
                    sourceURL: sourceURL, preparedMetadata: "preview", operations: operations, onEvent: { _ in }
                )
            }
            do {
                _ = try await task.value
                Issue.record("Expected transaction failure")
            } catch let failure as BackupImportWorkflowFailure {
                #expect(failure.phase == phase)
                #expect(failure.underlyingError as? WorkflowTestError == .injected)
                #expect(!failure.cancelledBeforeCommit)
            } catch {
                Issue.record("Lost transaction failure context: \(error)")
            }
            #expect(!operations.calls.contains("cleanup"))
            #expect(operations.cancelledStagingCount == 0)
        }
    }

    @Test func lateProgressFromEarlierStagesAndCompletedWorkflowIsIgnored() async throws {
        let operations = WorkflowOperationsFake()
        operations.emitProgress = true
        var events: [BackupImportWorkflowEvent] = []
        _ = try await BackupImportWorkflow.run(
            sourceURL: sourceURL, preparedMetadata: nil, operations: operations, onEvent: { events.append($0) }
        )
        let progressEvents = events.compactMap { event -> BackupImportWorkflowPhase? in
            if case let .progress(phase, _) = event { return phase }
            return nil
        }
        #expect(progressEvents == [.readingMetadata, .stagingFiles])
        let count = events.count
        operations.readProgress?(WorkflowOperationsFake.progress)
        operations.stageProgress?(WorkflowOperationsFake.progress)
        #expect(events.count == count)
    }

    @Test func failedWorkflowAlsoRejectsQueuedProgress() async {
        let operations = WorkflowOperationsFake()
        operations.failurePhase = .stagingFiles
        var events: [BackupImportWorkflowEvent] = []
        do {
            _ = try await BackupImportWorkflow.run(
                sourceURL: sourceURL, preparedMetadata: nil, operations: operations, onEvent: { events.append($0) }
            )
            Issue.record("Expected staging failure")
        } catch { }
        let count = events.count
        operations.readProgress?(WorkflowOperationsFake.progress)
        operations.stageProgress?(WorkflowOperationsFake.progress)
        #expect(events.count == count)
    }
}

private enum WorkflowTestError: Error, Equatable {
    case injected
    case archiveCancelled
}

@MainActor
private final class WorkflowOperationsFake: BackupImportWorkflowOperations {
    static let progress = BackupImportWorkflowProgress(completedBytes: 1, totalBytes: 2, currentItem: "fixture")
    var calls: [String] = []
    var mode = BackupImportWorkflowMode.merge
    var localMetadata = "local metadata"
    var importedMetadata: String?
    var committedContext: BackupImportWorkflowContext<String>?
    var committedSourceName: String?
    var cleanedContext: BackupImportWorkflowContext<String>?
    var cleanedMetadata: String?
    var cancelledStagingCount = 0
    var failurePhase: BackupImportWorkflowPhase?
    var cancelDuring: BackupImportWorkflowPhase?
    var archiveCancellation = false
    var emitProgress = false
    var afterReading: (() -> Void)?
    var readProgress: (@MainActor (BackupImportWorkflowProgress) -> Void)?
    var stageProgress: (@MainActor (BackupImportWorkflowProgress) -> Void)?

    func readMetadata(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> String {
        calls.append("read")
        readProgress = progress
        if emitProgress { progress(Self.progress) }
        cancelTaskIfNeeded(at: .readingMetadata)
        if failurePhase == .readingMetadata { throw WorkflowTestError.injected }
        afterReading?()
        return "archive metadata"
    }

    func captureContext(importedMetadata: String) -> BackupImportWorkflowContext<String> {
        calls.append("capture")
        self.importedMetadata = importedMetadata
        return BackupImportWorkflowContext(previousMetadata: localMetadata, mode: mode, overwrittenFileCount: mode == .overwrite ? 7 : 0)
    }

    func stageFiles(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> String {
        calls.append("stage")
        stageProgress = progress
        if emitProgress {
            readProgress?(Self.progress)
            progress(Self.progress)
        }
        cancelTaskIfNeeded(at: .stagingFiles)
        if archiveCancellation { throw WorkflowTestError.archiveCancelled }
        if failurePhase == .stagingFiles { throw WorkflowTestError.injected }
        return "staged files"
    }

    func stagedFileCount(_ files: String) -> Int { 4 }

    func cancelStagedFiles(_ files: String) {
        calls.append("cancel-stage")
        cancelledStagingCount += 1
    }

    func commit(
        _ files: String,
        importedMetadata: String,
        context: BackupImportWorkflowContext<String>,
        sourceFileName: String,
        onPersistingMetadata: @escaping @MainActor () -> Void
    ) async throws -> Int {
        calls.append("commit")
        committedContext = context
        committedSourceName = sourceFileName
        if emitProgress { stageProgress?(Self.progress) }
        cancelTaskIfNeeded(at: .committingFiles)
        if failurePhase == .committingFiles { throw WorkflowTestError.injected }
        onPersistingMetadata()
        calls.append("persist")
        cancelTaskIfNeeded(at: .persistingMetadata)
        if failurePhase == .persistingMetadata { throw WorkflowTestError.injected }
        return 4
    }

    func cleanupOverwrittenFiles(context: BackupImportWorkflowContext<String>, importedMetadata: String) {
        calls.append("cleanup")
        cleanedContext = context
        cleanedMetadata = importedMetadata
    }

    func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || error as? WorkflowTestError == .archiveCancelled
    }

    private func cancelTaskIfNeeded(at phase: BackupImportWorkflowPhase) {
        if cancelDuring == phase { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
