import Foundation

enum CloudBackupBatteryPolicy {
    static func evaluate() -> CloudBackupExecutionGateDecision {
        guard ProcessInfo.processInfo.isLowPowerModeEnabled else {
            return .allow
        }
        return .skip(statusMessage: "自动备份已跳过：当前为低电量模式。")
    }
}
