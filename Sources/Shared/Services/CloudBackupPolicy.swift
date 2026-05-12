import Foundation
import Network

struct CloudBackupContentOptions: Equatable {
    var includeBusinessRecords = true
    var includeProjectRecords = true
    var includeProjectFilesAndNotes = true
    var includeKnowledgeBase = true
    var includeAttachments = true

    static let all = CloudBackupContentOptions()

    var hasSelectedContent: Bool {
        includeBusinessRecords || includeProjectRecords || includeProjectFilesAndNotes || includeKnowledgeBase
    }

    func normalized() -> CloudBackupContentOptions {
        var copy = self
        if !copy.includeProjectRecords {
            copy.includeProjectFilesAndNotes = false
            copy.includeAttachments = false
        }
        if !copy.includeProjectFilesAndNotes {
            copy.includeAttachments = false
        }
        return copy
    }
}

enum CloudBackupAutoInterval: String, CaseIterable {
    case disabled
    case daily
    case every3Days
    case weekly

    var title: String {
        switch self {
        case .disabled:
            return "关闭"
        case .daily:
            return "每天"
        case .every3Days:
            return "每3天"
        case .weekly:
            return "每周"
        }
    }

    var minimumInterval: TimeInterval? {
        switch self {
        case .disabled:
            return nil
        case .daily:
            return 24 * 60 * 60
        case .every3Days:
            return 3 * 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        }
    }
}

enum CloudBackupSettingsStore {
    static func loadContentOptions() -> CloudBackupContentOptions {
        CloudBackupContentOptions(
            includeBusinessRecords: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeBusinessRecords, default: true),
            includeProjectRecords: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeProjectRecords, default: true),
            includeProjectFilesAndNotes: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeProjectFilesAndNotes, default: true),
            includeKnowledgeBase: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeKnowledgeBase, default: true),
            includeAttachments: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeAttachments, default: true)
        ).normalized()
    }

    static func loadAutoInterval() -> CloudBackupAutoInterval {
        let rawValue = UserPreferences.string(UserPreferenceKeys.cloudBackupAutoInterval, default: CloudBackupAutoInterval.disabled.rawValue)
        return StringEnumFallback.value(rawValue, default: .disabled)
    }

    static func loadAutoBackupRequiresWiFi() -> Bool {
        UserPreferences.bool(UserPreferenceKeys.cloudBackupAutoRequiresWiFi, default: false)
    }

    static func loadLastSuccessDate() -> Date? {
        let raw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func saveLastSuccessDate(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
    }

    static func loadAutoLastAttemptDate() -> Date? {
        let raw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func saveAutoLastAttemptDate(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
    }

    static func saveAutoLastStatus(_ value: String) {
        UserDefaults.standard.set(value, forKey: UserPreferenceKeys.cloudBackupAutoLastStatus)
    }
}

enum CloudNetworkPolicyChecker {
    static func isUsingWiFi(timeout: TimeInterval = 1.2) async -> Bool? {
        guard let path = await currentPath(timeout: timeout) else { return nil }
        guard path.status == .satisfied else { return false }
        return path.usesInterfaceType(.wifi)
    }

    private static func currentPath(timeout: TimeInterval) async -> NWPath? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.chengjinfang.sitekeeper.cloudbackup.network")
            var didResume = false

            let resume: (NWPath?) -> Void = { path in
                guard !didResume else { return }
                didResume = true
                monitor.cancel()
                continuation.resume(returning: path)
            }

            monitor.pathUpdateHandler = { path in
                resume(path)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                resume(nil)
            }
        }
    }
}

enum CloudBackupContentError: LocalizedError {
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "请至少选择一类需要备份的内容。"
        }
    }
}

struct CloudBackupExecutionResult {
    let savedFile: CloudBackupFile
    let allBackups: [CloudBackupFile]
}

@MainActor
extension DataStore {
    func makeCloudBackupSnapshot(options: CloudBackupContentOptions) -> BackupSnapshot {
        makeSnapshot(includePhotoFiles: false)
            .applyingCloudBackupContentOptions(options.normalized())
    }
}

extension BackupSnapshot {
    func applyingCloudBackupContentOptions(_ options: CloudBackupContentOptions) -> BackupSnapshot {
        let normalizedOptions = options.normalized()
        var snapshot = self

        if !normalizedOptions.includeBusinessRecords {
            snapshot.materialItems = []
            snapshot.quoteItems = []
            snapshot.laborRecords = []
            snapshot.historyRecords = []
        }

        if !normalizedOptions.includeProjectRecords {
            snapshot.projects = []
            snapshot.dailyLogs = []
            snapshot.progressTasks = []
            snapshot.lightingCircuitPlans = []
            snapshot.siteTodos = []
            snapshot.projectContacts = []
            snapshot.projectFinancialRecords = []
            snapshot.projectWarehouseMovements = []
        }

        if !normalizedOptions.includeProjectFilesAndNotes {
            snapshot.projectDrawings = []
            snapshot.projectDocuments = []
            snapshot.quickNotes = []
        }

        if !normalizedOptions.includeKnowledgeBase {
            snapshot.templates = []
            snapshot.materialPriceEntries = []
            snapshot.supplierProfiles = []
            snapshot.constructionMethods = []
            snapshot.favoriteMaterialKeys = []
            snapshot.recentMaterialKeys = []
        }

        if !normalizedOptions.includeAttachments {
            snapshot.dailyLogs = snapshot.dailyLogs.map { log in
                var value = log
                value.photoFileName = nil
                value.photos = []
                return value
            }
            snapshot.siteTodos = snapshot.siteTodos.map { todo in
                var value = todo
                value.rectificationBeforePhotoFileName = nil
                value.rectificationAfterPhotoFileName = nil
                return value
            }
            snapshot.quickNotes = snapshot.quickNotes.map { note in
                var value = note
                value.attachments = []
                return value
            }
            snapshot.constructionMethods = snapshot.constructionMethods.map { method in
                var value = method
                value.attachments = []
                value.tutorialAttachments = []
                return value
            }
            snapshot.photoFiles = []
            snapshot.drawingFiles = []
            snapshot.documentFiles = []
            snapshot.quickNoteAttachmentFiles = []
            return snapshot
        }

        let photoNames = Set(
            snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty }
        )
        let drawingNames = Set(snapshot.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let documentNames = Set(snapshot.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let quickNoteAttachmentNames = snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let constructionAttachmentNames = snapshot.constructionMethods.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let tutorialAttachmentNames = snapshot.constructionMethods.flatMap { $0.tutorialAttachments.map(\.fileName) }.filter { !$0.isEmpty }
        let attachmentNames = Set(quickNoteAttachmentNames + constructionAttachmentNames + tutorialAttachmentNames)

        snapshot.photoFiles = snapshot.photoFiles.filter { photoNames.contains($0.fileName) }
        snapshot.drawingFiles = snapshot.drawingFiles.filter { drawingNames.contains($0.fileName) }
        snapshot.documentFiles = snapshot.documentFiles.filter { documentNames.contains($0.fileName) }
        snapshot.quickNoteAttachmentFiles = snapshot.quickNoteAttachmentFiles.filter { attachmentNames.contains($0.fileName) }
        return snapshot
    }
}

actor CloudBackupCoordinator {
    static let shared = CloudBackupCoordinator()

    func backupToCloud(
        snapshot: BackupSnapshot,
        progress: ((BackupArchiveProgress) -> Void)? = nil
    ) async throws -> CloudBackupExecutionResult {
        var archiveFileURL: URL?
        let relay = TaskCancellationRelay()
        do {
            let archive = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    try BackupArchiveService.makeArchive(
                        from: snapshot,
                        progress: progress,
                        shouldCancel: { relay.isCancelled() || Task.isCancelled }
                    )
                }.value
            } onCancel: {
                relay.cancel()
            }
            archiveFileURL = archive.fileURL

            let savedFile = try await Task.detached(priority: .utility) {
                try CloudBackupService.saveArchiveToCloud(archiveFileURL: archive.fileURL)
            }.value
            let files = try await Task.detached(priority: .utility) {
                try CloudBackupService.listBackups()
            }.value
            do {
                try FileManager.default.removeItem(at: archive.fileURL)
            } catch {
                StorageIssueLog.record("云备份上传后清理临时包失败：\(archive.fileURL.lastPathComponent)，\(error.localizedDescription)")
            }
            archiveFileURL = nil
            return CloudBackupExecutionResult(savedFile: savedFile, allBackups: files)
        } catch {
            if let archiveFileURL {
                do {
                    try FileManager.default.removeItem(at: archiveFileURL)
                } catch {
                    StorageIssueLog.record("云备份异常清理临时包失败：\(archiveFileURL.lastPathComponent)，\(error.localizedDescription)")
                }
            }
            throw error
        }
    }
}

actor CloudAutoBackupScheduler {
    static let shared = CloudAutoBackupScheduler()
    private let retryCooldown: TimeInterval = 30 * 60
    private var isRunning = false

    func triggerIfNeeded(store: DataStore) async {
        guard !isRunning else { return }
        let hasData = await MainActor.run { store.hasAnyBusinessData }
        guard hasData else { return }
        let interval = CloudBackupSettingsStore.loadAutoInterval()
        guard let minimumInterval = interval.minimumInterval else { return }

        let now = Date()
        if let lastSuccess = CloudBackupSettingsStore.loadLastSuccessDate(),
           now.timeIntervalSince(lastSuccess) < minimumInterval {
            return
        }
        if let lastAttempt = CloudBackupSettingsStore.loadAutoLastAttemptDate(),
           now.timeIntervalSince(lastAttempt) < retryCooldown {
            return
        }

        let options = CloudBackupSettingsStore.loadContentOptions()
        guard options.hasSelectedContent else { return }

        let requiresWiFi = CloudBackupSettingsStore.loadAutoBackupRequiresWiFi()
        if requiresWiFi {
            let isWiFi = await CloudNetworkPolicyChecker.isUsingWiFi()
            guard isWiFi == true else {
                CloudBackupSettingsStore.saveAutoLastStatus("自动备份已跳过：当前不是 Wi‑Fi 网络。")
                return
            }
        }

        isRunning = true
        CloudBackupSettingsStore.saveAutoLastAttemptDate(now)
        defer { isRunning = false }

        do {
            let snapshot = await MainActor.run {
                store.makeCloudBackupSnapshot(options: options)
            }
            guard snapshot.hasAnyBackupContent else {
                CloudBackupSettingsStore.saveAutoLastStatus("自动备份已跳过：当前所选范围暂无可备份数据。")
                return
            }
            let _ = try await CloudBackupCoordinator.shared.backupToCloud(snapshot: snapshot)
            let successDate = Date()
            CloudBackupSettingsStore.saveLastSuccessDate(successDate)
            CloudBackupSettingsStore.saveAutoLastStatus("自动备份成功：\(Formatters.dateTime.string(from: successDate))")
        } catch {
            let failedAt = Date()
            CloudBackupSettingsStore.saveAutoLastStatus("自动备份失败（\(Formatters.dateTime.string(from: failedAt))）：\(error.localizedDescription)")
        }
    }
}

private extension BackupSnapshot {
    var hasAnyBackupContent: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
        !lightingCircuitPlans.isEmpty ||
        !siteTodos.isEmpty ||
        !projectDrawings.isEmpty ||
        !projectContacts.isEmpty ||
        !projectFinancialRecords.isEmpty ||
        !projectDocuments.isEmpty ||
        !quickNotes.isEmpty ||
        !projectWarehouseMovements.isEmpty ||
        !templates.isEmpty ||
        !materialPriceEntries.isEmpty ||
        !supplierProfiles.isEmpty ||
        !constructionMethods.isEmpty ||
        !favoriteMaterialKeys.isEmpty ||
        !recentMaterialKeys.isEmpty ||
        !userMaterials.isEmpty ||
        !deletedUserMaterials.isEmpty ||
        !hiddenPresetKeys.isEmpty
    }
}
