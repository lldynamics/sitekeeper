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
    @State var pendingCleanupProject: ProjectStorageUsage?
    @State private var pendingCleanupCategory: ProjectStorageCleanupCategory = .all
    @State private var showCleanupProjectAlert = false
    @State var cleanupStatusMessage = ""
    @State var cleanupTrashBatches: [StorageCleanupTrashBatch] = []
    @State var quarantinedFiles: [FileQuarantineEntry] = []

    private let showsNavigationTitle: Bool
    let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "hevc"]
    let drawingSourceFileExtensions: Set<String> = ["dwg", "dxf"]

    init(showsNavigationTitle: Bool = true) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    var body: some View {
        List {
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
        .modifier(StorageOptionalInlineTitleModifier(isEnabled: showsNavigationTitle, title: StorageCleanupSectionCopy.centerNavigationTitle))
        .onAppear {
            normalizeLargeFileThresholdPreference()
            normalizeCleanupTrashRetentionPreference()
            refreshCleanupTrash()
        }
        .task {
            await refreshCloudBackups()
            await refreshProjectBackupEstimates()
        }
        .task(id: store.dataVersion) {
            await refreshProjectBackupEstimates()
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
