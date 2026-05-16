import SwiftUI

struct BackupCloudSectionView: View {
    @Binding var cloudIncludeBusinessRecords: Bool
    @Binding var cloudIncludeProjectRecords: Bool
    @Binding var cloudIncludeProjectFilesAndNotes: Bool
    @Binding var cloudIncludeKnowledgeBase: Bool
    @Binding var cloudIncludeAttachments: Bool
    @Binding var cloudAutoIntervalRawValue: String
    @Binding var cloudAutoBackupRequiresWiFi: Bool
    @Binding var cloudBackupRetentionCount: Int

    let isBusy: Bool
    let isRefreshingCloudBackups: Bool
    let cloudBackups: [CloudBackupFile]
    let cloudStatusMessage: String
    let cloudBackupScopeHint: String
    let cloudCellularTrafficHint: String
    let cloudAutoNetworkHint: String
    let cloudAutoInterval: CloudBackupAutoInterval
    let cloudLastSuccessDate: Date?
    let cloudNextAutoBackupDate: Date?
    let cloudAutoLastStatus: String
    let onUploadBackup: () -> Void
    let onRefreshBackups: () -> Void
    let onRestoreBackup: (CloudBackupFile) -> Void

    private var cloudStatusHintColor: Color {
        if cloudStatusMessage.contains(String(localized: "失败")) || cloudStatusMessage.contains(String(localized: "未能")) {
            return .appWarning
        }
        return .secondary
    }

    var body: some View {
        Section(String(localized: "iCloud 云备份")) {
            Button(action: onUploadBackup) {
                Label(String(localized: "立即备份到 iCloud"), systemImage: "icloud.and.arrow.up")
            }
            .disabled(isBusy)

            Button(action: onRefreshBackups) {
                Label(String(localized: "刷新云端备份列表"), systemImage: "arrow.clockwise")
            }
            .disabled(isBusy || isRefreshingCloudBackups)

            if isRefreshingCloudBackups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "正在读取 iCloud 备份…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(cloudCellularTrafficHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(String(localized: "业务数据"), isOn: $cloudIncludeBusinessRecords)
            Toggle(String(localized: "项目记录"), isOn: $cloudIncludeProjectRecords)
            Toggle(String(localized: "项目资料与随手记"), isOn: $cloudIncludeProjectFilesAndNotes)
                .disabled(!cloudIncludeProjectRecords)
            Toggle(String(localized: "原文件附件（照片/图纸/文档）"), isOn: $cloudIncludeAttachments)
                .disabled(!cloudIncludeProjectRecords || !cloudIncludeProjectFilesAndNotes)
            Toggle(String(localized: "资料库（材料价/供应商/工艺）"), isOn: $cloudIncludeKnowledgeBase)

            Text(cloudBackupScopeHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker(String(localized: "自动备份"), selection: $cloudAutoIntervalRawValue) {
                ForEach(CloudBackupAutoInterval.allCases, id: \.rawValue) { interval in
                    Text(interval.title).tag(interval.rawValue)
                }
            }

            Picker(String(localized: "云端保留数量"), selection: $cloudBackupRetentionCount) {
                ForEach(CloudBackupRetentionCountOption.allCases) { option in
                    Text(option.title)
                        .tag(option.rawValue)
                }
            }
            .disabled(isBusy)
            Text(String(localized: "超过保留数量后，会自动删除最旧的 iCloud 备份。"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if cloudAutoInterval != .disabled {
                Toggle(String(localized: "仅在 Wi‑Fi 下自动备份"), isOn: $cloudAutoBackupRequiresWiFi)
                    .disabled(isBusy)
                Text(cloudAutoNetworkHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextDate = cloudNextAutoBackupDate {
                    LabeledContent(String(localized: "下次预计"), value: Formatters.dateTime.string(from: nextDate))
                }
            }

            if let lastSuccessDate = cloudLastSuccessDate {
                LabeledContent(String(localized: "最近成功"), value: Formatters.dateTime.string(from: lastSuccessDate))
            }
            if !cloudAutoLastStatus.isEmpty {
                Text(cloudAutoLastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cloudBackups.isEmpty {
                if !isRefreshingCloudBackups {
                    Text(String(localized: "iCloud 中还没有备份。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(cloudBackups.enumerated()), id: \.element.id) { index, file in
                    CloudBackupListRow(file: file, isLatest: index == 0) {
                        onRestoreBackup(file)
                    }
                }
            }

            if !cloudStatusMessage.isEmpty {
                Text(cloudStatusMessage)
                    .font(.caption)
                    .foregroundStyle(cloudStatusHintColor)
            }
        }
    }
}
