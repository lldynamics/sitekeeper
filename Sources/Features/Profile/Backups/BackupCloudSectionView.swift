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
    let onUploadBackup: () -> Void
    let onRefreshBackups: () -> Void
    let onRestoreBackup: (CloudBackupFile) -> Void

    private var cloudStatusHintColor: Color {
        if cloudStatusMessage.contains(AppLocalization.string("失败")) || cloudStatusMessage.contains(AppLocalization.string("未能")) {
            return .appWarning
        }
        return .secondary
    }

    var body: some View {
        Section(AppLocalization.string("iCloud 云备份")) {
            Button(action: onUploadBackup) {
                Label(AppLocalization.string("立即备份到 iCloud"), systemImage: "icloud.and.arrow.up")
            }
            .disabled(isBusy)

            Button(action: onRefreshBackups) {
                Label(AppLocalization.string("刷新云端备份列表"), systemImage: "arrow.clockwise")
            }
            .disabled(isBusy || isRefreshingCloudBackups)

            if isRefreshingCloudBackups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(AppLocalization.string("正在读取 iCloud 备份…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(cloudCellularTrafficHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(AppLocalization.string("业务数据"), isOn: $cloudIncludeBusinessRecords)
            Toggle(AppLocalization.string("项目记录"), isOn: $cloudIncludeProjectRecords)
            Toggle(AppLocalization.string("项目资料与随手记"), isOn: $cloudIncludeProjectFilesAndNotes)
                .disabled(!cloudIncludeProjectRecords)
            Toggle(AppLocalization.string("原文件附件（照片/图纸/文档）"), isOn: $cloudIncludeAttachments)
                .disabled(!cloudIncludeProjectRecords || !cloudIncludeProjectFilesAndNotes)
            Toggle(AppLocalization.string("资料库（材料价/供应商/工艺）"), isOn: $cloudIncludeKnowledgeBase)

            Text(cloudBackupScopeHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker(AppLocalization.string("自动备份"), selection: $cloudAutoIntervalRawValue) {
                ForEach(CloudBackupAutoInterval.allCases, id: \.rawValue) { interval in
                    Text(interval.title).tag(interval.rawValue)
                }
            }

            Picker(AppLocalization.string("云端保留数量"), selection: $cloudBackupRetentionCount) {
                ForEach(CloudBackupRetentionCountOption.allCases) { option in
                    Text(option.title)
                        .tag(option.rawValue)
                }
            }
            .disabled(isBusy)
            Text(AppLocalization.string("仅在新备份及校验文件确认上传后，才清理超出保留数量的旧备份；等待同步或上传失败的文件会保留。"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if cloudAutoInterval != .disabled {
                Toggle(AppLocalization.string("仅在 Wi‑Fi 下自动备份"), isOn: $cloudAutoBackupRequiresWiFi)
                    .disabled(isBusy)
                Text(cloudAutoNetworkHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cloudBackups.isEmpty {
                if !isRefreshingCloudBackups {
                    Text(AppLocalization.string("iCloud 中还没有备份。"))
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
