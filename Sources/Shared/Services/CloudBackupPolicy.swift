import Foundation

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

enum CloudBackupRetentionCountOption: Int, CaseIterable, Identifiable {
    case keep3 = 3
    case keep5 = 5
    case keep10 = 10
    case keep20 = 20

    static let defaultValue = keep5.rawValue

    var id: Int { rawValue }

    var title: String {
        String(format: String(localized: "保留最近 %lld 份"), Int64(rawValue))
    }

    static func normalized(_ value: Int) -> Int {
        allCases.first(where: { $0.rawValue == value })?.rawValue ?? defaultValue
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

    static func loadRetentionCount() -> Int {
        let rawValue = UserPreferences.int(
            UserPreferenceKeys.cloudBackupRetentionCount,
            default: CloudBackupRetentionCountOption.defaultValue
        )
        return CloudBackupRetentionCountOption.normalized(rawValue)
    }

    static func loadLastSuccessDate() -> Date? {
        UserPreferencesStore.shared.unixDate(for: UserPreferenceKeys.cloudBackupLastSuccessAt)
    }

    static func saveLastSuccessDate(_ date: Date) {
        UserPreferencesStore.shared.setUnixDate(date, for: UserPreferenceKeys.cloudBackupLastSuccessAt)
    }

    static func loadAutoLastAttemptDate() -> Date? {
        UserPreferencesStore.shared.unixDate(for: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
    }

    static func saveAutoLastAttemptDate(_ date: Date) {
        UserPreferencesStore.shared.setUnixDate(date, for: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
    }

    static func saveAutoLastStatus(_ value: String) {
        UserPreferencesStore.shared.set(value, for: UserPreferenceKeys.cloudBackupAutoLastStatus)
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

        snapshot.removeExcludedReferenceLinks()

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
            // 图纸与项目资料的 fileName 会被归档写入器用来读取原件。关闭附件时，
            // 不能只清空 BackupFile 数组，否则仍会把这些原件上传到云端。
            snapshot.projectDrawings = snapshot.projectDrawings.map { drawing in
                var value = drawing
                value.fileName = ""
                return value
            }
            snapshot.projectDocuments = snapshot.projectDocuments.map { document in
                var value = document
                value.fileName = ""
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

    private mutating func removeExcludedReferenceLinks() {
        let projectIDs = Set(projects.map(\.id))
        let constructionMethodIDs = Set(constructionMethods.map(\.id))
        let documentProjectIDs = Dictionary(uniqueKeysWithValues: projectDocuments.map { ($0.id, $0.projectId) })
        let financialRecordProjectIDs = Dictionary(uniqueKeysWithValues: projectFinancialRecords.map { ($0.id, $0.projectId) })

        func validProject(_ id: UUID?) -> UUID? {
            guard let id, projectIDs.contains(id) else { return nil }
            return id
        }

        materialItems = materialItems.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        quoteItems = quoteItems.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        laborRecords = laborRecords.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        historyRecords = historyRecords.map { record in
            var value = record
            value.projectId = validProject(value.projectId)
            return value
        }
        quickNotes = quickNotes.map { note in
            var value = note
            value.projectId = validProject(value.projectId)
            return value
        }
        materialSheetDrafts = materialSheetDrafts.map { draft in
            var value = draft
            value.projectId = validProject(value.projectId)
            return value
        }
        dailyLogs = dailyLogs.map { log in
            var value = log
            value.projectId = validProject(value.projectId)
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            return value
        }
        siteTodos = siteTodos.map { todo in
            var value = todo
            value.projectId = validProject(value.projectId)
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            return value
        }
        projectContacts = projectContacts.map { contact in
            var value = contact
            value.relatedProjectIds = value.relatedProjectIds.filter(projectIDs.contains)
            return value
        }
        projectFinancialRecords = projectFinancialRecords.map { record in
            var value = record
            value.linkedDocumentIds = value.linkedDocumentIds.filter { documentProjectIDs[$0] == value.projectId }
            return value
        }
        projectWarehouseMovements = projectWarehouseMovements.map { movement in
            var value = movement
            value.linkedDocumentIds = value.linkedDocumentIds.filter { documentProjectIDs[$0] == value.projectId }
            return value
        }
        projectDocuments = projectDocuments.map { document in
            var value = document
            if let linkedFinancialRecordId = value.linkedFinancialRecordId,
               financialRecordProjectIDs[linkedFinancialRecordId] != value.projectId {
                value.linkedFinancialRecordId = nil
            }
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            value.replacesDocumentId = value.replacesDocumentId.flatMap {
                documentProjectIDs[$0] == value.projectId ? $0 : nil
            }
            value.replacedByDocumentId = value.replacedByDocumentId.flatMap {
                documentProjectIDs[$0] == value.projectId ? $0 : nil
            }
            return value
        }
    }
}

actor CloudBackupCoordinator {
    static let shared = CloudBackupCoordinator()

    func backupToCloud(
        snapshot: BackupSnapshot,
        progress: ((BackupArchiveProgress) -> Void)? = nil
    ) async throws -> CloudBackupExecutionResult {
        var archiveFileURL: URL?
        let retentionCount = CloudBackupSettingsStore.loadRetentionCount()
        do {
            let archive = try await FileIOTaskRunner.runWithRelay(
                priority: .userInitiated,
                logContext: .init(
                    event: "cloud_backup.make_archive",
                    source: "CloudBackupCoordinator.backupToCloud",
                    category: .zipArchive,
                    details: ["retention_count": "\(retentionCount)"]
                )
            ) { relay in
                try BackupArchiveService.makeArchive(
                    from: snapshot,
                    progress: progress,
                    shouldCancel: { relay.isCancelled() || Task.isCancelled }
                )
            }
            archiveFileURL = archive.fileURL

            let savedFile = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "cloud_backup.save_archive",
                    source: "CloudBackupCoordinator.backupToCloud",
                    category: .cloudBackup,
                    details: ["retention_count": "\(retentionCount)"]
                )
            ) {
                try Task.checkCancellation()
                return try CloudBackupService.saveArchiveToCloud(
                    archiveFileURL: archive.fileURL,
                    keepMostRecent: retentionCount
                )
            }

            let files = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "cloud_backup.list_after_upload",
                    source: "CloudBackupCoordinator.backupToCloud",
                    category: .cloudBackup
                )
            ) {
                try Task.checkCancellation()
                return try CloudBackupService.listBackups()
            }
            do {
                _ = try FileOps.removeIfExists(
                    at: archive.fileURL,
                    context: .init(
                        event: "cloud_backup.temp_archive_cleanup",
                        category: .cloudBackup,
                        source: "CloudBackupCoordinator.backupToCloud.afterUpload"
                    )
                )
            } catch {
                // FileOps 已记录失败，上传成功路径不因临时文件清理失败而中断。
            }
            archiveFileURL = nil
            return CloudBackupExecutionResult(savedFile: savedFile, allBackups: files)
        } catch {
            if let archiveFileURL {
                do {
                    _ = try FileOps.removeIfExists(
                        at: archiveFileURL,
                        context: .init(
                            event: "cloud_backup.temp_archive_cleanup",
                            category: .cloudBackup,
                            source: "CloudBackupCoordinator.backupToCloud.failureCleanup"
                        )
                    )
                } catch {
                    // FileOps 已记录失败，保持原始备份错误向上抛出。
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
        let interval = CloudBackupSettingsStore.loadAutoInterval()
        let now = Date()
        let options = CloudBackupSettingsStore.loadContentOptions()
        switch CloudBackupExecutionGate.evaluateSchedule(
            hasData: hasData,
            interval: interval,
            now: now,
            lastSuccess: CloudBackupSettingsStore.loadLastSuccessDate(),
            lastAttempt: CloudBackupSettingsStore.loadAutoLastAttemptDate(),
            retryCooldown: retryCooldown,
            options: options
        ) {
        case .allow:
            break
        case .skip(let statusMessage):
            if let statusMessage, !statusMessage.isEmpty {
                CloudBackupSettingsStore.saveAutoLastStatus(statusMessage)
            }
            return
        }

        let requiresWiFi = CloudBackupSettingsStore.loadAutoBackupRequiresWiFi()
        switch await CloudBackupExecutionGate.evaluateEnvironment(requiresWiFi: requiresWiFi) {
        case .allow:
            break
        case .skip(let statusMessage):
            if let statusMessage, !statusMessage.isEmpty {
                CloudBackupSettingsStore.saveAutoLastStatus(statusMessage)
            }
            return
        }

        isRunning = true
        CloudBackupSettingsStore.saveAutoLastAttemptDate(now)
        defer { isRunning = false }

        do {
            let snapshot = await MainActor.run {
                store.makeCloudBackupSnapshot(options: options)
            }
            switch CloudBackupExecutionGate.evaluateSnapshot(snapshot) {
            case .allow:
                break
            case .skip(let statusMessage):
                if let statusMessage, !statusMessage.isEmpty {
                    CloudBackupSettingsStore.saveAutoLastStatus(statusMessage)
                }
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

extension BackupSnapshot {
    var hasAnyBackupContent: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
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
