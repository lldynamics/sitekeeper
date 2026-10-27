import Foundation

actor CloudAutoBackupScheduler {
    static let shared = CloudAutoBackupScheduler()
    private var isRunning = false
    private let operation: @Sendable (DataStore) async -> Void

    init(operation: @escaping @Sendable (DataStore) async -> Void = { store in await CloudAutoBackupJob.run(store: store) }) {
        self.operation = operation
    }

    func triggerIfNeeded(store: DataStore) async {
        await store.awaitInitialLoad()
        guard !Task.isCancelled, await store.canEditBusinessData else { return }
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        await operation(store)
    }
}

/// Cloud side effects are separate from launch readiness and single-flight coordination.
private enum CloudAutoBackupJob {
    private static let retryCooldown: TimeInterval = 30 * 60

    static func run(store: DataStore) async {
        let hasData = await MainActor.run { store.hasAnyBusinessData }
        let interval = CloudBackupSettingsStore.loadAutoInterval()
        let now = Date()
        let options = CloudBackupSettingsStore.loadContentOptions()
        guard hasData, interval != .disabled, await refreshPendingUploads() else { return }
        guard shouldContinue(CloudBackupExecutionGate.evaluateSchedule(
            hasData: hasData,
            interval: interval,
            now: now,
            lastSuccess: CloudBackupSettingsStore.loadLastSuccessDate(),
            lastAttempt: CloudBackupSettingsStore.loadAutoLastAttemptDate(),
            retryCooldown: retryCooldown,
            options: options
        )) else { return }

        let requiresWiFi = CloudBackupSettingsStore.loadAutoBackupRequiresWiFi()
        guard shouldContinue(await CloudBackupExecutionGate.evaluateEnvironment(requiresWiFi: requiresWiFi)) else { return }

        CloudBackupSettingsStore.saveAutoLastAttemptDate(now)

        do {
            let result = try await store.withBackupExport {
                let snapshot = store.makeCloudBackupSnapshot(options: options)
                guard Self.shouldContinue(CloudBackupExecutionGate.evaluateSnapshot(snapshot)) else {
                    return nil as CloudBackupExecutionResult?
                }
                return try await CloudBackupCoordinator.shared.backupToCloud(snapshot: snapshot)
            }
            guard let result else { return }
            CloudBackupSettingsStore.saveAutoLastStatus(result.savedFile.uploadState.statusMessage)
        } catch {
            let failedAt = Date()
            CloudBackupSettingsStore.saveAutoLastStatus("自动备份失败（\(Formatters.dateTime.string(from: failedAt))）：\(error.localizedDescription)")
        }
    }
    private static func shouldContinue(_ decision: CloudBackupExecutionGateDecision) -> Bool {
        switch decision {
        case .allow:
            return true
        case .skip(let message):
            if let message, !message.isEmpty { CloudBackupSettingsStore.saveAutoLastStatus(message) }
            return false
        }
    }

    private static func refreshPendingUploads() async -> Bool {
        do {
            let files = try await FileIOTaskRunner.run(priority: .utility) {
                try CloudBackupService.refreshUploadStatusAndPrune(keepMostRecent: CloudBackupSettingsStore.loadRetentionCount())
            }
            if let message = CloudBackupRetentionPolicy.automaticBackupBlockReason(in: files, pendingFileName: CloudBackupSettingsStore.loadPendingFileName()) {
                CloudBackupSettingsStore.saveAutoLastStatus(message)
                return false
            }
        } catch {
            if !CloudBackupSettingsStore.loadPendingFileName().isEmpty {
                CloudBackupSettingsStore.saveAutoLastStatus(CloudBackupRetentionPolicy.unconfirmedStatusMessage)
                return false
            }
        }
        return true
    }
}
