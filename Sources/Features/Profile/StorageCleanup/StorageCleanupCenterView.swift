import SwiftUI

struct StorageCleanupCenterView: View {
    @Environment(DataStore.self) var store
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) var cloudBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) var backupHealthReminderDays = 7
    @AppStorage(UserPreferenceKeys.storageCleanupLargeFileThresholdMB) var largeFileThresholdMB = StorageCleanupLargeFileThresholdOption.defaultMegabytes
    @AppStorage(UserPreferenceKeys.storageCleanupTrashRetentionDays) var cleanupTrashRetentionDays = StorageCleanupTrashRetentionOption.defaultDays
    @State var cloudBackups: [CloudBackupFile] = []
    @State var cloudBackupError: String?
    @State var isRefreshingCloudBackups = false
    @State var projectBackupEstimateByID: [UUID: Int] = [:]
    @State var isRefreshingProjectBackupEstimates = false
    @State var hasCompletedInitialStorageLoad = false
    @State var pendingCleanupProject: ProjectStorageUsage?
    @State private var pendingCleanupCategory: ProjectStorageCleanupCategory = .all
    @State private var showCleanupProjectAlert = false
    @State var cleanupStatusMessage = ""
    @State var cleanupTrashBatches: [StorageCleanupTrashBatch] = []
    @State var quarantinedFiles: [FileQuarantineEntry] = []
    @State var scanResult: StorageCleanupScanResult = .empty

    private let showsNavigationTitle: Bool
    private let bottomContentInset: CGFloat
    private let onMobileScrollOffsetChange: ((CGFloat) -> Void)?
    let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "hevc"]
    let drawingSourceFileExtensions: Set<String> = ["dwg", "dxf"]

    init(
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        onMobileScrollOffsetChange: ((CGFloat) -> Void)? = nil
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.onMobileScrollOffsetChange = onMobileScrollOffsetChange
    }

    var body: some View {
        List {
            if onMobileScrollOffsetChange != nil {
                DataManagementMobileScrollProbeRow(onOffsetChange: onMobileScrollOffsetChange)
            }

            if !cleanupStatusMessage.isEmpty {
                Section {
                    Text(cleanupStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let cloudBackupError, !cloudBackupError.isEmpty {
                Section {
                    Text(StorageCleanupSectionCopy.cloudBackupReadFailed(cloudBackupError))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            StorageCleanupTrashPolicySection(
                cleanupTrashRetentionDays: $cleanupTrashRetentionDays,
                cleanupTrashRecoveryDeadlineText: cleanupTrashRecoveryDeadlineText
            )

            StorageCleanupTrashSection(
                cleanupTrashBatches: cleanupTrashBatches,
                quarantinedFiles: quarantinedFiles,
                normalizedCleanupTrashRetentionDays: normalizedCleanupTrashRetentionDays,
                onRestoreCleanupTrash: restoreCleanupTrash,
                onPermanentlyDeleteCleanupTrash: permanentlyDeleteCleanupTrash,
                onRestoreQuarantinedFile: restoreQuarantinedFile,
                onPermanentlyDeleteQuarantinedFile: permanentlyDeleteQuarantinedFile
            )

            StorageCleanupSummarySection(categorySummaries: categorySummaries)

            StorageCleanupLargeFileSections(
                largeFileThresholdMB: $largeFileThresholdMB,
                largeFileRuleSuggestionText: largeFileRuleSuggestionText,
                largeFileItems: largeFileItems
            )

            StorageCleanupProjectSection(projectUsages: projectUsages) { usage, category in
                pendingCleanupProject = usage
                pendingCleanupCategory = category
                showCleanupProjectAlert = true
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .modifier(StorageOptionalInlineTitleModifier(isEnabled: showsNavigationTitle, title: StorageCleanupSectionCopy.centerNavigationTitle))
        .onAppear {
            normalizeLargeFileThresholdPreference()
            normalizeCleanupTrashRetentionPreference()
            refreshCleanupTrash()
        }
        .task {
            await refreshInitialStorageData()
        }
        .task(id: store.dataVersion) {
            guard hasCompletedInitialStorageLoad else { return }
            await refreshProjectBackupEstimates()
        }
        .onChange(of: largeFileThresholdMB) { _, _ in
            normalizeLargeFileThresholdPreference()
            refreshScanResult()
        }
        .alert(
            StorageCleanupSectionCopy.cleanupProjectFilesAlertTitle,
            isPresented: $showCleanupProjectAlert,
            presenting: pendingCleanupProject
        ) { usage in
            Button(pendingCleanupCategory.confirmationButtonTitle, role: .destructive) {
                cleanupProjectFiles(usage, category: pendingCleanupCategory)
            }
            Button(StorageCleanupSectionCopy.cancelActionTitle, role: .cancel) {
                pendingCleanupProject = nil
            }
        } message: { usage in
            Text(cleanupConfirmationMessage(for: usage, category: pendingCleanupCategory))
        }
    }

    var normalizedCleanupTrashRetentionDays: Int {
        StorageCleanupTrashRetentionOption.normalizedDays(cleanupTrashRetentionDays)
    }

    private var cleanupTrashRecoveryDeadlineText: String {
        Formatters.date.string(from: cleanupTrashExpirationDate(from: Date()))
    }

    private var largeFileRuleSuggestionText: String {
        StorageCleanupSectionCopy.largeFileRuleSuggestion(
            photo: QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.photo.bytes),
            video: QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.video.bytes),
            ticket: QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.ticket.bytes)
        )
    }
}
