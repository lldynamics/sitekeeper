import Foundation

extension DataStore {
    func flushSaveOrThrow() async throws {
        cancelScheduledSave()
        persistTask?.cancel()
        await awaitInitialLoad()
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
