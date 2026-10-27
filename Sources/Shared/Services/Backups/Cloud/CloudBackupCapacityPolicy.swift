import Foundation

enum CloudBackupCapacityPolicy {
    private static let capacityReserveBytes: Int64 = 256 * 1024 * 1024
    private static let estimationSafetyFactorNumerator: Int64 = 12
    private static let estimationSafetyFactorDenominator: Int64 = 10

    static func evaluate(snapshot: BackupSnapshot) -> CloudBackupExecutionGateDecision {
        let estimate = BackupArchiveService.estimateArchive(from: snapshot)
        let estimatedBytes = Int64(max(estimate.estimatedBytes, 0))
        guard estimatedBytes > 0 else { return .allow }

        guard let availableBytes = availableCapacityBytes() else {
            return .allow
        }

        let requiredBytes = estimatedBytes * estimationSafetyFactorNumerator / estimationSafetyFactorDenominator + capacityReserveBytes
        guard availableBytes < requiredBytes else {
            return .allow
        }

        return .skip(
            statusMessage: "自动备份已跳过：本机可用空间不足（预计需 \(formattedBytes(requiredBytes))，可用 \(formattedBytes(availableBytes))）。"
        )
    }

    private static func availableCapacityBytes() -> Int64? {
        let probeURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        do {
            let values = try probeURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
                return importantUsage
            }
            if let fallback = values.volumeAvailableCapacity {
                return Int64(fallback)
            }
            return nil
        } catch {
            StorageIssueLog.recordEvent(
                "cloud_backup.capacity_probe_failed",
                category: .cloudBackup,
                details: ["source": "CloudBackupCapacityPolicy.availableCapacityBytes"],
                error: error
            )
            return nil
        }
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
