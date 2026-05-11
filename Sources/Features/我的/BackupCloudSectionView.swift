import SwiftUI

struct BackupCloudSectionView: View {
    @Binding var cloudIncludeBusinessRecords: Bool
    @Binding var cloudIncludeProjectRecords: Bool
    @Binding var cloudIncludeProjectFilesAndNotes: Bool
    @Binding var cloudIncludeKnowledgeBase: Bool
    @Binding var cloudIncludeAttachments: Bool
    @Binding var cloudAutoIntervalRawValue: String
    @Binding var cloudAutoBackupRequiresWiFi: Bool

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
        if cloudStatusMessage.contains("失败") || cloudStatusMessage.contains("未能") {
            return .orange
        }
        return .secondary
    }

    var body: some View {
        Section("iCloud 云备份") {
            Button(action: onUploadBackup) {
                Label("立即备份到 iCloud", systemImage: "icloud.and.arrow.up")
            }
            .disabled(isBusy)

            Button(action: onRefreshBackups) {
                Label("刷新云端备份列表", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy || isRefreshingCloudBackups)

            if isRefreshingCloudBackups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取 iCloud 备份…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(cloudCellularTrafficHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("业务数据", isOn: $cloudIncludeBusinessRecords)
            Toggle("项目记录", isOn: $cloudIncludeProjectRecords)
            Toggle("项目资料与随手记", isOn: $cloudIncludeProjectFilesAndNotes)
                .disabled(!cloudIncludeProjectRecords)
            Toggle("原文件附件（照片/图纸/文档）", isOn: $cloudIncludeAttachments)
                .disabled(!cloudIncludeProjectRecords || !cloudIncludeProjectFilesAndNotes)
            Toggle("资料库（材料价/供应商/工艺）", isOn: $cloudIncludeKnowledgeBase)

            Text(cloudBackupScopeHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("自动备份", selection: $cloudAutoIntervalRawValue) {
                ForEach(CloudBackupAutoInterval.allCases, id: \.rawValue) { interval in
                    Text(interval.title).tag(interval.rawValue)
                }
            }

            if cloudAutoInterval != .disabled {
                Toggle("仅在 Wi‑Fi 下自动备份", isOn: $cloudAutoBackupRequiresWiFi)
                    .disabled(isBusy)
                Text(cloudAutoNetworkHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextDate = cloudNextAutoBackupDate {
                    LabeledContent("下次预计", value: Formatters.dateTime.string(from: nextDate))
                }
            }

            if let lastSuccessDate = cloudLastSuccessDate {
                LabeledContent("最近成功", value: Formatters.dateTime.string(from: lastSuccessDate))
            }
            if !cloudAutoLastStatus.isEmpty {
                Text(cloudAutoLastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if cloudBackups.isEmpty {
                if !isRefreshingCloudBackups {
                    Text("iCloud 中还没有备份。")
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
