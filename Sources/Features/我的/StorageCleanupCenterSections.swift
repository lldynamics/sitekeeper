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
                Label(StorageCleanupSectionCopy.trashRetentionLabel, systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }

            Text(
                StorageCleanupSectionCopy.trashPolicyRecoveryHint(
                    deadlineText: cleanupTrashRecoveryDeadlineText
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        } header: {
            Text(StorageCleanupSectionCopy.trashPolicyHeader)
        } footer: {
            Text(StorageCleanupSectionCopy.trashPolicyFooter)
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
                Text(StorageCleanupSectionCopy.emptyTrashMessage)
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
            Text(StorageCleanupSectionCopy.globalTrashHeader)
        } footer: {
            Text(StorageCleanupSectionCopy.globalTrashFooter(retentionDays: normalizedCleanupTrashRetentionDays))
        }
    }

    private func cleanupTrashBatchRow(_ batch: StorageCleanupTrashBatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(batch.summary)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(StorageCleanupSectionCopy.cleanupBatchFileCount(batch.fileCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appWarning)
            }
            Text(StorageCleanupSectionCopy.cleanupBatchLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(StorageCleanupSectionCopy.recoverableUntil(Formatters.date.string(from: batch.expiresAt)))
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    onRestoreCleanupTrash(batch)
                } label: {
                    Label(StorageCleanupSectionCopy.restoreActionTitle, systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onPermanentlyDeleteCleanupTrash(batch)
                } label: {
                    Label(StorageCleanupSectionCopy.permanentDeleteActionTitle, systemImage: "trash")
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
                Text(StorageCleanupSectionCopy.quarantinedFileLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appWarning)
            }
            Text(fileQuarantineCategoryTitle(entry.category))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(StorageCleanupSectionCopy.recoverableUntil(Formatters.date.string(from: entry.expiresAt)))
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    onRestoreQuarantinedFile(entry)
                } label: {
                    Label(StorageCleanupSectionCopy.restoreActionTitle, systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onPermanentlyDeleteQuarantinedFile(entry)
                } label: {
                    Label(StorageCleanupSectionCopy.permanentDeleteActionTitle, systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private func fileQuarantineCategoryTitle(_ category: FileQuarantineCategory) -> String {
        StorageCleanupSectionCopy.quarantineCategoryTitle(category)
    }
}

struct StorageCleanupSummarySection: View {
    let categorySummaries: [StorageCategorySummary]

    var body: some View {
        Section(StorageCleanupSectionCopy.storageSummaryHeader) {
            ForEach(categorySummaries) { summary in
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: summary.icon)
                        .foregroundStyle(summary.tint)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.title)
                        Text(StorageCleanupSectionCopy.summaryItemCount(summary.count))
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
                Label(StorageCleanupSectionCopy.largeFileThresholdLabel, systemImage: "externaldrive.fill.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            Text(largeFileRuleSuggestionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } header: {
            Text(StorageCleanupSectionCopy.largeFileHeader(largeFileItems.count))
        } footer: {
            Text(StorageCleanupSectionCopy.largeFileFooter)
        }

        if largeFileItems.isEmpty {
            Section {
                ContentUnavailableView(
                    StorageCleanupSectionCopy.noLargeFilesTitle,
                    systemImage: "checkmark.seal",
                    description: Text(StorageCleanupSectionCopy.noLargeFilesDescription)
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
        Section(StorageCleanupSectionCopy.projectCleanupHeader) {
            if projectUsages.isEmpty {
                Text(StorageCleanupSectionCopy.noProjectCleanupMessage)
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
                                Text(StorageCleanupSectionCopy.projectUsage(StorageCleanupSectionCopy.usagePhotoTitle, sizeText: QuickNoteAttachmentStorage.formattedFileSize(usage.photoBytes)))
                                Text(StorageCleanupSectionCopy.projectUsage(StorageCleanupSectionCopy.usageVideoTitle, sizeText: QuickNoteAttachmentStorage.formattedFileSize(usage.videoBytes)))
                                Text(StorageCleanupSectionCopy.projectUsage(StorageCleanupSectionCopy.usageDrawingTitle, sizeText: QuickNoteAttachmentStorage.formattedFileSize(usage.drawingBytes)))
                                Text(StorageCleanupSectionCopy.projectUsage(StorageCleanupSectionCopy.usageTicketTitle, sizeText: QuickNoteAttachmentStorage.formattedFileSize(usage.ticketBytes)))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            Text(StorageCleanupSectionCopy.projectBackupEstimate(usage.formattedBackupEstimatedBytes))
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

struct ProjectStorageCleanupDetailView: View {
    let usage: ProjectStorageUsage
    let onCleanup: (ProjectStorageCleanupCategory) -> Void

    var body: some View {
        List {
            Section(StorageCleanupSectionCopy.usageSummaryHeader) {
                usageRow(title: StorageCleanupSectionCopy.usagePhotoTitle, icon: "photo.fill", tint: .appWarning, bytes: usage.photoBytes)
                usageRow(title: StorageCleanupSectionCopy.usageVideoTitle, icon: "video.fill", tint: .appPhoto, bytes: usage.videoBytes)
                usageRow(title: StorageCleanupSectionCopy.usageDrawingOriginalTitle, icon: "doc.viewfinder", tint: .appDoc, bytes: usage.drawingBytes)
                usageRow(title: StorageCleanupSectionCopy.usageTicketDocumentTitle, icon: "doc.text.fill", tint: .appRisk, bytes: usage.ticketBytes)
                usageRow(title: StorageCleanupSectionCopy.usageBackupEstimateTitle, icon: "externaldrive.fill", tint: .appPrimaryAction, bytesText: usage.formattedBackupEstimatedBytes)
            }

            Section {
                HStack {
                    Text(StorageCleanupSectionCopy.projectTotalUsageTitle)
                    Spacer()
                    Text(usage.formattedTotalBytes)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section {
                cleanupButton(.photos, bytes: usage.photoBytes)
                cleanupButton(.videos, bytes: usage.videoBytes)
                cleanupButton(.drawings, bytes: usage.drawingBytes)
                cleanupButton(.tickets, bytes: usage.ticketBytes)
            } header: {
                Text(StorageCleanupSectionCopy.cleanupByTypeHeader)
            } footer: {
                Text(StorageCleanupSectionCopy.cleanupByTypeFooter)
            }

            Section {
                Button(role: .destructive) {
                    onCleanup(.all)
                } label: {
                    Label(StorageCleanupSectionCopy.cleanupAllProjectFilesTitle, systemImage: "trash")
                }
                .disabled(usage.totalBytes == 0)
            } footer: {
                Text(StorageCleanupSectionCopy.backupSpaceNote)
            }
        }
        .navigationTitle(usage.projectName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func cleanupButton(_ category: ProjectStorageCleanupCategory, bytes: Int) -> some View {
        Button(role: .destructive) {
            onCleanup(category)
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.tint)
                    .frame(width: 18, height: 18)
                Text(StorageCleanupSectionCopy.cleanupCategoryTitle(category.displayName))
                Spacer()
                Text(QuickNoteAttachmentStorage.formattedFileSize(bytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(bytes == 0)
    }

    @ViewBuilder
    private func usageRow(title: String, icon: String, tint: Color, bytes: Int) -> some View {
        usageRow(title: title, icon: icon, tint: tint, bytesText: QuickNoteAttachmentStorage.formattedFileSize(bytes))
    }

    @ViewBuilder
    private func usageRow(title: String, icon: String, tint: Color, bytesText: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(title)
            Spacer()
            Text(bytesText)
                .font(.caption.weight(.semibold))
        }
    }
}

struct StorageOptionalInlineTitleModifier: ViewModifier {
    let isEnabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
