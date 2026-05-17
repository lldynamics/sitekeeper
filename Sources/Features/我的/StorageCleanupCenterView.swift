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

    private let showsNavigationTitle: Bool
    private let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "hevc"]
    private let cadFileExtensions: Set<String> = ["dwg", "dxf"]

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

            Section(String(localized: "按项目清理")) {
                if projectUsages.isEmpty {
                    Text(String(localized: "暂无可清理项目文件。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectUsages) { usage in
                        NavigationLink {
                            ProjectStorageCleanupDetailView(usage: usage) { category in
                                pendingCleanupProject = usage
                                pendingCleanupCategory = category
                                showCleanupProjectAlert = true
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
            if cleanupTrashBatches.isEmpty {
                Text(String(localized: "暂无可恢复的清理记录。"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cleanupTrashBatches) { batch in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(batch.summary)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(String(format: String(localized: "%lld 个文件"), Int64(batch.fileCount)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.appWarning)
                        }
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
            }
        } header: {
            Text(String(localized: "清理回收站"))
        } footer: {
            Text(
                String(
                    format: String(localized: "项目文件清理后会先进入回收站，当前保留 %lld 天。过期批次会在进入本页时自动永久删除。"),
                    Int64(normalizedCleanupTrashRetentionDays)
                )
            )
        }
    }

    private var largeFileRuleSuggestionText: String {
        String(
            format: String(localized: "建议规则：照片≥%@、视频≥%@、票据资料≥%@ 时优先检查。"),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.photo.bytes),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.video.bytes),
            QuickNoteAttachmentStorage.formattedFileSize(StorageCleanupLargeFileRuleSuggestion.ticket.bytes)
        )
    }

    private var categorySummaries: [StorageCategorySummary] {
        [
            StorageCategorySummary(
                title: String(localized: "照片"),
                icon: "photo.fill",
                tint: .appWarning,
                bytes: photoEntries.reduce(0) { $0 + $1.bytes },
                count: photoEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "视频"),
                icon: "video.fill",
                tint: .appPhoto,
                bytes: videoEntries.reduce(0) { $0 + $1.bytes },
                count: videoEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "CAD 图纸"),
                icon: "compass.drawing",
                tint: .appDoc,
                bytes: cadEntries.reduce(0) { $0 + $1.bytes },
                count: cadEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "票据资料"),
                icon: "doc.text.fill",
                tint: .appRisk,
                bytes: ticketEntries.reduce(0) { $0 + $1.bytes },
                count: ticketEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "备份（iCloud）"),
                icon: "icloud.and.arrow.up.fill",
                tint: .appPrimaryAction,
                bytes: cloudBackups.reduce(0) { $0 + $1.byteSize },
                count: cloudBackups.count
            ),
            StorageCategorySummary(
                title: String(localized: "历史计算"),
                icon: "clock.arrow.circlepath",
                tint: .appSuccess,
                bytes: historyBytes,
                count: store.historyRecords.count
            )
        ]
    }

    private var largeFileItems: [StorageLargeFileItem] {
        var items = (photoEntries + videoEntries + cadEntries + ticketEntries + backupEntries)
            .filter { $0.bytes >= largeFileThresholdBytes }
        if historyBytes >= largeFileThresholdBytes {
            items.append(
                StorageLargeFileItem(
                    id: "history-records",
                    category: .history,
                    title: String(localized: "历史计算记录"),
                    detail: String(format: String(localized: "%lld 条"), Int64(store.historyRecords.count)),
                    projectName: nil,
                    bytes: historyBytes
                )
            )
        }
        return items.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private var projectUsages: [ProjectStorageUsage] {
        store.projects.compactMap { project in
            let projectId = project.id
            let photoBytes = photoEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let videoBytes = videoEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let cadBytes = cadEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let ticketBytes = ticketEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let total = photoBytes + videoBytes + cadBytes + ticketBytes
            guard total > 0 else { return nil }
            return ProjectStorageUsage(
                projectId: projectId,
                projectName: project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未命名项目") : project.name,
                photoBytes: photoBytes,
                videoBytes: videoBytes,
                cadBytes: cadBytes,
                ticketBytes: ticketBytes,
                backupEstimatedBytes: projectBackupEstimateByID[projectId]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.projectName.localizedStandardCompare(rhs.projectName) == .orderedAscending
        }
    }

    private var photoEntries: [StorageLargeFileItem] {
        var entries: [StorageLargeFileItem] = []
        var seen = Set<String>()
        for log in store.dailyLogs {
            let projectName = projectName(for: log.projectId)
            for photo in log.photoAttachments {
                guard seen.insert(photo.fileName).inserted else { continue }
                let bytes = PhotoStorage.fileSize(for: photo.fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "photo-\(photo.fileName)",
                        category: .photo,
                        title: photo.fileName,
                        detail: log.date,
                        projectId: log.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }
        for todo in store.siteTodos {
            let projectName = projectName(for: todo.projectId)
            let candidates: [(String?, String)] = [
                (todo.rectificationBeforePhotoFileName, String(localized: "整改前")),
                (todo.rectificationAfterPhotoFileName, String(localized: "整改后"))
            ]
            for (fileName, phase) in candidates {
                guard let fileName, seen.insert(fileName).inserted else { continue }
                let bytes = PhotoStorage.fileSize(for: fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "photo-\(fileName)",
                        category: .photo,
                        title: "\(todo.title) · \(phase)",
                        detail: fileName,
                        projectId: todo.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }
        return entries
    }

    private var videoEntries: [StorageLargeFileItem] {
        var entries: [StorageLargeFileItem] = []
        var seen = Set<String>()

        for note in store.quickNotes {
            let projectName = projectName(for: note.projectId)
            for attachment in note.attachments where attachment.attachmentKind == .video {
                guard seen.insert(attachment.fileName).inserted else { continue }
                let bytes = QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "video-\(attachment.fileName)",
                        category: .video,
                        title: attachment.displayName,
                        detail: note.title.isEmpty ? note.createdAt : note.title,
                        projectId: note.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }

        for document in store.projectDocuments {
            let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard videoFileExtensions.contains(ext),
                  !isTicketCategory(document.category),
                  seen.insert(document.fileName).inserted else { continue }
            let bytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            guard bytes > 0 else { continue }
            entries.append(
                StorageLargeFileItem(
                    id: "video-doc-\(document.fileName)",
                    category: .video,
                    title: document.title.isEmpty ? document.fileName : document.title,
                    detail: document.fileName,
                    projectId: document.projectId,
                    projectName: projectName(for: document.projectId),
                    bytes: bytes
                )
            )
        }
        return entries
    }

    private var cadEntries: [StorageLargeFileItem] {
        store.projectDrawings.compactMap { drawing in
            let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard cadFileExtensions.contains(ext) else { return nil }
            let bytes = DrawingStorage.fileSize(for: drawing.fileName)
            guard bytes > 0 else { return nil }
            return StorageLargeFileItem(
                id: "cad-\(drawing.fileName)",
                category: .cad,
                title: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                detail: "\(drawing.version) · \(drawing.fileName)",
                projectId: drawing.projectId,
                projectName: projectName(for: drawing.projectId),
                bytes: bytes
            )
        }
    }

    private var ticketEntries: [StorageLargeFileItem] {
        store.projectDocuments.compactMap { document in
            guard isTicketCategory(document.category) else { return nil }
            let bytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            guard bytes > 0 else { return nil }
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return StorageLargeFileItem(
                id: "ticket-\(document.id.uuidString)",
                category: .ticket,
                title: title.isEmpty ? document.fileName : title,
                detail: "\(document.category.displayName) · \(document.fileName)",
                projectId: document.projectId,
                projectName: projectName(for: document.projectId),
                bytes: bytes
            )
        }
    }

    private var backupEntries: [StorageLargeFileItem] {
        cloudBackups.map { backup in
            StorageLargeFileItem(
                id: "backup-\(backup.id)",
                category: .backup,
                title: backup.fileName,
                detail: backup.formattedModifiedAt,
                projectName: nil,
                bytes: backup.byteSize
            )
        }
    }

    private var historyBytes: Int {
        (try? JSONEncoder().encode(store.historyRecords).count) ?? 0
    }

    private func projectName(for projectId: UUID?) -> String? {
        guard let projectId else { return nil }
        if let project = store.projects.first(where: { $0.id == projectId }) {
            let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "未命名项目") : trimmed
        }
        return String(localized: "未知项目")
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

    private func isTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
        switch category {
        case .invoice, .receipt, .paymentRequest:
            return true
        default:
            return false
        }
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
        switch category {
        case .photos:
            return photoCleanupPreview(projectId: projectId)
        case .videos:
            return videoCleanupPreview(projectId: projectId)
        case .cad:
            return cadCleanupPreview(projectId: projectId)
        case .tickets:
            return ticketCleanupPreview(projectId: projectId)
        case .all:
            var summary = CleanupImpactSummary()
            summary.merge(photoCleanupPreview(projectId: projectId))
            summary.merge(videoCleanupPreview(projectId: projectId))
            summary.merge(cadCleanupPreview(projectId: projectId))
            summary.merge(ticketCleanupPreview(projectId: projectId))
            return summary
        }
    }

    private func photoCleanupPreview(projectId: UUID) -> CleanupImpactSummary {
        let projectLogs = store.dailyLogs.filter { $0.projectId == projectId }
        let projectTodos = store.siteTodos.filter { $0.projectId == projectId }
        let logsWithPhotos = projectLogs.filter { !$0.allPhotoFileNames.isEmpty }
        let todosWithPhotos = projectTodos.filter {
            $0.rectificationBeforePhotoFileName != nil || $0.rectificationAfterPhotoFileName != nil
        }

        var selectedPhotoNames = Set<String>()
        for log in projectLogs {
            selectedPhotoNames.formUnion(log.allPhotoFileNames)
        }
        for todo in projectTodos {
            if let before = todo.rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = todo.rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
        }
        let remainingLogs = store.dailyLogs.filter { $0.projectId != projectId }
        let remainingTodos = store.siteTodos.filter { $0.projectId != projectId }
        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: remainingLogs, todos: remainingTodos)
        let deletablePhotoNames = selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "照片原文件"), count: deletablePhotoNames.count)
        summary.addRecord(title: String(localized: "日志照片记录"), count: logsWithPhotos.count)
        summary.addRecord(title: String(localized: "待办整改照片"), count: todosWithPhotos.count)
        summary.addSampleFileNames(deletablePhotoNames)
        return summary
    }

    private func videoCleanupPreview(projectId: UUID) -> CleanupImpactSummary {
        let projectNotes = store.quickNotes.filter { $0.projectId == projectId }
        let notesWithVideos = projectNotes.filter { note in
            note.attachments.contains { $0.attachmentKind == .video }
        }

        var selectedAttachmentNames = Set<String>()
        for note in projectNotes {
            let names = note.attachments
                .filter { $0.attachmentKind == .video }
                .map(\.fileName)
            selectedAttachmentNames.formUnion(names)
        }

        let videoDocuments = store.projectDocuments
            .filter { $0.projectId == projectId }
            .filter { document in
                let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return videoFileExtensions.contains(ext) && !isTicketCategory(document.category)
            }
        let videoDocumentIDs = Set(videoDocuments.map(\.id))
        let videoDocumentFileNames = Set(videoDocuments.map(\.fileName))

        let notesAfterCleanup = store.quickNotes.map { note -> QuickNote in
            guard note.projectId == projectId else { return note }
            var value = note
            value.attachments.removeAll { $0.attachmentKind == .video }
            return value
        }

        let extraMethodAttachments = store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: notesAfterCleanup,
            extraAttachments: extraMethodAttachments
        )
        let deletableAttachmentNames = selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) }

        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = videoDocumentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "随手记视频文件"), count: deletableAttachmentNames.count)
        summary.addFile(title: String(localized: "资料视频文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: String(localized: "随手记视频记录"), count: notesWithVideos.count)
        summary.addRecord(title: String(localized: "视频资料记录"), count: videoDocumentIDs.count)
        summary.addRecord(title: String(localized: "财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: String(localized: "仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(Set(deletableAttachmentNames).union(deletableDocumentNames))
        return summary
    }

    private func cadCleanupPreview(projectId: UUID) -> CleanupImpactSummary {
        let drawings = store.projectDrawings
            .filter { $0.projectId == projectId }
            .filter { drawing in
                let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return cadFileExtensions.contains(ext)
            }
        let drawingFileNames = Set(drawings.map(\.fileName))
        let remainingDrawingNamesAfterCleanup = Set(
            store.projectDrawings
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let shouldRemove = drawing.projectId == projectId && cadFileExtensions.contains(ext)
                    return !shouldRemove
                }
                .map(\.fileName)
        )
        let deletableDrawingNames = drawingFileNames.filter { !remainingDrawingNamesAfterCleanup.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "CAD 文件"), count: deletableDrawingNames.count)
        summary.addRecord(title: String(localized: "CAD 图纸记录"), count: drawings.count)
        summary.addSampleFileNames(deletableDrawingNames)
        return summary
    }

    private func ticketCleanupPreview(projectId: UUID) -> CleanupImpactSummary {
        let ticketDocuments = store.projectDocuments.filter { $0.projectId == projectId && isTicketCategory($0.category) }
        let removedDocumentIDs = Set(ticketDocuments.map(\.id))
        let documentFileNames = Set(ticketDocuments.map(\.fileName))
        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !removedDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = documentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "票据文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: String(localized: "票据资料记录"), count: removedDocumentIDs.count)
        summary.addRecord(title: String(localized: "财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: String(localized: "仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(deletableDocumentNames)
        return summary
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
        let purgedCount = StorageCleanupTrashStore.purgeExpiredBatches(now: Date())
        cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
        if purgedCount > 0 {
            StorageIssueLog.record(
                String(
                    format: String(localized: "清理回收站已自动永久删除 %lld 个过期批次。"),
                    Int64(purgedCount)
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
            cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
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
            cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
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
        case .cad:
            cleanupPlan.merge(cleanupProjectCAD(projectId))
        case .tickets:
            cleanupPlan.merge(cleanupProjectTickets(projectId))
        case .all:
            cleanupPlan.merge(cleanupProjectPhotos(projectId))
            cleanupPlan.merge(cleanupProjectVideos(projectId))
            cleanupPlan.merge(cleanupProjectCAD(projectId))
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
            cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
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
    private func cleanupProjectCAD(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectCADReferences(
                projectId: projectId,
                cadFileExtensions: cadFileExtensions
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
                let scopedSnapshot = StorageCleanupCenterView.makeProjectScopedSnapshot(from: baseSnapshot, projectId: projectId)
                estimates[projectId] = StorageCleanupCenterView.estimateBackupBytes(for: scopedSnapshot)
            }
            return estimates
        }

        projectBackupEstimateByID = await estimateTask.value
    }

    nonisolated private static func makeProjectScopedSnapshot(from baseSnapshot: BackupSnapshot, projectId: UUID) -> BackupSnapshot {
        var snapshot = baseSnapshot
        snapshot.materialItems = snapshot.materialItems.filter { $0.projectId == projectId }
        snapshot.quoteItems = snapshot.quoteItems.filter { $0.projectId == projectId }
        snapshot.laborRecords = snapshot.laborRecords.filter { $0.projectId == projectId }
        snapshot.projects = snapshot.projects.filter { $0.id == projectId }
        snapshot.dailyLogs = snapshot.dailyLogs.filter { $0.projectId == projectId }
        snapshot.historyRecords = []
        snapshot.progressTasks = snapshot.progressTasks.filter { $0.projectId == projectId }
        snapshot.lightingCircuitPlans = snapshot.lightingCircuitPlans.filter { $0.projectId == projectId }
        snapshot.siteTodos = snapshot.siteTodos.filter { $0.projectId == projectId }
        snapshot.projectDrawings = snapshot.projectDrawings.filter { $0.projectId == projectId }
        snapshot.projectContacts = snapshot.projectContacts.filter { $0.projectId == projectId }
        snapshot.projectFinancialRecords = snapshot.projectFinancialRecords.filter { $0.projectId == projectId }
        snapshot.projectDocuments = snapshot.projectDocuments.filter { $0.projectId == projectId }
        snapshot.quickNotes = snapshot.quickNotes.filter { $0.projectId == projectId }
        snapshot.projectWarehouseMovements = snapshot.projectWarehouseMovements.filter { $0.projectId == projectId }
        snapshot.templates = []
        snapshot.materialPriceEntries = []
        snapshot.materialSheetDrafts = snapshot.materialSheetDrafts.filter { $0.projectId == projectId }
        snapshot.supplierProfiles = []
        snapshot.constructionMethods = []
        snapshot.favoriteMaterialKeys = []
        snapshot.recentMaterialKeys = []
        snapshot.userMaterials = []
        snapshot.deletedUserMaterials = []
        snapshot.hiddenPresetKeys = []
        snapshot.photoFiles = []
        snapshot.drawingFiles = []
        snapshot.documentFiles = []
        snapshot.quickNoteAttachmentFiles = []
        return snapshot
    }

    nonisolated private static func estimateBackupBytes(for snapshot: BackupSnapshot) -> Int {
        let metadataBytes = (try? JSONEncoder().encode(snapshot).count) ?? 0

        let photoNames = Set(
            snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty }
        )
        let drawingNames = Set(snapshot.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let documentNames = Set(snapshot.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let attachmentNames = Set(snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty })

        let rawFilesBytes =
            sumFileBytes(fileNames: photoNames, size: PhotoStorage.fileSize(for:))
            + sumFileBytes(fileNames: drawingNames, size: DrawingStorage.fileSize(for:))
            + sumFileBytes(fileNames: documentNames, size: ProjectDocumentStorage.fileSize(for:))
            + sumFileBytes(fileNames: attachmentNames, size: QuickNoteAttachmentStorage.fileSize(for:))

        return metadataBytes + rawFilesBytes
    }

    nonisolated private static func sumFileBytes(fileNames: Set<String>, size: (String) -> Int) -> Int {
        fileNames.reduce(0) { partial, fileName in
            partial + size(fileName)
        }
    }
}

private struct StorageCleanupUndoSnapshot: Codable {
    let dailyLogs: [DailyLog]
    let siteTodos: [SiteTodo]
    let quickNotes: [QuickNote]
    let projectDrawings: [ProjectDrawing]
    let projectDocuments: [ProjectDocument]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectWarehouseMovements: [ProjectWarehouseMovement]

    @MainActor
    static func capture(from store: DataStore) -> StorageCleanupUndoSnapshot {
        StorageCleanupUndoSnapshot(
            dailyLogs: store.dailyLogs,
            siteTodos: store.siteTodos,
            quickNotes: store.quickNotes,
            projectDrawings: store.projectDrawings,
            projectDocuments: store.projectDocuments,
            projectFinancialRecords: store.projectFinancialRecords,
            projectWarehouseMovements: store.projectWarehouseMovements
        )
    }

    @MainActor
    func restore(into store: DataStore) {
        store.replaceDailyLogs(dailyLogs)
        store.replaceSiteTodos(siteTodos)
        store.replaceQuickNotes(quickNotes)
        store.replaceProjectDrawings(projectDrawings)
        store.replaceProjectDocuments(projectDocuments)
        store.replaceProjectFinancialRecords(projectFinancialRecords)
        store.replaceProjectWarehouseMovements(projectWarehouseMovements)
    }
}

private struct DeferredProjectFileCleanupPlan: Codable {
    var photoFileNames: Set<String> = []
    var quickNoteAttachmentFileNames: Set<String> = []
    var projectDocumentFileNames: Set<String> = []
    var drawingFileNames: Set<String> = []

    init(
        photoFileNames: Set<String> = [],
        quickNoteAttachmentFileNames: Set<String> = [],
        projectDocumentFileNames: Set<String> = [],
        drawingFileNames: Set<String> = []
    ) {
        self.photoFileNames = photoFileNames
        self.quickNoteAttachmentFileNames = quickNoteAttachmentFileNames
        self.projectDocumentFileNames = projectDocumentFileNames
        self.drawingFileNames = drawingFileNames
    }

    init(_ result: DataStoreProjectFileCleanupResult) {
        self.init(
            photoFileNames: result.photoFileNames,
            quickNoteAttachmentFileNames: result.quickNoteAttachmentFileNames,
            projectDocumentFileNames: result.projectDocumentFileNames,
            drawingFileNames: result.drawingFileNames
        )
    }

    var totalFileCount: Int {
        photoFileNames.count
            + quickNoteAttachmentFileNames.count
            + projectDocumentFileNames.count
            + drawingFileNames.count
    }

    mutating func merge(_ other: DeferredProjectFileCleanupPlan) {
        photoFileNames.formUnion(other.photoFileNames)
        quickNoteAttachmentFileNames.formUnion(other.quickNoteAttachmentFileNames)
        projectDocumentFileNames.formUnion(other.projectDocumentFileNames)
        drawingFileNames.formUnion(other.drawingFileNames)
    }
}

private struct StorageCleanupTrashBatch: Identifiable, Codable {
    let id: UUID
    let summary: String
    let createdAt: Date
    let expiresAt: Date
    let snapshot: StorageCleanupUndoSnapshot
    let files: [StorageCleanupTrashFile]

    var fileCount: Int { files.count }
}

private struct StorageCleanupTrashFile: Identifiable, Codable {
    let id: UUID
    let kind: StorageCleanupTrashFileKind
    let originalFileName: String
    let trashedFileName: String
}

private enum StorageCleanupTrashFileKind: String, Codable {
    case photoOriginal
    case photoThumbnail
    case drawing
    case quickNoteAttachment
    case projectDocument

    func originalURL(for fileName: String) -> URL {
        switch self {
        case .photoOriginal:
            return PhotoStorage.fileURL(for: fileName)
        case .photoThumbnail:
            return PhotoStorage.thumbnailStorageURL(for: fileName)
        case .drawing:
            return DrawingStorage.fileURL(for: fileName)
        case .quickNoteAttachment:
            return QuickNoteAttachmentStorage.fileURL(for: fileName)
        case .projectDocument:
            return ProjectDocumentStorage.fileURL(for: fileName)
        }
    }

    func invalidateCache(for fileName: String) {
        switch self {
        case .photoOriginal, .photoThumbnail:
            PhotoCache.shared.invalidate(fileName: fileName)
        case .drawing, .quickNoteAttachment, .projectDocument:
            break
        }
    }
}

private enum StorageCleanupTrashError: LocalizedError {
    case rootUnavailable
    case manifestWriteFailed
    case moveToTrashFailed(String)
    case restoreFailed(String)
    case permanentDeleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootUnavailable:
            return String(localized: "无法访问清理回收站目录。")
        case .manifestWriteFailed:
            return String(localized: "无法保存清理回收站清单。")
        case let .moveToTrashFailed(fileName):
            return String(format: String(localized: "无法移入清理回收站：%@"), fileName)
        case let .restoreFailed(fileName):
            return String(format: String(localized: "无法恢复清理回收站文件：%@"), fileName)
        case let .permanentDeleteFailed(fileName):
            return String(format: String(localized: "无法永久删除清理回收站文件：%@"), fileName)
        }
    }
}

private enum StorageCleanupTrashStore {
    private static let manifestFileName = "manifest.json"

    private static var rootURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageCleanupTrash", isDirectory: true)
    }

    private static var manifestURL: URL? {
        rootURL?.appendingPathComponent(manifestFileName)
    }

    static func loadBatches() -> [StorageCleanupTrashBatch] {
        guard let manifestURL else { return [] }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode([StorageCleanupTrashBatch].self, from: data)
                .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        } catch {
            StorageIssueLog.record(
                String(format: String(localized: "清理回收站清单读取失败：%@"), error.localizedDescription)
            )
            return []
        }
    }

    static func quarantine(
        plan: DeferredProjectFileCleanupPlan,
        snapshot: StorageCleanupUndoSnapshot,
        summary: String,
        retentionDays: Int
    ) throws -> StorageCleanupTrashBatch {
        guard let rootURL else { throw StorageCleanupTrashError.rootUnavailable }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let batchID = UUID()
        let createdAt = Date()
        let expiresAt = Calendar.current.date(
            byAdding: .day,
            value: max(retentionDays, 1),
            to: createdAt
        ) ?? createdAt.addingTimeInterval(TimeInterval(max(retentionDays, 1) * 24 * 60 * 60))

        var movedFiles: [StorageCleanupTrashFile] = []
        do {
            for source in trashSources(for: plan) {
                if let file = try moveToTrash(source, batchID: batchID) {
                    movedFiles.append(file)
                }
            }

            let batch = StorageCleanupTrashBatch(
                id: batchID,
                summary: summary,
                createdAt: createdAt,
                expiresAt: expiresAt,
                snapshot: snapshot,
                files: movedFiles
            )
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            batches.append(batch)
            try saveBatches(batches)
            return batch
        } catch {
            rollback(files: movedFiles, batchID: batchID)
            throw error
        }
    }

    static func restore(_ batch: StorageCleanupTrashBatch) throws {
        for file in batch.files {
            try restore(file: file, batchID: batch.id)
        }
        try removeBatchDirectory(batch.id)
        var batches = loadBatches()
        batches.removeAll { $0.id == batch.id }
        try saveBatches(batches)
    }

    static func permanentlyDelete(_ batch: StorageCleanupTrashBatch) throws {
        do {
            try removeBatchDirectory(batch.id)
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            try saveBatches(batches)
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batch.summary)
        }
    }

    static func purgeExpiredBatches(now: Date) -> Int {
        let batches = loadBatches()
        let expired = batches.filter { $0.expiresAt <= now }
        guard !expired.isEmpty else { return 0 }

        for batch in expired {
            try? removeBatchDirectory(batch.id)
        }
        let active = batches.filter { $0.expiresAt > now }
        do {
            try saveBatches(active)
        } catch {
            StorageIssueLog.record(
                String(format: String(localized: "清理回收站过期清单更新失败：%@"), error.localizedDescription)
            )
        }
        return expired.count
    }

    private static func saveBatches(_ batches: [StorageCleanupTrashBatch]) throws {
        guard let rootURL, let manifestURL else { throw StorageCleanupTrashError.rootUnavailable }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt })
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            throw StorageCleanupTrashError.manifestWriteFailed
        }
    }

    private static func trashSources(for plan: DeferredProjectFileCleanupPlan) -> [StorageCleanupTrashSource] {
        var sources: [StorageCleanupTrashSource] = []
        sources += plan.photoFileNames.sorted().flatMap { fileName in
            [
                StorageCleanupTrashSource(kind: .photoOriginal, fileName: fileName),
                StorageCleanupTrashSource(kind: .photoThumbnail, fileName: fileName)
            ]
        }
        sources += plan.quickNoteAttachmentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .quickNoteAttachment, fileName: $0)
        }
        sources += plan.projectDocumentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .projectDocument, fileName: $0)
        }
        sources += plan.drawingFileNames.sorted().flatMap { fileName in
            ([fileName] + DrawingStorage.sidecarFileNames(for: fileName)).map {
                StorageCleanupTrashSource(kind: .drawing, fileName: $0)
            }
        }
        return sources
    }

    private static func moveToTrash(
        _ source: StorageCleanupTrashSource,
        batchID: UUID
    ) throws -> StorageCleanupTrashFile? {
        let sourceURL = source.kind.originalURL(for: source.fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }

        guard let destinationURL = trashURL(
            batchID: batchID,
            kind: source.kind,
            trashedFileName: "\(UUID().uuidString)-\(source.fileName)"
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            source.kind.invalidateCache(for: source.fileName)
            return StorageCleanupTrashFile(
                id: UUID(),
                kind: source.kind,
                originalFileName: source.fileName,
                trashedFileName: destinationURL.lastPathComponent
            )
        } catch {
            throw StorageCleanupTrashError.moveToTrashFailed(source.fileName)
        }
    }

    private static func restore(file: StorageCleanupTrashFile, batchID: UUID) throws {
        guard let trashedURL = trashURL(
            batchID: batchID,
            kind: file.kind,
            trashedFileName: file.trashedFileName
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        let originalURL = file.kind.originalURL(for: file.originalFileName)
        let manager = FileManager.default
        guard manager.fileExists(atPath: trashedURL.path) else {
            if manager.fileExists(atPath: originalURL.path) {
                file.kind.invalidateCache(for: file.originalFileName)
                return
            }
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }

        do {
            try manager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: originalURL.path) {
                _ = try FileOps.removeIfExists(
                    at: trashedURL,
                    context: .init(
                        event: "storage_cleanup.trash_restore_cleanup",
                        category: .fileStorage,
                        source: "StorageCleanupTrashStore.restore"
                    )
                )
            } else {
                try manager.moveItem(at: trashedURL, to: originalURL)
            }
            file.kind.invalidateCache(for: file.originalFileName)
        } catch {
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }
    }

    private static func rollback(files: [StorageCleanupTrashFile], batchID: UUID) {
        for file in files.reversed() {
            try? restore(file: file, batchID: batchID)
        }
        try? removeBatchDirectory(batchID)
    }

    private static func trashURL(
        batchID: UUID,
        kind: StorageCleanupTrashFileKind,
        trashedFileName: String
    ) -> URL? {
        rootURL?
            .appendingPathComponent(batchID.uuidString, isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(trashedFileName)
    }

    private static func removeBatchDirectory(_ batchID: UUID) throws {
        guard let batchURL = rootURL?.appendingPathComponent(batchID.uuidString, isDirectory: true) else {
            throw StorageCleanupTrashError.rootUnavailable
        }
        guard FileManager.default.fileExists(atPath: batchURL.path) else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: batchURL,
                context: .init(
                    event: "storage_cleanup.trash_batch_remove",
                    category: .fileStorage,
                    source: "StorageCleanupTrashStore.removeBatchDirectory"
                )
            )
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batchID.uuidString)
        }
    }
}

private struct StorageCleanupTrashSource {
    let kind: StorageCleanupTrashFileKind
    let fileName: String
}

private enum StorageCleanupTrashRetentionOption: Int, CaseIterable, Identifiable {
    case days3 = 3
    case days7 = 7
    case days14 = 14
    case days30 = 30

    static let defaultDays = Self.days7.rawValue

    var id: Int { rawValue }
    var days: Int { rawValue }
    var displayName: String {
        String(format: String(localized: "%lld 天"), Int64(rawValue))
    }

    static func normalizedDays(_ days: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - days) < abs(rhs.rawValue - days)
        }?.rawValue ?? defaultDays
    }
}

private enum StorageCleanupLargeFileThresholdOption: Int, CaseIterable, Identifiable {
    case mb5 = 5
    case mb20 = 20
    case mb50 = 50
    case mb100 = 100

    static let defaultMegabytes = Self.mb5.rawValue

    var id: Int { rawValue }
    var megabytes: Int { rawValue }
    var bytes: Int { rawValue * 1024 * 1024 }
    var displayName: String { QuickNoteAttachmentStorage.formattedFileSize(bytes) }

    static func bytes(for megabytes: Int) -> Int {
        normalizedMegabytes(megabytes) * 1024 * 1024
    }

    static func normalizedMegabytes(_ megabytes: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - megabytes) < abs(rhs.rawValue - megabytes)
        }?.rawValue ?? defaultMegabytes
    }
}

private enum StorageCleanupLargeFileRuleSuggestion {
    case photo
    case video
    case ticket

    var bytes: Int {
        switch self {
        case .photo:
            return 5 * 1024 * 1024
        case .video:
            return 50 * 1024 * 1024
        case .ticket:
            return 20 * 1024 * 1024
        }
    }
}

private struct StorageCategorySummary: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    let bytes: Int
    let count: Int

    var formattedBytes: String {
        QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }
}

private struct StorageLargeFileItem: Identifiable {
    let id: String
    let category: StorageFileCategory
    let title: String
    let detail: String
    let projectId: UUID?
    let projectName: String?
    let bytes: Int

    init(
        id: String,
        category: StorageFileCategory,
        title: String,
        detail: String,
        projectId: UUID? = nil,
        projectName: String? = nil,
        bytes: Int
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.projectId = projectId
        self.projectName = projectName
        self.bytes = bytes
    }

    var formattedBytes: String {
        QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }
}

private enum StorageFileCategory {
    case photo
    case video
    case cad
    case ticket
    case backup
    case history

    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "照片")
        case .video:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD")
        case .ticket:
            return String(localized: "票据")
        case .backup:
            return String(localized: "备份")
        case .history:
            return String(localized: "历史计算")
        }
    }

    var icon: String {
        switch self {
        case .photo:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .cad:
            return "compass.drawing"
        case .ticket:
            return "doc.text.fill"
        case .backup:
            return "externaldrive.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .photo:
            return .appWarning
        case .video:
            return .appPhoto
        case .cad:
            return .appDoc
        case .ticket:
            return .appRisk
        case .backup:
            return .appPrimaryAction
        case .history:
            return .appSuccess
        }
    }
}

private struct ProjectStorageUsage: Identifiable {
    let projectId: UUID
    let projectName: String
    let photoBytes: Int
    let videoBytes: Int
    let cadBytes: Int
    let ticketBytes: Int
    let backupEstimatedBytes: Int?

    var id: UUID { projectId }
    var totalBytes: Int { photoBytes + videoBytes + cadBytes + ticketBytes }
    var formattedTotalBytes: String { QuickNoteAttachmentStorage.formattedFileSize(totalBytes) }
    var formattedBackupEstimatedBytes: String {
        guard let backupEstimatedBytes else { return String(localized: "计算中…") }
        return QuickNoteAttachmentStorage.formattedFileSize(backupEstimatedBytes)
    }
}

private struct CleanupImpactSummary {
    struct Item {
        let title: String
        let count: Int
    }

    private var fileCountMap: [String: Int] = [:]
    private var recordCountMap: [String: Int] = [:]
    private var sampleFileNameSet: Set<String> = []

    mutating func addFile(title: String, count: Int) {
        guard count > 0 else { return }
        fileCountMap[title, default: 0] += count
    }

    mutating func addRecord(title: String, count: Int) {
        guard count > 0 else { return }
        recordCountMap[title, default: 0] += count
    }

    mutating func addSampleFileNames<S: Sequence>(_ names: S) where S.Element == String {
        for name in names where !name.isEmpty {
            sampleFileNameSet.insert(name)
        }
    }

    mutating func merge(_ other: CleanupImpactSummary) {
        for (title, count) in other.fileCountMap {
            fileCountMap[title, default: 0] += count
        }
        for (title, count) in other.recordCountMap {
            recordCountMap[title, default: 0] += count
        }
        sampleFileNameSet.formUnion(other.sampleFileNameSet)
    }

    var totalFileCount: Int {
        fileCountMap.values.reduce(0, +)
    }

    var fileItems: [Item] {
        fileCountMap.map { Item(title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    var recordItems: [Item] {
        recordCountMap.map { Item(title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    var sampleFileNames: [String] {
        sampleFileNameSet.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}

private enum ProjectStorageCleanupCategory: String, Identifiable {
    case photos
    case videos
    case cad
    case tickets
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photos:
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD 图纸")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "全部可清理文件")
        }
    }

    var resultTitle: String {
        switch self {
        case .photos:
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD 图纸")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "项目文件")
        }
    }

    var icon: String {
        switch self {
        case .photos:
            return "photo.fill"
        case .videos:
            return "video.fill"
        case .cad:
            return "compass.drawing"
        case .tickets:
            return "doc.text.fill"
        case .all:
            return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .photos:
            return .appWarning
        case .videos:
            return .appPhoto
        case .cad:
            return .appDoc
        case .tickets:
            return .appRisk
        case .all:
            return .red
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .all:
            return String(localized: "清理全部")
        default:
            return String(format: String(localized: "清理%@"), displayName)
        }
    }

    func confirmationMessage(projectName: String) -> String {
        switch self {
        case .photos:
            return String(format: String(localized: "将清理 %@ 日志和待办整改中的照片原文件，并断开照片关联。文本记录会保留。"), projectName)
        case .videos:
            return String(format: String(localized: "将清理 %@ 随手记视频和资料中的视频原文件，并断开视频关联。"), projectName)
        case .cad:
            return String(format: String(localized: "将清理 %@ 的 CAD 图纸原文件和图纸索引。"), projectName)
        case .tickets:
            return String(format: String(localized: "将清理 %@ 的发票、收据和付款申请资料原文件，并断开财务/仓库关联。"), projectName)
        case .all:
            return String(format: String(localized: "将清理 %@ 的照片、视频、CAD 图纸和票据资料原文件，保留其他文本记录。"), projectName)
        }
    }
}

private struct ProjectStorageCleanupDetailView: View {
    let usage: ProjectStorageUsage
    let onCleanup: (ProjectStorageCleanupCategory) -> Void

    var body: some View {
        List {
            Section(String(localized: "占用汇总")) {
                usageRow(title: String(localized: "照片"), icon: "photo.fill", tint: .appWarning, bytes: usage.photoBytes)
                usageRow(title: String(localized: "视频"), icon: "video.fill", tint: .appPhoto, bytes: usage.videoBytes)
                usageRow(title: String(localized: "CAD 图纸"), icon: "compass.drawing", tint: .appDoc, bytes: usage.cadBytes)
                usageRow(title: String(localized: "票据资料"), icon: "doc.text.fill", tint: .appRisk, bytes: usage.ticketBytes)
                usageRow(title: String(localized: "备份估算"), icon: "externaldrive.fill", tint: .appPrimaryAction, bytesText: usage.formattedBackupEstimatedBytes)
            }

            Section {
                HStack {
                    Text(String(localized: "项目总占用"))
                    Spacer()
                    Text(usage.formattedTotalBytes)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section {
                cleanupButton(.photos, bytes: usage.photoBytes)
                cleanupButton(.videos, bytes: usage.videoBytes)
                cleanupButton(.cad, bytes: usage.cadBytes)
                cleanupButton(.tickets, bytes: usage.ticketBytes)
            } header: {
                Text(String(localized: "按类型清理"))
            } footer: {
                Text(String(localized: "分项清理只处理对应文件类型，项目文本、金额、日志正文不会删除。"))
            }

            Section {
                Button(role: .destructive) {
                    onCleanup(.all)
                } label: {
                    Label(String(localized: "清理该项目全部可清理文件"), systemImage: "trash")
                }
                .disabled(usage.totalBytes == 0)
            } footer: {
                Text(String(localized: "备份是全局快照，不会按单个项目直接删除；如需释放备份空间，请回到“数据管理 → 备份”处理。"))
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
                Text(String(format: String(localized: "清理%@"), category.displayName))
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

private struct StorageOptionalInlineTitleModifier: ViewModifier {
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
