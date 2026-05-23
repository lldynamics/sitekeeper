import Foundation

final class TaskCancellationRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

struct FileIOTaskLogContext {
    let event: String
    let source: String
    var category: StorageIssueCategory = .fileStorage
    var details: [String: String] = [:]
    var logCancellation: Bool = false
}

enum FileIOTaskRunner {
    static func run<T>(
        priority: TaskPriority = .utility,
        logContext: FileIOTaskLogContext? = nil,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try await operation()
        }
        return try await awaitTask(task, logContext: logContext) {
            task.cancel()
        }
    }

    static func runWithRelay<T>(
        priority: TaskPriority = .utility,
        logContext: FileIOTaskLogContext? = nil,
        operation: @escaping @Sendable (TaskCancellationRelay) async throws -> T
    ) async throws -> T {
        let relay = TaskCancellationRelay()
        let task = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try await operation(relay)
        }
        return try await awaitTask(task, logContext: logContext) {
            relay.cancel()
            task.cancel()
        }
    }

    private static func awaitTask<T>(
        _ task: Task<T, Error>,
        logContext: FileIOTaskLogContext?,
        onCancel: @escaping @Sendable () -> Void
    ) async throws -> T {
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                onCancel()
                recordCancellationIfNeeded(logContext)
            }
        } catch {
            if shouldTreatAsCancellation(error) {
                recordCancellationIfNeeded(logContext)
            } else {
                recordFailureIfNeeded(logContext, error: error)
            }
            throw error
        }
    }

    private static func shouldTreatAsCancellation(_ error: Error) -> Bool {
        error is CancellationError || Task.isCancelled
    }

    private static func recordFailureIfNeeded(
        _ context: FileIOTaskLogContext?,
        error: Error
    ) {
        guard let context else { return }
        var details = context.details
        details["source"] = context.source
        StorageIssueLog.recordEvent(
            "\(context.event).detached_failed",
            category: context.category,
            details: details,
            error: error
        )
    }

    private static func recordCancellationIfNeeded(_ context: FileIOTaskLogContext?) {
        guard let context, context.logCancellation else { return }
        var details = context.details
        details["source"] = context.source
        StorageIssueLog.recordEvent(
            "\(context.event).detached_cancelled",
            category: context.category,
            details: details
        )
    }
}

enum DebouncedTask {
    static func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
