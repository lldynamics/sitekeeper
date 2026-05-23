import SwiftUI
import Foundation
import UniformTypeIdentifiers

enum BackupSection: CaseIterable {
    case local
    case cloud
    case overview

    var displayName: String {
        switch self {
        case .local:
            return String(localized: "本地备份与恢复")
        case .cloud:
            return String(localized: "iCloud 同步备份")
        case .overview:
            return String(localized: "备份健康概览")
        }
    }
    var systemImage: String {
        switch self {
        case .local: "externaldrive"
        case .cloud: "icloud"
        case .overview: "info.circle"
        }
    }
}

struct BackupView: View {
    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @AppStorage(UserPreferenceKeys.hasCompletedBackupExportTask) var hasCompletedBackupExportTask = false
    @AppStorage(UserPreferenceKeys.hasSeenBackupGuide) var hasSeenBackupGuide = false
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeBusinessRecords) var cloudIncludeBusinessRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectRecords) var cloudIncludeProjectRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectFilesAndNotes) var cloudIncludeProjectFilesAndNotes = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeKnowledgeBase) var cloudIncludeKnowledgeBase = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeAttachments) var cloudIncludeAttachments = true
    @AppStorage(UserPreferenceKeys.cloudBackupAutoInterval) var cloudAutoIntervalRawValue = CloudBackupAutoInterval.disabled.rawValue
    @AppStorage(UserPreferenceKeys.cloudBackupAutoRequiresWiFi) private var cloudAutoBackupRequiresWiFi = false
    @AppStorage(UserPreferenceKeys.cloudBackupRetentionCount) var cloudBackupRetentionCount = CloudBackupRetentionCountOption.defaultValue
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) var cloudLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupAutoLastStatus) private var cloudAutoLastStatus = ""
    @State var statusMessage = ""
    @State var showExporter = false
    @State var showImporter = false
    @State var exportFileURL: URL?
    @State var exportSummary = ""
    @State var pendingImportPreview: BackupImportPreview?
    @State var pendingImportFileURL: URL?
    @State var showPreview = false
    @State var importMode: ImportMode = .merge
    @State var isOverwriteImportArmed = false
    @State var showUITestOverwriteImportConfirm = false
    @State var didAutoOpenImporter = false
    @State var exportTask: Task<Void, Never>?
    @State var importTask: Task<Void, Never>?
    @State var isExportingArchive = false
    @State var exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: String(localized: "准备导出"))
    @State var isImportingBackup = false
    @State var importProgress = BackupImportProgress(completedBytes: 0, totalBytes: 1, currentItem: String(localized: "准备导入"))
    @State var importProgressTitle = String(localized: "正在读取备份")
    @State var lastExportSucceeded = false
    @State var lastImportSucceeded = false
    @State var estimateState = BackupEstimateState()
    @State var cloudState = BackupCloudState()
    @State var selectedBackupSection: BackupSection = .local
    let autoOpenImporter: Bool
    let showsNavigationTitle: Bool
    let bottomContentInset: CGFloat
    let onAutoOpenImporterConsumed: (() -> Void)?
    private let cloudBackupScopeHint = String(localized: "可按业务模块选择备份范围。关闭“原文件附件”可显著减小体积。")
    private let cloudCellularTrafficHint = String(localized: "提示：在蜂窝网络下手动或自动备份 iCloud 会消耗移动数据流量，建议大包资料优先在 Wi‑Fi 下操作。")

    init(
        autoOpenImporter: Bool = false,
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        onAutoOpenImporterConsumed: (() -> Void)? = nil
    ) {
        self.autoOpenImporter = autoOpenImporter
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.onAutoOpenImporterConsumed = onAutoOpenImporterConsumed
    }

    var backupEstimateSignature: Int {
        var hasher = Hasher()
        hasher.combine(store.materialItems.count)
        hasher.combine(store.quoteItems.count)
        hasher.combine(store.laborRecords.count)
        hasher.combine(store.projects.count)
        hasher.combine(store.dailyLogs.count)
        hasher.combine(store.historyRecords.count)
        hasher.combine(store.progressTasks.count)
        hasher.combine(store.siteTodos.count)
        hasher.combine(store.projectDrawings.count)
        hasher.combine(store.projectContacts.count)
        hasher.combine(store.projectFinancialRecords.count)
        hasher.combine(store.projectDocuments.count)
        hasher.combine(store.quickNotes.count)
        hasher.combine(store.projectWarehouseMovements.count)
        hasher.combine(store.templates.count)
        hasher.combine(store.materialPriceEntries.count)
        hasher.combine(store.supplierProfiles.count)
        hasher.combine(store.constructionMethods.count)
        hasher.combine(store.favoriteMaterialKeys.count)
        hasher.combine(store.recentMaterialKeys.count)

        let dailyLogPhotoCount = store.dailyLogs.reduce(0) { result, log in
            result + log.allPhotoFileNames.count
        }
        let todoPhotoCount = store.siteTodos.reduce(0) { result, todo in
            result
                + (todo.rectificationBeforePhotoFileName?.isEmpty == false ? 1 : 0)
                + (todo.rectificationAfterPhotoFileName?.isEmpty == false ? 1 : 0)
        }
        let quickNoteAttachmentCount = store.quickNotes.reduce(0) { result, note in
            result + note.attachments.count
        }
        let constructionAttachmentCount = store.constructionMethods.reduce(0) { result, method in
            result + method.attachments.count + method.tutorialAttachments.count
        }

        hasher.combine(dailyLogPhotoCount)
        hasher.combine(todoPhotoCount)
        hasher.combine(quickNoteAttachmentCount)
        hasher.combine(constructionAttachmentCount)
        return hasher.finalize()
    }

    var shouldShowFirstBackupGuide: Bool {
        !hasCompletedBackupExportTask && !hasSeenBackupGuide && !lastImportSucceeded
    }

    var shouldShowMicroGuides: Bool {
        !isExportingArchive
            && !isImportingBackup
            && (estimateState.backupEstimate.missingFiles.count > 0 || lastExportSucceeded || lastImportSucceeded)
    }

    var showsUITestPreviewShortcut: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
    }

    var runtimeState: BackupRuntimeState {
        BackupRuntimeState(
            isExportingArchive: isExportingArchive,
            isImportingBackup: isImportingBackup,
            isUploadingCloudBackup: cloudState.isUploadingCloudBackup,
            isRefreshingCloudBackups: cloudState.isRefreshingCloudBackups
        )
    }

    var isBusy: Bool {
        runtimeState.isBusy
    }

    var cloudBackupOptions: CloudBackupContentOptions {
        CloudBackupContentOptions(
            includeBusinessRecords: cloudIncludeBusinessRecords,
            includeProjectRecords: cloudIncludeProjectRecords,
            includeProjectFilesAndNotes: cloudIncludeProjectFilesAndNotes,
            includeKnowledgeBase: cloudIncludeKnowledgeBase,
            includeAttachments: cloudIncludeAttachments
        ).normalized()
    }

    var cloudAutoInterval: CloudBackupAutoInterval {
        StringEnumFallback.value(cloudAutoIntervalRawValue, default: CloudBackupAutoInterval.disabled)
    }

    var cloudLastSuccessDate: Date? {
        guard cloudLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: cloudLastSuccessAt)
    }

    var cloudNextAutoBackupDate: Date? {
        guard let interval = cloudAutoInterval.minimumInterval else { return nil }
        let base = cloudLastSuccessDate ?? Date()
        return base.addingTimeInterval(interval)
    }

    var cloudAutoNetworkHint: String {
        cloudAutoBackupRequiresWiFi
            ? String(localized: "已限制为仅 Wi‑Fi 自动备份。")
            : String(localized: "当前允许在蜂窝网络下自动备份，可能消耗移动数据流量。")
    }

    var localBackupDate: Date? {
        guard localBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: localBackupLastSuccessAt)
    }

    var backupStatusItems: [DataSafetyStatusItem] {
        var items: [DataSafetyStatusItem] = [
            DataSafetyStatusItem(
                title: String(localized: "上次备份"),
                value: localBackupDate.map(formatDataSafetyDate) ?? String(localized: "尚未完成"),
                tone: localBackupDate == nil ? .warning : .success
            ),
            DataSafetyStatusItem(
                title: String(localized: "缺失文件"),
                value: estimateState.backupEstimate.missingFiles.isEmpty
                    ? String(localized: "0 个")
                    : String(format: String(localized: "%lld 个"), Int64(estimateState.backupEstimate.missingFiles.count)),
                tone: estimateState.backupEstimate.missingFiles.isEmpty ? .success : .warning
            ),
        ]

        if selectedBackupSection == .cloud {
            items.append(
                DataSafetyStatusItem(
                    title: String(localized: "云端最近成功"),
                    value: cloudLastSuccessDate.map(formatDataSafetyDate) ?? String(localized: "尚未完成"),
                    tone: cloudLastSuccessDate == nil ? .warning : .success
                )
            )
            items.append(
                DataSafetyStatusItem(
                    title: String(localized: "下次自动备份"),
                    value: cloudAutoInterval == .disabled
                        ? String(localized: "已关闭")
                        : cloudNextAutoBackupDate.map(formatDataSafetyDate) ?? String(localized: "等待首次成功"),
                    tone: cloudAutoInterval == .disabled ? .neutral : .doc
                )
            )
            items.append(
                DataSafetyStatusItem(
                    title: String(localized: "自动备份状态"),
                    value: normalizedCloudAutoStatus,
                    tone: cloudAutoStatusTone
                )
            )
        } else {
            items.append(
                DataSafetyStatusItem(
                    title: String(localized: "当前环节"),
                    value: selectedBackupSection.displayName,
                    tone: .primary
                )
            )
        }

        return items
    }

    var normalizedCloudAutoStatus: String {
        let trimmed = cloudAutoLastStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "未记录") : trimmed
    }

    var cloudAutoStatusTone: StatusChipTone {
        let trimmed = cloudAutoLastStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .neutral }
        if trimmed.contains(String(localized: "失败")) || trimmed.contains(String(localized: "未能")) {
            return .warning
        }
        if trimmed.contains(String(localized: "成功")) || trimmed.contains(String(localized: "完成")) {
            return .success
        }
        return .doc
    }

    var cloudBackupSection: some View {
        BackupCloudSectionView(
            cloudIncludeBusinessRecords: $cloudIncludeBusinessRecords,
            cloudIncludeProjectRecords: $cloudIncludeProjectRecords,
            cloudIncludeProjectFilesAndNotes: $cloudIncludeProjectFilesAndNotes,
            cloudIncludeKnowledgeBase: $cloudIncludeKnowledgeBase,
            cloudIncludeAttachments: $cloudIncludeAttachments,
            cloudAutoIntervalRawValue: $cloudAutoIntervalRawValue,
            cloudAutoBackupRequiresWiFi: $cloudAutoBackupRequiresWiFi,
            cloudBackupRetentionCount: $cloudBackupRetentionCount,
            isBusy: isBusy,
            isRefreshingCloudBackups: cloudState.isRefreshingCloudBackups,
            cloudBackups: cloudState.cloudBackups,
            cloudStatusMessage: cloudState.cloudStatusMessage,
            cloudBackupScopeHint: cloudBackupScopeHint,
            cloudCellularTrafficHint: cloudCellularTrafficHint,
            cloudAutoNetworkHint: cloudAutoNetworkHint,
            cloudAutoInterval: cloudAutoInterval,
            onUploadBackup: uploadBackupToICloud,
            onRefreshBackups: { refreshCloudBackups(force: true) },
            onRestoreBackup: { file in
                cloudState.pendingCloudRestore = file
                cloudState.showCloudRestoreConfirm = true
            }
        )
        .onChange(of: cloudIncludeProjectRecords) { _, isEnabled in
            if !isEnabled {
                cloudIncludeProjectFilesAndNotes = false
                cloudIncludeAttachments = false
            }
        }
        .onChange(of: cloudIncludeProjectFilesAndNotes) { _, isEnabled in
            if !isEnabled {
                cloudIncludeAttachments = false
            }
        }
    }
}
