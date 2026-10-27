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
            return AppLocalization.string("本地备份与恢复")
        case .cloud:
            return AppLocalization.string("iCloud 同步备份")
        case .overview:
            return AppLocalization.string("备份健康概览")
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
    @AppStorage(UserPreferenceKeys.cloudBackupAutoLastStatus) var cloudAutoLastStatus = ""
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
    @State var exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: AppLocalization.string("准备导出"))
    @State var isImportingBackup = false
    @State var importProgress = BackupImportProgress(completedBytes: 0, totalBytes: 1, currentItem: AppLocalization.string("准备导入"))
    @State var importProgressTitle = AppLocalization.string("正在读取备份")
    @State var lastExportSucceeded = false
    @State var lastImportSucceeded = false
    @State var estimateState = BackupEstimateState()
    @State var cloudState = BackupCloudState()
    @State var selectedBackupSection: BackupSection = .local
    let autoOpenImporter: Bool
    let showsNavigationTitle: Bool
    let bottomContentInset: CGFloat
    let onMobileScrollOffsetChange: ((CGFloat) -> Void)?
    let onAutoOpenImporterConsumed: (() -> Void)?
    private let cloudBackupScopeHint = AppLocalization.string("可按业务模块选择备份范围。关闭“原文件附件”可显著减小体积。")
    private let cloudCellularTrafficHint = AppLocalization.string("提示：在蜂窝网络下手动或自动备份 iCloud 会消耗移动数据流量，建议大包资料优先在 Wi‑Fi 下操作。")

    init(
        autoOpenImporter: Bool = false,
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        onMobileScrollOffsetChange: ((CGFloat) -> Void)? = nil,
        onAutoOpenImporterConsumed: (() -> Void)? = nil
    ) {
        self.autoOpenImporter = autoOpenImporter
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.onMobileScrollOffsetChange = onMobileScrollOffsetChange
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
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
#else
        false
#endif
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
            ? AppLocalization.string("已限制为仅 Wi‑Fi 自动备份。")
            : AppLocalization.string("当前允许在蜂窝网络下自动备份，可能消耗移动数据流量。")
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
