import SwiftUI

struct StorageCleanupTrashPolicySection: View {
    @Binding var cleanupTrashRetentionDays: Int
    let cleanupTrashRecoveryDeadlineText: String

    var body: some View {
        Section {
            Picker(selection: $cleanupTrashRetentionDays) {
                ForEach(StorageCleanupTrashRetentionOption.allCases) { option in
                    Text(option.displayName)
                        .tag(option.days)
                }
            } label: {
                Label(String(localized: "回收站保留时间"), systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }

            Text(
                String(
                    format: String(localized: "之后新清理的文件可恢复至 %@。"),
                    cleanupTrashRecoveryDeadlineText
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        } header: {
            Text(String(localized: "回收站策略"))
        } footer: {
            Text(String(localized: "只影响之后新清理的批次；已有回收站批次仍按原到期时间处理。"))
        }
    }
}

struct StorageCleanupTrashSection: View {
    let cleanupTrashBatches: [StorageCleanupTrashBatch]
    let quarantinedFiles: [FileQuarantineEntry]
    let normalizedCleanupTrashRetentionDays: Int
    let onRestoreCleanupTrash: (StorageCleanupTrashBatch) -> Void
    let onPermanentlyDeleteCleanupTrash: (StorageCleanupTrashBatch) -> Void
    let onRestoreQuarantinedFile: (FileQuarantineEntry) -> Void
    let onPermanentlyDeleteQuarantinedFile: (FileQuarantineEntry) -> Void

    var body: some View {
        Section {
            if cleanupTrashBatches.isEmpty && quarantinedFiles.isEmpty {
                Text(String(localized: "暂无可恢复的回收站项目。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cleanupTrashBatches) { batch in
                    cleanupTrashBatchRow(batch)
                }

                ForEach(quarantinedFiles) { entry in
                    quarantinedFileRow(entry)
                }
            }
        } header: {
            Text(String(localized: "全局回收站"))
        } footer: {
            Text(
                String(
                    format: String(localized: "照片、图纸、票据、附件删除和项目文件清理都会先进入回收站，当前保留 %lld 天。过期项目会在进入本页时自动永久删除。"),
                    Int64(normalizedCleanupTrashRetentionDays)
                )
            )
        }
    }

    private func cleanupTrashBatchRow(_ batch: StorageCleanupTrashBatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(batch.summary)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(format: String(localized: "%lld 个文件"), Int64(batch.fileCount)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appWarning)
            }
            Text(String(localized: "清理批次"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(
                String(
                    format: String(localized: "可恢复至 %@"),
                    Formatters.date.string(from: batch.expiresAt)
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    onRestoreCleanupTrash(batch)
                } label: {
                    Label(String(localized: "恢复"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onPermanentlyDeleteCleanupTrash(batch)
                } label: {
                    Label(String(localized: "永久删除"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private func quarantinedFileRow(_ entry: FileQuarantineEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.originalFileName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(localized: "隔离文件"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appWarning)
            }
            Text(fileQuarantineCategoryTitle(entry.category))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(
                String(
                    format: String(localized: "可恢复至 %@"),
                    Formatters.date.string(from: entry.expiresAt)
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    onRestoreQuarantinedFile(entry)
                } label: {
                    Label(String(localized: "恢复"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onPermanentlyDeleteQuarantinedFile(entry)
                } label: {
                    Label(String(localized: "永久删除"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private func fileQuarantineCategoryTitle(_ category: FileQuarantineCategory) -> String {
        switch category {
        case .photoOriginal:
            return String(localized: "照片原文件")
        case .photoThumbnail:
            return String(localized: "照片缩略图")
        case .drawing:
            return String(localized: "图纸原件文件")
        case .drawingSidecar:
            return String(localized: "图纸附属文件")
        case .projectDocument:
            return String(localized: "项目资料文件")
        case .quickNoteAttachment:
            return String(localized: "随手记附件")
        }
    }
}

struct StorageCleanupSummarySection: View {
    let categorySummaries: [StorageCategorySummary]

    var body: some View {
        Section(String(localized: "空间汇总")) {
            ForEach(categorySummaries) { summary in
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: summary.icon)
                        .foregroundStyle(summary.tint)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                        Text(String(format: String(localized: "%lld 项"), Int64(summary.count)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(summary.formattedBytes)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

struct StorageCleanupLargeFileSections: View {
    @Binding var largeFileThresholdMB: Int
    let largeFileRuleSuggestionText: String
    let largeFileItems: [StorageLargeFileItem]

    var body: some View {
        Section {
            Picker(selection: $largeFileThresholdMB) {
                ForEach(StorageCleanupLargeFileThresholdOption.allCases) { option in
                    Text(option.displayName)
                        .tag(option.megabytes)
                }
            } label: {
                Label(String(localized: "大文件阈值"), systemImage: "externaldrive.fill.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            Text(largeFileRuleSuggestionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            Text(String(format: String(localized: "大文件列表（%lld）"), Int64(largeFileItems.count)))
        } footer: {
            Text(String(localized: "展示照片、视频、图纸原件、备份和历史计算中的高占用项。"))
        }

        if largeFileItems.isEmpty {
            Section {
                ContentUnavailableView(
                    String(localized: "暂无大文件"),
                    systemImage: "checkmark.seal",
                    description: Text(String(localized: "当前各类文件都低于阈值。"))
                )
            }
        } else {
            Section {
                ForEach(largeFileItems.prefix(80)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: AppSpacing.tight) {
                            Image(systemName: item.category.icon)
                                .foregroundStyle(item.category.tint)
                            Text(item.title)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(item.formattedBytes)
                                .font(.caption.weight(.semibold))
                        }
                        HStack(spacing: AppSpacing.tight) {
                            Text(item.category.displayName)
                            if let projectName = item.projectName {
                                Text(projectName)
                            }
                            if !item.detail.isEmpty {
                                Text(item.detail)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct StorageCleanupProjectSection: View {
    let projectUsages: [ProjectStorageUsage]
    let onRequestCleanup: (ProjectStorageUsage, ProjectStorageCleanupCategory) -> Void

    var body: some View {
        Section(String(localized: "按项目清理")) {
            if projectUsages.isEmpty {
                Text(String(localized: "暂无可清理项目文件。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projectUsages) { usage in
                    NavigationLink {
                        ProjectStorageCleanupDetailView(usage: usage) { category in
                            onRequestCleanup(usage, category)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(usage.projectName)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(usage.formattedTotalBytes)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.appWarning)
                            }
                            HStack(spacing: AppSpacing.tight) {
                                Text(String(format: String(localized: "照片 %@"), QuickNoteAttachmentStorage.formattedFileSize(usage.photoBytes)))
                                Text(String(format: String(localized: "视频 %@"), QuickNoteAttachmentStorage.formattedFileSize(usage.videoBytes)))
                                Text(String(format: String(localized: "图纸 %@"), QuickNoteAttachmentStorage.formattedFileSize(usage.drawingBytes)))
                                Text(String(format: String(localized: "票据 %@"), QuickNoteAttachmentStorage.formattedFileSize(usage.ticketBytes)))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            Text(String(format: String(localized: "备份估算 %@"), usage.formattedBackupEstimatedBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}
