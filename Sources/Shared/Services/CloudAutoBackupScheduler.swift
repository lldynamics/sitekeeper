import Foundation

actor CloudAutoBackupScheduler {
    static let shared = CloudAutoBackupScheduler()
    private let retryCooldown: TimeInterval = 30 * 60
    private var isRunning = false

    func triggerIfNeeded(store: DataStore) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
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
                guard await self.shouldContinue(CloudBackupExecutionGate.evaluateSnapshot(snapshot)) else {
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
    private func shouldContinue(_ decision: CloudBackupExecutionGateDecision) -> Bool {
        switch decision {
        case .allow:
            return true
        case .skip(let message):
            if let message, !message.isEmpty { CloudBackupSettingsStore.saveAutoLastStatus(message) }
            return false
        }
    }

    private func refreshPendingUploads() async -> Bool {
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
