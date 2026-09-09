import Foundation

extension DataStore {
    func flushSaveOrThrow() async throws {
        cancelScheduledSave()
        persistTask?.cancel()
        await awaitInitialLoad()
        guard loadState == .ready, !isApplyingBackup else {
            throw PersistenceBlockedError(message: persistenceErrorMessage)
        }
        let snapshot = makeSnapshot(includePhotoFiles: false)
        do {
            try await persistenceActor.persist(snapshot: snapshot)
        } catch {
            persistenceErrorMessage = String(
                format: String(localized: "保存本地数据失败：%@"),
                error.localizedDescription
            )
            throw error
        }
        publishWidgetData()
        scheduleDataHealthScan(reason: .dataChanged)
    }

    func flushSave() async {
        do {
            try await flushSaveOrThrow()
        } catch {
            // flushSaveOrThrow 已写入 persistenceErrorMessage
        }
    }

    func save(includePhotoFiles: Bool = false) {
        if let initialLoadTask, !initialLoadTask.isCancelled {
            needsSaveAfterInitialLoad = true
            return
        }
        guard loadState == .ready, !isApplyingBackup else { return }
        let snapshot = makeSnapshot(includePhotoFiles: includePhotoFiles)
        latestPersistToken += 1
        let persistToken = latestPersistToken
        let persistenceActor = self.persistenceActor

        persistTask?.cancel()
        persistTask = Task(priority: .utility) {
            do {
                try await persistenceActor.persist(snapshot: snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          persistToken == self.latestPersistToken else { return }
                    self.persistenceErrorMessage = String(
                        format: String(localized: "保存本地数据失败：%@"),
                        error.localizedDescription
                    )
                }
            }
        }
        publishWidgetData()
        scheduleDataHealthScan(reason: .dataChanged)
    }
}

extension DataStore {
    struct PersistenceBlockedError: LocalizedError {
        let message: String?
        var errorDescription: String? {
            message ?? String(localized: "本地数据尚未安全加载或正在恢复，已暂停保存。")
        }
    }

    /// Only a user-confirmed backup transaction may replace a store that failed to load.
    func persistAppliedBackup(encodedData: Data? = nil) async throws {
        try Task.checkCancellation()
        let wasFailed = loadState == .failed
        if let encodedData {
            try await persistenceActor.persistPreparedBackup(data: encodedData, preservingExistingFile: wasFailed)
        } else {
            try await persistenceActor.persist(
                snapshot: makeSnapshot(includePhotoFiles: false), preservingExistingFile: wasFailed
            )
        }
        setLoadState(.ready)
        persistenceErrorMessage = nil
        publishWidgetData()
        scheduleDataHealthScan(reason: .dataChanged)
    }
}
