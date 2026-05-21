import SwiftUI

struct StorageCleanupCenterView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @AppStorage(UserPreferenceKeys.storageCleanupLargeFileThresholdMB) private var largeFileThresholdMB = StorageCleanupLargeFileThresholdOption.defaultMegabytes
    @AppStorage(UserPreferenceKeys.storageCleanupTrashRetentionDays) private var cleanupTrashRetentionDays = StorageCleanupTrashRetentionOption.defaultDays
    @State private var cloudBackups: [CloudBackupFile] = []
    @State private var cloudBackupError: String?
    @State private var isRefreshingCloudBackups = false
    @State private var projectBackupEstimateByID: [UUID: Int] = [:]
    @State private var isRefreshingProjectBackupEstimates = false
    @State private var pendingCleanupProject: ProjectStorageUsage?
    @State private var pendingCleanupCategory: ProjectStorageCleanupCategory = .all
    @State private var showCleanupProjectAlert = false
    @State private var cleanupStatusMessage = ""
    @State private var cleanupTrashBatches: [StorageCleanupTrashBatch] = []
    @State private var quarantinedFiles: [FileQuarantineEntry] = []

    private let showsNavigationTitle: Bool
    private let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "hevc"]
    private let drawingSourceFileExtensions: Set<String> = ["dwg", "dxf"]

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
                    Text(String(format: String(localized: "云备份读取失败：%@"), cloudBackupError))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            cleanupTrashPolicySection

            cleanupTrashSection

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
        .modifier(StorageOptionalInlineTitleModifier(isEnabled: showsNavigationTitle, title: String(localized: "存储清理中心")))
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
            String(localized: "清理项目文件？"),
            isPresented: $showCleanupProjectAlert,
            presenting: pendingCleanupProject
        ) { usage in
            Button(pendingCleanupCategory.confirmationButtonTitle, role: .destructive) {
                cleanupProjectFiles(usage, category: pendingCleanupCategory)
            }
            Button(String(localized: "取消"), role: .cancel) {
                pendingCleanupProject = nil
            }
        } message: { usage in
            Text(cleanupConfirmationMessage(for: usage, category: pendingCleanupCategory))
        }
    }

    private var largeFileThresholdBytes: Int {
        StorageCleanupLargeFileThresholdOption.bytes(for: largeFileThresholdMB)
    }

    private var normalizedCleanupTrashRetentionDays: Int {
        StorageCleanupTrashRetentionOption.normalizedDays(cleanupTrashRetentionDays)
    }

    private var cleanupTrashRecoveryDeadlineText: String {
        Formatters.date.string(from: cleanupTrashExpirationDate(from: Date()))
    }

    private var cleanupTrashPolicySection: some View {
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

    private var cleanupTrashSection: some View {
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
                    restoreCleanupTrash(batch)
                } label: {
                    Label(String(localized: "恢复"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    permanentlyDeleteCleanupTrash(batch)
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
                    restoreQuarantinedFile(entry)
                } label: {
                    Label(String(localized: "恢复"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    permanentlyDeleteQuarantinedFile(entry)
                } label: {
                    Label(String(localized: "永久删除"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }

    private var largeFileRuleSuggestionText: String {
        String(
            format: String(localized: "建议规则：照片≥%@、视频≥%@、票据资料≥%@ 时优先检查。"),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.photo.bytes),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.video.bytes),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.ticket.bytes)
        )
    }

    private var scanResult: StorageCleanupScanResult {
        StorageCleanupScanner.scan(
            store: store,
            cloudBackups: cloudBackups,
            projectBackupEstimateByID: projectBackupEstimateByID,
            largeFileThresholdBytes: largeFileThresholdBytes,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    private var categorySummaries: [StorageCategorySummary] {
        scanResult.categorySummaries
    }

    private var largeFileItems: [StorageLargeFileItem] {
        scanResult.largeFileItems
    }

    private var projectUsages: [ProjectStorageUsage] {
        scanResult.projectUsages
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

    private func normalizeLargeFileThresholdPreference() {
        let normalized = StorageCleanupLargeFileThresholdOption.normalizedMegabytes(largeFileThresholdMB)
        if largeFileThresholdMB != normalized {
            largeFileThresholdMB = normalized
        }
    }

    private func normalizeCleanupTrashRetentionPreference() {
        let normalized = StorageCleanupTrashRetentionOption.normalizedDays(cleanupTrashRetentionDays)
        if cleanupTrashRetentionDays != normalized {
            cleanupTrashRetentionDays = normalized
        }
    }

    private func cleanupTrashExpirationDate(from date: Date) -> Date {
        let retentionDays = max(normalizedCleanupTrashRetentionDays, 1)
        return Calendar.current.date(byAdding: .day, value: retentionDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(retentionDays * 24 * 60 * 60))
    }

    private func refreshCloudBackups() async {
        guard !isRefreshingCloudBackups else { return }
        isRefreshingCloudBackups = true
        defer { isRefreshingCloudBackups = false }

        let task = Task.detached(priority: .utility) { () -> ([CloudBackupFile], String?) in
            do {
                return (try CloudBackupService.listBackups(), nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }
        let (backups, errorMessage) = await task.value

        if let errorMessage, !errorMessage.isEmpty {
            cloudBackups = []
            cloudBackupError = errorMessage
            StorageIssueLog.record(String(format: String(localized: "存储清理中心读取云备份失败：%@"), errorMessage))
        } else {
            cloudBackups = backups
            cloudBackupError = nil
        }
    }

    private func cleanupConfirmationMessage(for usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) -> String {
        let preview = cleanupPreview(for: usage.projectId, category: category)
        var lines: [String] = [category.confirmationMessage(projectName: usage.projectName)]

        if preview.totalFileCount > 0 {
            lines.append(String(format: String(localized: "预计删除文件 %lld 个："), Int64(preview.totalFileCount)))
            for item in preview.fileItems {
                lines.append(String(format: String(localized: "- %@ %lld 个"), item.title, Int64(item.count)))
            }
        } else {
            lines.append(String(localized: "预计删除文件 0 个。"))
        }

        lines.append(String(localized: "预计影响记录："))
        if preview.recordItems.isEmpty {
            lines.append(String(localized: "- 无关联记录变更"))
        } else {
            for item in preview.recordItems {
                lines.append(String(format: String(localized: "- %@ %lld 条"), item.title, Int64(item.count)))
            }
        }

        if !preview.sampleFileNames.isEmpty {
            let sampleSeparator = String(localized: "、")
            lines.append(String(format: String(localized: "示例文件：%@"), preview.sampleFileNames.prefix(5).joined(separator: sampleSeparator)))
        }

        lines.append(
            String(
                format: String(localized: "清理后文件将进入回收站，可恢复至 %@（%lld 天内）。"),
                Formatters.date.string(from: cleanupTrashExpirationDate(from: Date())),
                Int64(normalizedCleanupTrashRetentionDays)
            )
        )
        lines.append(backupReminderMessage())
        return lines.joined(separator: "\n")
    }

    private func cleanupPreview(for projectId: UUID, category: ProjectStorageCleanupCategory) -> CleanupImpactSummary {
        StorageCleanupScanner.cleanupPreview(
            store: store,
            projectId: projectId,
            category: category,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    private func backupReminderMessage() -> String {
        guard let latestDate = latestBackupDateForReminder else {
            return String(localized: "最近备份：未检测到本机或云备份，建议先执行备份后再清理。")
        }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latestDate)
        let today = calendar.startOfDay(for: Date())
        let daysSinceBackup = max(calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0, 0)
        let formattedDate = Formatters.dateTime.string(from: latestDate)
        let reminderDays = max(1, backupHealthReminderDays)

        if daysSinceBackup >= reminderDays {
            return String(format: String(localized: "最近备份：%@（%lld 天前），建议先备份后再清理。"), formattedDate, Int64(daysSinceBackup))
        }

        return String(format: String(localized: "最近备份：%@。"), formattedDate)
    }

    private var latestBackupDateForReminder: Date? {
        var candidates: [Date] = []
        if localBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: localBackupLastSuccessAt))
        }
        if cloudBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: cloudBackupLastSuccessAt))
        }
        if let latestCloudBackup = cloudBackups.first?.modifiedAt {
            candidates.append(latestCloudBackup)
        }
        return candidates.max()
    }

    private func refreshCleanupTrash() {
        let now = Date()
        let purgedCount = StorageCleanupTrashStore.purgeExpiredBatches(now: now)
        let purgedFileCount = FileQuarantineStore.purgeExpiredEntries(now: now)
        cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
        quarantinedFiles = FileQuarantineStore.loadEntries()
        if purgedCount > 0 {
            StorageIssueLog.record(
                String(
                    format: String(localized: "清理回收站已自动永久删除 %lld 个过期批次。"),
                    Int64(purgedCount)
                )
            )
        }
        if purgedFileCount > 0 {
            StorageIssueLog.record(
                String(
                    format: String(localized: "回收站已自动永久删除 %lld 个过期隔离文件。"),
                    Int64(purgedFileCount)
                )
            )
        }
    }

    private func restoreCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        OperationAuditLog.record(
            action: .restore,
            outcome: .started,
            summary: String(localized: "恢复清理回收站"),
            detail: batch.summary,
            source: "StorageCleanupCenterView"
        )
        do {
            try StorageCleanupTrashStore.restore(batch)
            batch.snapshot.restore(into: store)
            store.scheduleSave()
            refreshCleanupTrash()
            cleanupStatusMessage = String(
                format: String(localized: "已从清理回收站恢复：%@。"),
                batch.summary
            )
            OperationAuditLog.record(
                action: .restore,
                outcome: .succeeded,
                summary: String(localized: "恢复清理回收站"),
                detail: "\(batch.summary) · restored=\(batch.fileCount)",
                source: "StorageCleanupCenterView"
            )
        } catch {
            cleanupStatusMessage = String(
                format: String(localized: "清理回收站恢复失败：%@"),
                error.localizedDescription
            )
            OperationAuditLog.record(
                action: .restore,
                outcome: .failed,
                summary: String(localized: "恢复清理回收站"),
                detail: "\(batch.summary) · error=\(error.localizedDescription)",
                source: "StorageCleanupCenterView"
            )
        }
    }

    private func permanentlyDeleteCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: String(localized: "永久删除清理回收站"),
            detail: batch.summary,
            source: "StorageCleanupCenterView"
        )
        do {
            try StorageCleanupTrashStore.permanentlyDelete(batch)
            refreshCleanupTrash()
            cleanupStatusMessage = String(
                format: String(localized: "已永久删除清理回收站批次：%@。"),
                batch.summary
            )
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .succeeded,
                summary: String(localized: "永久删除清理回收站"),
                detail: "\(batch.summary) · deleted=\(batch.fileCount)",
                source: "StorageCleanupCenterView"
            )
        } catch {
            cleanupStatusMessage = String(
                format: String(localized: "永久删除清理回收站失败：%@"),
                error.localizedDescription
            )
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .failed,
                summary: String(localized: "永久删除清理回收站"),
                detail: "\(batch.summary) · error=\(error.localizedDescription)",
                source: "StorageCleanupCenterView"
            )
        }
    }

    private func restoreQuarantinedFile(_ entry: FileQuarantineEntry) {
        OperationAuditLog.record(
            action: .restore,
            outcome: .started,
            summary: String(localized: "恢复隔离文件"),
            detail: "\(entry.category.rawValue) · \(entry.originalFileName)",
            source: "StorageCleanupCenterView"
        )
        do {
            try FileQuarantineStore.restore(entry)
            refreshCleanupTrash()
            cleanupStatusMessage = String(
                format: String(localized: "已从回收站恢复隔离文件：%@。"),
                entry.originalFileName
            )
            OperationAuditLog.record(
                action: .restore,
                outcome: .succeeded,
                summary: String(localized: "恢复隔离文件"),
                detail: "\(entry.category.rawValue) · \(entry.originalFileName)",
                source: "StorageCleanupCenterView"
            )
        } catch {
            cleanupStatusMessage = String(
                format: String(localized: "隔离文件恢复失败：%@"),
                error.localizedDescription
            )
            OperationAuditLog.record(
                action: .restore,
                outcome: .failed,
                summary: String(localized: "恢复隔离文件"),
                detail: "\(entry.category.rawValue) · \(entry.originalFileName) · error=\(error.localizedDescription)",
                source: "StorageCleanupCenterView"
            )
        }
    }

    private func permanentlyDeleteQuarantinedFile(_ entry: FileQuarantineEntry) {
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: String(localized: "永久删除隔离文件"),
            detail: "\(entry.category.rawValue) · \(entry.originalFileName)",
            source: "StorageCleanupCenterView"
        )
        do {
            try FileQuarantineStore.permanentlyDelete(entry)
            refreshCleanupTrash()
            cleanupStatusMessage = String(
                format: String(localized: "已永久删除隔离文件：%@。"),
                entry.originalFileName
            )
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .succeeded,
                summary: String(localized: "永久删除隔离文件"),
                detail: "\(entry.category.rawValue) · \(entry.originalFileName)",
                source: "StorageCleanupCenterView"
            )
        } catch {
            cleanupStatusMessage = String(
                format: String(localized: "隔离文件永久删除失败：%@"),
                error.localizedDescription
            )
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .failed,
                summary: String(localized: "永久删除隔离文件"),
                detail: "\(entry.category.rawValue) · \(entry.originalFileName) · error=\(error.localizedDescription)",
                source: "StorageCleanupCenterView"
            )
        }
    }

    private func cleanupProjectFiles(_ usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) {
        let projectId = usage.projectId
        let auditDetail = "\(usage.projectName) · \(category.displayName)"
        let undoSnapshot = StorageCleanupUndoSnapshot.capture(from: store)
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: String(localized: "按项目清理"),
            detail: auditDetail,
            source: "StorageCleanupCenterView"
        )
        var cleanupPlan = DeferredProjectFileCleanupPlan()

        switch category {
        case .photos:
            cleanupPlan.merge(cleanupProjectPhotos(projectId))
        case .videos:
            cleanupPlan.merge(cleanupProjectVideos(projectId))
        case .drawings:
            cleanupPlan.merge(cleanupProjectDrawings(projectId))
        case .tickets:
            cleanupPlan.merge(cleanupProjectTickets(projectId))
        case .all:
            cleanupPlan.merge(cleanupProjectPhotos(projectId))
            cleanupPlan.merge(cleanupProjectVideos(projectId))
            cleanupPlan.merge(cleanupProjectDrawings(projectId))
            cleanupPlan.merge(cleanupProjectTickets(projectId))
        }

        let summary = String(
            format: String(localized: "%@ · %@"),
            usage.projectName,
            category.resultTitle
        )
        do {
            let retentionDays = normalizedCleanupTrashRetentionDays
            let batch = try StorageCleanupTrashStore.quarantine(
                plan: cleanupPlan,
                snapshot: undoSnapshot,
                summary: summary,
                retentionDays: retentionDays
            )
            refreshCleanupTrash()
            cleanupStatusMessage = String(
                format: String(localized: "已将 %@ 的%@移入清理回收站：%lld 个文件，可恢复至 %@。"),
                usage.projectName,
                category.resultTitle,
                Int64(batch.fileCount),
                Formatters.date.string(from: batch.expiresAt)
            )
            store.scheduleSave()
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .succeeded,
                summary: String(localized: "按项目清理"),
                detail: "\(auditDetail) · trashed=\(batch.fileCount) · retentionDays=\(retentionDays)",
                source: "StorageCleanupCenterView"
            )
        } catch {
            undoSnapshot.restore(into: store)
            cleanupStatusMessage = String(
                format: String(localized: "清理回收站写入失败：%@"),
                error.localizedDescription
            )
            store.scheduleSave()
            OperationAuditLog.record(
                action: .cleanup,
                outcome: .failed,
                summary: String(localized: "按项目清理"),
                detail: "\(auditDetail) · error=\(error.localizedDescription)",
                source: "StorageCleanupCenterView"
            )
        }
        pendingCleanupProject = nil
    }

    @discardableResult
    private func cleanupProjectPhotos(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectPhotoReferences(projectId: projectId)
        )
    }

    @discardableResult
    private func cleanupProjectVideos(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        return DeferredProjectFileCleanupPlan(
            store.clearProjectVideoReferences(
                projectId: projectId,
                videoFileExtensions: videoFileExtensions
            )
        )
    }

    @discardableResult
    private func cleanupProjectDrawings(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectDrawingSourceReferences(
                projectId: projectId,
                drawingFileExtensions: drawingSourceFileExtensions
            )
        )
    }

    @discardableResult
    private func cleanupProjectTickets(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectTicketDocumentReferences(projectId: projectId)
        )
    }

    @MainActor
    private func refreshProjectBackupEstimates() async {
        guard !isRefreshingProjectBackupEstimates else { return }
        isRefreshingProjectBackupEstimates = true
        defer { isRefreshingProjectBackupEstimates = false }

        let baseSnapshot = store.makeSnapshot(includePhotoFiles: false)
        let projectIDs = store.projects.map(\.id)
        let estimateTask = Task.detached(priority: .utility) { () -> [UUID: Int] in
            var estimates: [UUID: Int] = [:]
            estimates.reserveCapacity(projectIDs.count)

            for projectId in projectIDs {
                let scopedSnapshot = StorageCleanupScanner.makeProjectScopedSnapshot(from: baseSnapshot, projectId: projectId)
                estimates[projectId] = StorageCleanupScanner.estimateBackupBytes(for: scopedSnapshot)
            }
            return estimates
        }

        projectBackupEstimateByID = await estimateTask.value
    }
}
