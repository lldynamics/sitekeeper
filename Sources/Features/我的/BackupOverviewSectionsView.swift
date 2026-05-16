import SwiftUI

struct BackupOverviewSectionsView: View {
    let isEstimatingBackup: Bool
    let backupEstimate: BackupArchiveEstimate

    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var body: some View {
        Group {
            Section(String(localized: "预计体积")) {
                if isEstimatingBackup {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "正在后台估算备份体积…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(String(localized: "数据索引"), value: formattedFileSize(backupEstimate.metadataBytes))
                LabeledContent(String(localized: "原文件"), value: formattedFileSize(backupEstimate.rawFilesBytes))
                LabeledContent(String(localized: "预计合计"), value: formattedFileSize(backupEstimate.estimatedBytes))
                Text(String(localized: "备份导出不设体积上限，会按 ZIP64 流式打包；大文件导出前请确认设备剩余空间充足。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !backupEstimate.missingFiles.isEmpty {
                    Text(String(format: String(localized: "发现 %d 个原文件缺失，备份包会记录缺失清单。"), backupEstimate.missingFiles.count))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
                if backupEstimate.estimatedBytes >= BackupArchiveService.largeArchiveWarningBytes {
                    Text(String(localized: "预计体积较大，导出可能持续较久；请保持 App 在前台、电量充足，并预留导出包体积以上的可用空间。"))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
            }

            Section(String(localized: "版本")) {
                HStack {
                    Text(String(localized: "备份格式版本"))
                    Spacer()
                    Text("2 · ZIP").foregroundStyle(.secondary)
                }
            }
        }
    }
}
