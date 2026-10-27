import Foundation

extension DataStore {
    func scheduleSave() {
        invalidateDataHealthScan()
        refreshSearchIndexVersion()
        dataVersion = UUID()
        scheduleDataHealthScan(reason: .dataChanged)
        let now = autosaveClock.now
        autosaveLastMutationAt = now
        if autosaveFirstMutationAt == nil {
            autosaveFirstMutationAt = now
        }
        guard scheduledSaveTask == nil else { return }
        scheduledSaveTask = Task { [weak self] in
            await self?.runScheduledSaveLoop()
        }
    }

    func runScheduledSaveLoop() async {
        defer { scheduledSaveTask = nil }
        let minimumPollInterval: Duration = .milliseconds(120)
        while !Task.isCancelled {
            guard let firstMutationAt = autosaveFirstMutationAt,
                  let lastMutationAt = autosaveLastMutationAt else {
                return
            }
            let now = autosaveClock.now
            let idleElapsed = now - lastMutationAt
            let totalElapsed = now - firstMutationAt
            if idleElapsed >= autosaveDebounceInterval || totalElapsed >= autosaveMaxLatency {
                break
            }

            let idleRemaining = autosaveDebounceInterval - idleElapsed
            let maxRemaining = autosaveMaxLatency - totalElapsed
            var sleepDuration = idleRemaining < maxRemaining ? idleRemaining : maxRemaining
            if sleepDuration < minimumPollInterval {
                sleepDuration = minimumPollInterval
            }
            do {
                try await Task.sleep(for: sleepDuration)
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        let hadPendingChanges = autosaveLastMutationAt != nil
        autosaveFirstMutationAt = nil
        autosaveLastMutationAt = nil
        guard hadPendingChanges else { return }
        save(includePhotoFiles: false)
    }

    func cancelScheduledSave() {
        scheduledSaveTask?.cancel()
        scheduledSaveTask = nil
        autosaveFirstMutationAt = nil
        autosaveLastMutationAt = nil
    }
}
