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
