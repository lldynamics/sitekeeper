import Foundation

extension DataStore {
    /// Invalidate immediately on mutation, before the debounce starts. A cancelled
    /// filesystem call may finish, but its result can never replace newer state.
    func invalidateDataHealthScan() {
        dataHealthScanTask?.cancel()
        dataHealthScanTask = nil
        dataHealthScanGeneration = UUID()
    }

    func scheduleDataHealthScan(
        reason: DataHealthScanReason = .dataChanged,
        delay: Duration? = nil
    ) {
        // Saving the same revision need not restart an already queued/running scan.
        // Actual domain mutations invalidate the task before calling scheduleSave.
        if reason == .dataChanged, dataHealthScanTask != nil { return }
        startDataHealthScan(reason: reason, delay: delay ?? dataHealthScanDebounceInterval)
    }

    func scheduleDataHealthScanIfStale(
        reason: DataHealthScanReason = .scheduled,
        maxAge: TimeInterval? = nil
    ) {
        let ageLimit = maxAge ?? dataHealthScheduledScanMaxAge
        guard let completedAt = dataHealthLastCompletedAt ?? latestDataHealthScan?.scannedAt else {
            scheduleDataHealthScan(reason: reason, delay: .zero)
            return
        }
        guard Date().timeIntervalSince(completedAt) >= ageLimit else { return }
        scheduleDataHealthScan(reason: reason, delay: .zero)
    }

    func runDataHealthScanNow(reason: DataHealthScanReason = .manual) {
        startDataHealthScan(reason: reason, delay: .zero)
    }

    /// Returns nil if superseded or cancelled; callers must not report repair
    /// counts using a stale scan. No filesystem enumeration runs on MainActor.
    @discardableResult
    func scanDataHealthNow(
        reason: DataHealthScanReason = .manual,
        includeSupplementalMetrics: Bool = true
    ) async -> DataHealthScanSummary? {
        let task = startDataHealthScan(
            reason: reason, delay: .zero,
            includeSupplementalMetrics: includeSupplementalMetrics
        )
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult
    private func startDataHealthScan(
        reason: DataHealthScanReason,
        delay: Duration,
        includeSupplementalMetrics: Bool? = nil
    ) -> Task<DataHealthScanSummary?, Never> {
        invalidateDataHealthScan()
        let generation = dataHealthScanGeneration
        // A mutation interrupting a manual/startup scan must not lose its metrics refresh.
        dataHealthSupplementalScanPending = dataHealthSupplementalScanPending
            || (includeSupplementalMetrics ?? (reason != .dataChanged))
        let task = Task(priority: .utility) { [weak self] () -> DataHealthScanSummary? in
            guard let self else { return nil }
            defer {
                if generation == self.dataHealthScanGeneration { self.dataHealthScanTask = nil }
            }
            do { try await Task.sleep(for: delay) } catch { return nil }
            guard !Task.isCancelled,
                  self.loadState == .ready, !self.isApplyingBackup,
                  generation == self.dataHealthScanGeneration else { return nil }
            let revision = self.dataVersion
            let includeMetrics = self.dataHealthSupplementalScanPending
            let input = DataHealthScanInput(store: self)
            guard let scanned = try? await self.dataHealthWorker.scan(
                input: input, reason: reason, includeSupplementalMetrics: includeMetrics
            ), !Task.isCancelled,
                generation == self.dataHealthScanGeneration,
                revision == self.dataVersion,
                self.loadState == .ready, !self.isApplyingBackup else { return nil }
            let summary = includeMetrics
                ? scanned : scanned.fillingSupplementalMetrics(from: self.latestDataHealthScan)
            self.dataHealthLastCompletedAt = scanned.scannedAt
            self.dataHealthSupplementalScanPending = false
            // Keep automatic no-op scans from invalidating every dashboard observer.
            // Explicit scans still publish their completion timestamp and reason.
            if reason == .dataChanged, let previous = self.latestDataHealthScan,
               summary.hasSameFindings(as: previous) { return summary }
            let snapshot = DataHealthScanSnapshot(
                summary: summary,
                fallbackStorageUsage: self.latestDataHealthSnapshot?.storageUsage,
                fallbackWidgetHealth: self.latestDataHealthSnapshot?.widgetHealth
            )
            if self.latestDataHealthSnapshot != snapshot { self.latestDataHealthSnapshot = snapshot }
            if self.latestDataHealthScan != summary { self.latestDataHealthScan = summary }
            return summary
        }
        dataHealthScanTask = task
        return task
    }
}
