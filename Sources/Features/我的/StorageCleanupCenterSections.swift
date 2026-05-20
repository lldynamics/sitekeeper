import SwiftUI

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
            Text(String(localized: "展示照片、视频、CAD、备份和历史计算中的高占用项。"))
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
                                Text(String(format: String(localized: "CAD %@"), QuickNoteAttachmentStorage.formattedFileSize(usage.cadBytes)))
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
