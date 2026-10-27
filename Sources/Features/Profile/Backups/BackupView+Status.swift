import SwiftUI

extension BackupView {
    var localBackupDate: Date? {
        guard localBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: localBackupLastSuccessAt)
    }

    var backupStatusItems: [DataSafetyStatusItem] {
        var items: [DataSafetyStatusItem] = [
            DataSafetyStatusItem(
                title: AppLocalization.string("上次备份"),
                value: localBackupDate.map(formatDataSafetyDate) ?? AppLocalization.string("尚未完成"),
                tone: localBackupDate == nil ? .warning : .success
            ),
            DataSafetyStatusItem(
                title: AppLocalization.string("缺失文件"),
                value: estimateState.backupEstimate.missingFiles.isEmpty
                    ? AppLocalization.string("0 个")
                    : String(format: AppLocalization.string("%lld 个"), Int64(estimateState.backupEstimate.missingFiles.count)),
                tone: estimateState.backupEstimate.missingFiles.isEmpty ? .success : .warning
            ),
        ]

        if selectedBackupSection == .cloud {
            items.append(
                DataSafetyStatusItem(
                    title: AppLocalization.string("云端最近成功"),
                    value: cloudLastSuccessDate.map(formatDataSafetyDate) ?? AppLocalization.string("尚未完成"),
                    tone: cloudLastSuccessDate == nil ? .warning : .success
                )
            )
            items.append(
                DataSafetyStatusItem(
                    title: AppLocalization.string("下次自动备份"),
                    value: cloudAutoInterval == .disabled
                        ? AppLocalization.string("已关闭")
                        : cloudNextAutoBackupDate.map(formatDataSafetyDate) ?? AppLocalization.string("等待首次成功"),
                    tone: cloudAutoInterval == .disabled ? .neutral : .doc
                )
            )
            items.append(
                DataSafetyStatusItem(
                    title: AppLocalization.string("自动备份状态"),
                    value: normalizedCloudAutoStatus,
                    tone: cloudAutoStatusTone
                )
            )
        } else {
            items.append(
                DataSafetyStatusItem(
                    title: AppLocalization.string("当前环节"),
                    value: selectedBackupSection.displayName,
                    tone: .primary
                )
            )
        }

        return items
    }

    var normalizedCloudAutoStatus: String {
        let trimmed = cloudAutoLastStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.string("未记录") : trimmed
    }

    var cloudAutoStatusTone: StatusChipTone {
        let trimmed = cloudAutoLastStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .neutral }
        if trimmed.contains(AppLocalization.string("失败")) || trimmed.contains(AppLocalization.string("未能")) {
            return .warning
        }
        if trimmed.contains(AppLocalization.string("成功")) || trimmed.contains(AppLocalization.string("完成")) {
            return .success
        }
        return .doc
    }
}
