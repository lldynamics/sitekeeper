import Foundation

extension DataStore {
    func scheduleDataHealthScan(
        reason: DataHealthScanReason = .dataChanged,
        delay: Duration? = nil
    ) {
        dataHealthScanTask?.cancel()
        let effectiveDelay = delay ?? dataHealthScanDebounceInterval
        dataHealthScanTask = Task { [weak self] in
            do {
                try await Task.sleep(for: effectiveDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.performDataHealthScan(reason: reason)
        }
    }

    func scheduleDataHealthScanIfStale(
        reason: DataHealthScanReason = .scheduled,
        maxAge: TimeInterval? = nil
    ) {
        let ageLimit = maxAge ?? dataHealthScheduledScanMaxAge
        guard let latestDataHealthScan else {
            scheduleDataHealthScan(reason: reason, delay: .zero)
            return
        }
        guard Date().timeIntervalSince(latestDataHealthScan.scannedAt) >= ageLimit else { return }
        scheduleDataHealthScan(reason: reason, delay: .zero)
    }

    func runDataHealthScanNow(reason: DataHealthScanReason = .manual) {
        scheduleDataHealthScan(reason: reason, delay: .zero)
    }

    @discardableResult
    func scanDataHealthNow(
        reason: DataHealthScanReason = .manual,
        includeSupplementalMetrics: Bool = true
    ) -> DataHealthScanSummary {
        let scanned = DataHealthScanner.scan(
            input: DataHealthScanInput(store: self),
            reason: reason,
            includeSupplementalMetrics: includeSupplementalMetrics
        )
        let summary = includeSupplementalMetrics
            ? scanned
            : scanned.fillingSupplementalMetrics(from: latestDataHealthScan)
        latestDataHealthScan = summary
        return summary
    }

    private func performDataHealthScan(reason: DataHealthScanReason) {
        let includeSupplementalMetrics: Bool
        switch reason {
        case .dataChanged:
            includeSupplementalMetrics = false
        case .startup, .scheduled, .manual:
            includeSupplementalMetrics = true
        }
        _ = scanDataHealthNow(reason: reason, includeSupplementalMetrics: includeSupplementalMetrics)
    }
}
