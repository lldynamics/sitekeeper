import SwiftUI
import Foundation

extension BackupView {
    @ViewBuilder
    var backupQuickStartSection: some View {
        BackupLocalSectionsView(
            shouldShowFirstBackupGuide: shouldShowFirstBackupGuide,
            includeLocalSection: false,
            showsUITestPreviewShortcut: false,
            showsUITestRoundTrip: false,
            isUITestRoundTripReady: false,
            isBusy: isBusy,
            onExport: exportBackupZIP,
            onDismissGuide: { hasSeenBackupGuide = true },
            onShowImporter: { showImporter = true },
            onInjectUITestPreview: injectUITestPreview,
            onTriggerOverwriteConfirm: { showUITestOverwriteImportConfirm = true },
            onRestoreUITestRoundTrip: {}
        )
    }

    var backupLocalSection: some View {
        BackupLocalSectionsView(
            shouldShowFirstBackupGuide: false,
            includeLocalSection: true,
            showsUITestPreviewShortcut: showsUITestPreviewShortcut,
            showsUITestRoundTrip: isUITestRoundTripEnabled,
            isUITestRoundTripReady: isUITestRoundTripBackupReady,
            isBusy: isBusy,
            onExport: exportBackupZIP,
            onDismissGuide: { hasSeenBackupGuide = true },
            onShowImporter: { showImporter = true },
            onInjectUITestPreview: injectUITestPreview,
            onTriggerOverwriteConfirm: { showUITestOverwriteImportConfirm = true },
            onRestoreUITestRoundTrip: startUITestRoundTripImport
        )
    }

    @ViewBuilder
    var backupMicroGuideSection: some View {
        if shouldShowMicroGuides {
            Section(String(localized: "建议下一步")) {
                if estimateState.backupEstimate.missingFiles.count > 0 {
                    BackupMicroGuideRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .appWarning,
                        title: String(format: String(localized: "检测到 %d 个原文件缺失"), estimateState.backupEstimate.missingFiles.count),
                        detail: String(localized: "建议先到项目文件页抽查缺件，再导出正式备份。")
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label(String(localized: "去项目文件排查"), systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if lastExportSucceeded {
                    BackupMicroGuideRow(
                        icon: "checkmark.seal.fill",
                        color: .appSuccess,
                        title: String(localized: "备份已导出，建议立即做一次导入预览"),
                        detail: String(localized: "提前验证恢复链路，换机或误删时更稳。")
                    )
                    Button {
                        showImporter = true
                    } label: {
                        Label(String(localized: "马上验证导入"), systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.appProminent(tint: .appWarning))
                }

                if lastImportSucceeded {
                    BackupMicroGuideRow(
                        icon: "doc.text.magnifyingglass",
                        color: .appPrimaryAction,
                        title: String(localized: "导入完成，建议抽查关键资料"),
                        detail: String(localized: "优先核对最近图纸、票据和随手记附件是否完整。")
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label(String(localized: "去抽查文件"), systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    var backupEstimateSection: some View {
        BackupOverviewSectionsView(
            isEstimatingBackup: estimateState.isEstimatingBackup,
            backupEstimate: estimateState.backupEstimate
        )
    }

    @ViewBuilder
    var backupStatusSection: some View {
        if store.loadState == .failed {
            Section(String(localized: "本地数据读取失败")) {
                Text(store.persistenceErrorMessage ?? "")
                    .font(.caption)
                Button(String(localized: "重试读取本地数据")) { store.loadAsync() }
                    .disabled(isBusy)
            }
        }
        if !statusMessage.isEmpty {
            Section {
                Text(statusMessage)
                    .font(.caption)
                    .accessibilityIdentifier("backup-status-message")
            }
        }
    }

    var exportProgressCard: some View {
        BackupTaskProgressCard(
            title: cloudState.isUploadingCloudBackup ? String(localized: "正在生成 iCloud 备份") : String(localized: "正在生成备份 ZIP"),
            subtitle: exportProgress.currentItem,
            progressValue: exportProgress.fractionCompleted,
            detail: "\(exportProgress.completedSteps)/\(max(exportProgress.totalSteps, 1))",
            cancelTitle: cloudState.isUploadingCloudBackup ? String(localized: "取消云备份") : String(localized: "取消导出"),
            onCancel: {
                AppHaptics.warning()
                exportProgress = BackupArchiveProgress(
                    completedSteps: exportProgress.completedSteps,
                    totalSteps: max(exportProgress.totalSteps, 1),
                    currentItem: String(localized: "正在取消...")
                )
                if cloudState.isUploadingCloudBackup {
                    cloudState.cloudBackupTask?.cancel()
                } else {
                    exportTask?.cancel()
                }
            }
        )
    }

    var importProgressCard: some View {
        BackupTaskProgressCard(
            title: importProgressTitle,
            subtitle: importProgress.currentItem,
            progressValue: importProgress.fractionCompleted,
            detail: "\(formattedFileSize(Int(importProgress.completedBytes)))/\(formattedFileSize(Int(importProgress.totalBytes)))",
            cancelTitle: String(localized: "取消导入"),
            onCancel: {
                AppHaptics.warning()
                importProgress = BackupImportProgress(
                    completedBytes: importProgress.completedBytes,
                    totalBytes: max(importProgress.totalBytes, 1),
                    currentItem: String(localized: "正在取消...")
                )
                importTask?.cancel()
            }
        )
    }

    func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    func formatDataSafetyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
