import Foundation

enum CloudBackupExecutionGateDecision {
    case allow
    case skip(statusMessage: String?)
}

enum CloudBackupExecutionGate {
    static func evaluateSchedule(
        hasData: Bool,
        interval: CloudBackupAutoInterval,
        now: Date,
        lastSuccess: Date?,
        lastAttempt: Date?,
        retryCooldown: TimeInterval,
        options: CloudBackupContentOptions
    ) -> CloudBackupExecutionGateDecision {
        guard hasData else { return .skip(statusMessage: nil) }
        guard let minimumInterval = interval.minimumInterval else {
            return .skip(statusMessage: nil)
        }
        if let lastSuccess, now.timeIntervalSince(lastSuccess) < minimumInterval {
            return .skip(statusMessage: nil)
        }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryCooldown {
            return .skip(statusMessage: nil)
        }
        guard options.hasSelectedContent else {
            return .skip(statusMessage: "自动备份已跳过：请先选择需要备份的内容。")
        }
        return .allow
    }

    static func evaluateEnvironment(requiresWiFi: Bool) async -> CloudBackupExecutionGateDecision {
        switch CloudBackupBatteryPolicy.evaluate() {
        case .allow:
            break
        case .skip(let statusMessage):
            return .skip(statusMessage: statusMessage)
        }

        switch await CloudBackupNetworkPolicy.evaluate(requiresWiFi: requiresWiFi) {
        case .allow:
            return .allow
        case .skip(let statusMessage):
            return .skip(statusMessage: statusMessage)
        }
    }

    static func evaluateSnapshot(_ snapshot: BackupSnapshot) -> CloudBackupExecutionGateDecision {
        guard snapshot.hasAnyBackupContent else {
            return .skip(statusMessage: "自动备份已跳过：当前所选范围暂无可备份数据。")
        }

        switch CloudBackupCapacityPolicy.evaluate(snapshot: snapshot) {
        case .allow:
            return .allow
        case .skip(let statusMessage):
            return .skip(statusMessage: statusMessage)
        }
    }
}
