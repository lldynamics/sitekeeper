import SwiftUI

struct StorageCleanupCenterView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @State private var cloudBackups: [CloudBackupFile] = []
    @State private var cloudBackupError: String?
    @State private var isRefreshingCloudBackups = false
    @State private var projectBackupEstimateByID: [UUID: Int] = [:]
    @State private var isRefreshingProjectBackupEstimates = false
    @State private var pendingCleanupProject: ProjectStorageUsage?
    @State private var pendingCleanupCategory: ProjectStorageCleanupCategory = .all
    @State private var showCleanupProjectAlert = false
    @State private var cleanupStatusMessage = ""

    private let showsNavigationTitle: Bool
    private let largeFileThresholdBytes = 5 * 1024 * 1024
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
                    Text("云备份读取失败：\(cloudBackupError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("空间汇总") {
                ForEach(categorySummaries) { summary in
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: summary.icon)
                            .foregroundStyle(summary.tint)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                            Text("\(summary.count) 项")
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
                HStack {
                    Label("大文件阈值", systemImage: "externaldrive.fill.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(QuickNoteAttachmentStorage.formattedFileSize(largeFileThresholdBytes))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("大文件列表 (\(largeFileItems.count))")
            } footer: {
                Text("展示照片、视频、CAD、备份和历史计算中的高占用项。")
            }

            if largeFileItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        "暂无大文件",
                        systemImage: "checkmark.seal",
                        description: Text("当前各类文件都低于阈值。")
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

            Section("按项目清理") {
                if projectUsages.isEmpty {
                    Text("暂无可清理项目文件。")
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
                                    Text("照片 \(QuickNoteAttachmentStorage.formattedFileSize(usage.photoBytes))")
                                    Text("视频 \(QuickNoteAttachmentStorage.formattedFileSize(usage.videoBytes))")
                                    Text("CAD \(QuickNoteAttachmentStorage.formattedFileSize(usage.cadBytes))")
                                    Text("票据 \(QuickNoteAttachmentStorage.formattedFileSize(usage.ticketBytes))")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                Text("备份估算 \(usage.formattedBackupEstimatedBytes)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .modifier(StorageOptionalInlineTitleModifier(isEnabled: showsNavigationTitle, title: "存储清理中心"))
        .task {
            await refreshCloudBackups()
            await refreshProjectBackupEstimates()
        }
        .task(id: store.dataVersion) {
            await refreshProjectBackupEstimates()
        }
        .alert(
            "清理项目文件？",
            isPresented: $showCleanupProjectAlert,
            presenting: pendingCleanupProject
        ) { usage in
            Button(pendingCleanupCategory.confirmationButtonTitle, role: .destructive) {
                cleanupProjectFiles(usage, category: pendingCleanupCategory)
            }
            Button("取消", role: .cancel) {
                pendingCleanupProject = nil
            }
        } message: { usage in
            Text(cleanupConfirmationMessage(for: usage, category: pendingCleanupCategory))
        }
    }

    private var categorySummaries: [StorageCategorySummary] {
        [
            StorageCategorySummary(
                title: "照片",
                icon: "photo.fill",
                tint: .appWarning,
                bytes: photoEntries.reduce(0) { $0 + $1.bytes },
                count: photoEntries.count
            ),
            StorageCategorySummary(
                title: "视频",
                icon: "video.fill",
                tint: .appPhoto,
                bytes: videoEntries.reduce(0) { $0 + $1.bytes },
                count: videoEntries.count
            ),
            StorageCategorySummary(
                title: "CAD 图纸",
                icon: "compass.drawing",
                tint: .appDoc,
                bytes: cadEntries.reduce(0) { $0 + $1.bytes },
                count: cadEntries.count
            ),
            StorageCategorySummary(
                title: "票据资料",
                icon: "doc.text.fill",
                tint: .appRisk,
                bytes: ticketEntries.reduce(0) { $0 + $1.bytes },
                count: ticketEntries.count
            ),
            StorageCategorySummary(
                title: "备份（iCloud）",
                icon: "icloud.and.arrow.up.fill",
                tint: .appPrimaryAction,
                bytes: cloudBackups.reduce(0) { $0 + $1.byteSize },
                count: cloudBackups.count
            ),
            StorageCategorySummary(
                title: "历史计算",
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
                    title: "历史计算记录",
                    detail: "\(store.historyRecords.count) 条",
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
                projectName: project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名项目" : project.name,
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
                (todo.rectificationBeforePhotoFileName, "整改前"),
                (todo.rectificationAfterPhotoFileName, "整改后")
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
            return trimmed.isEmpty ? "未命名项目" : trimmed
        }
        return "未知项目"
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
            StorageIssueLog.record("存储清理中心读取云备份失败：\(errorMessage)")
        } else {
            cloudBackups = backups
            cloudBackupError = nil
        }
    }

    private func cleanupConfirmationMessage(for usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) -> String {
        let preview = cleanupPreview(for: usage.projectId, category: category)
        var lines: [String] = [category.confirmationMessage(projectName: usage.projectName)]

        if preview.totalFileCount > 0 {
            lines.append("预计删除文件 \(preview.totalFileCount) 个：")
            for item in preview.fileItems {
                lines.append("- \(item.title) \(item.count) 个")
            }
        } else {
            lines.append("预计删除文件 0 个。")
        }

        if !preview.recordItems.isEmpty {
            lines.append("预计影响记录：")
            for item in preview.recordItems {
                lines.append("- \(item.title) \(item.count) 条")
            }
        }

        if !preview.sampleFileNames.isEmpty {
            lines.append("示例文件：\(preview.sampleFileNames.prefix(5).joined(separator: "、"))")
        }

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
        summary.addFile(title: "照片原文件", count: deletablePhotoNames.count)
        summary.addRecord(title: "日志照片记录", count: logsWithPhotos.count)
        summary.addRecord(title: "待办整改照片", count: todosWithPhotos.count)
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
        summary.addFile(title: "随手记视频文件", count: deletableAttachmentNames.count)
        summary.addFile(title: "资料视频文件", count: deletableDocumentNames.count)
        summary.addRecord(title: "随手记视频记录", count: notesWithVideos.count)
        summary.addRecord(title: "视频资料记录", count: videoDocumentIDs.count)
        summary.addRecord(title: "财务关联变更", count: financialLinkedCount)
        summary.addRecord(title: "仓库关联变更", count: warehouseLinkedCount)
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
        summary.addFile(title: "CAD 文件", count: deletableDrawingNames.count)
        summary.addRecord(title: "CAD 图纸记录", count: drawings.count)
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
        summary.addFile(title: "票据文件", count: deletableDocumentNames.count)
        summary.addRecord(title: "票据资料记录", count: removedDocumentIDs.count)
        summary.addRecord(title: "财务关联变更", count: financialLinkedCount)
        summary.addRecord(title: "仓库关联变更", count: warehouseLinkedCount)
        summary.addSampleFileNames(deletableDocumentNames)
        return summary
    }

    private func backupReminderMessage() -> String {
        guard let latestDate = latestBackupDateForReminder else {
            return "最近备份：未检测到本机或云备份，建议先执行备份后再清理。"
        }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latestDate)
        let today = calendar.startOfDay(for: Date())
        let daysSinceBackup = max(calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0, 0)
        let formattedDate = Formatters.dateTime.string(from: latestDate)
        let reminderDays = max(1, backupHealthReminderDays)

        if daysSinceBackup >= reminderDays {
            return "最近备份：\(formattedDate)（\(daysSinceBackup) 天前），建议先备份后再清理。"
        }

        return "最近备份：\(formattedDate)。"
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

    private func cleanupProjectFiles(_ usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) {
        let projectId = usage.projectId
        let auditDetail = "\(usage.projectName) · \(category.displayName)"
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: String(localized: "按项目清理"),
            detail: auditDetail,
            source: "StorageCleanupCenterView"
        )
        let deletedCount: Int

        switch category {
        case .photos:
            deletedCount = cleanupProjectPhotos(projectId)
        case .videos:
            deletedCount = cleanupProjectVideos(projectId)
        case .cad:
            deletedCount = cleanupProjectCAD(projectId)
        case .tickets:
            deletedCount = cleanupProjectTickets(projectId)
        case .all:
            deletedCount =
                cleanupProjectPhotos(projectId)
                + cleanupProjectVideos(projectId)
                + cleanupProjectCAD(projectId)
                + cleanupProjectTickets(projectId)
        }

        cleanupStatusMessage = "已清理 \(usage.projectName) 的\(category.resultTitle)：\(deletedCount) 个文件。"
        store.scheduleSave()
        pendingCleanupProject = nil
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .succeeded,
            summary: String(localized: "按项目清理"),
            detail: "\(auditDetail) · deleted=\(deletedCount)",
            source: "StorageCleanupCenterView"
        )
    }

    @discardableResult
    private func cleanupProjectPhotos(_ projectId: UUID) -> Int {
        let logIndexes = store.dailyLogs.indices.filter { store.dailyLogs[$0].projectId == projectId }
        let todoIndexes = store.siteTodos.indices.filter { store.siteTodos[$0].projectId == projectId }

        var selectedPhotoNames = Set<String>()
        for index in logIndexes {
            selectedPhotoNames.formUnion(store.dailyLogs[index].allPhotoFileNames)
            store.dailyLogs[index].photoFileName = nil
            store.dailyLogs[index].photos = []
        }
        for index in todoIndexes {
            if let before = store.siteTodos[index].rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = store.siteTodos[index].rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
            store.siteTodos[index].rectificationBeforePhotoFileName = nil
            store.siteTodos[index].rectificationAfterPhotoFileName = nil
        }

        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: store.dailyLogs, todos: store.siteTodos)
        let deletablePhotoNames = selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }
        PhotoStorage.delete(fileNames: Array(deletablePhotoNames))
        return deletablePhotoNames.count
    }

    @discardableResult
    private func cleanupProjectVideos(_ projectId: UUID) -> Int {
        let noteIndexes = store.quickNotes.indices.filter { store.quickNotes[$0].projectId == projectId }
        var selectedAttachmentNames = Set<String>()
        for index in noteIndexes {
            let videos = store.quickNotes[index].attachments.filter { $0.attachmentKind == .video }
            selectedAttachmentNames.formUnion(videos.map(\.fileName))
            store.quickNotes[index].attachments.removeAll { $0.attachmentKind == .video }
        }

        let videoDocumentIDs = Set(
            store.projectDocuments
                .filter { $0.projectId == projectId }
                .filter { document in
                    let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return videoFileExtensions.contains(ext) && !isTicketCategory(document.category)
                }
                .map(\.id)
        )
        let videoDocumentFileNames = Set(
            store.projectDocuments
                .filter { videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        store.projectDocuments.removeAll { videoDocumentIDs.contains($0.id) }
        unlinkDocuments(ids: videoDocumentIDs)

        let extraMethodAttachments = store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: store.quickNotes,
            extraAttachments: extraMethodAttachments
        )
        let deletableAttachmentNames = selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) }
        QuickNoteAttachmentStorage.delete(fileNames: Array(deletableAttachmentNames))

        let remainingDocumentNames = Set(store.projectDocuments.map(\.fileName))
        let deletableDocumentNames = videoDocumentFileNames.filter { !remainingDocumentNames.contains($0) }
        ProjectDocumentStorage.delete(fileNames: Array(deletableDocumentNames))

        return deletableAttachmentNames.count + deletableDocumentNames.count
    }

    @discardableResult
    private func cleanupProjectCAD(_ projectId: UUID) -> Int {
        let drawingFileNames = Set(
            store.projectDrawings
                .filter { $0.projectId == projectId }
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return cadFileExtensions.contains(ext)
                }
                .map(\.fileName)
        )
        store.projectDrawings.removeAll { drawing in
            drawing.projectId == projectId
                && cadFileExtensions.contains(drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        let remainingDrawingNames = Set(store.projectDrawings.map(\.fileName))
        let deletableDrawingNames = drawingFileNames.filter { !remainingDrawingNames.contains($0) }
        DrawingStorage.delete(fileNames: Array(deletableDrawingNames))
        return deletableDrawingNames.count
    }

    @discardableResult
    private func cleanupProjectTickets(_ projectId: UUID) -> Int {
        let removedDocumentIDs = Set(
            store.projectDocuments
                .filter { $0.projectId == projectId && isTicketCategory($0.category) }
                .map(\.id)
        )
        let documentFileNames = Set(
            store.projectDocuments
                .filter { removedDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        store.projectDocuments.removeAll { removedDocumentIDs.contains($0.id) }
        unlinkDocuments(ids: removedDocumentIDs)
        let remainingDocumentNames = Set(store.projectDocuments.map(\.fileName))
        let deletableDocumentNames = documentFileNames.filter { !remainingDocumentNames.contains($0) }
        ProjectDocumentStorage.delete(fileNames: Array(deletableDocumentNames))
        return deletableDocumentNames.count
    }

    private func unlinkDocuments(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for index in store.projectFinancialRecords.indices {
            store.projectFinancialRecords[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        for index in store.projectWarehouseMovements.indices {
            store.projectWarehouseMovements[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
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
            return "照片"
        case .video:
            return "视频"
        case .cad:
            return "CAD"
        case .ticket:
            return "票据"
        case .backup:
            return "备份"
        case .history:
            return "历史计算"
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
        guard let backupEstimatedBytes else { return "计算中…" }
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
            return "照片"
        case .videos:
            return "视频"
        case .cad:
            return "CAD 图纸"
        case .tickets:
            return "票据资料"
        case .all:
            return "全部可清理文件"
        }
    }

    var resultTitle: String {
        switch self {
        case .photos:
            return "照片"
        case .videos:
            return "视频"
        case .cad:
            return "CAD 图纸"
        case .tickets:
            return "票据资料"
        case .all:
            return "项目文件"
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
            return "清理全部"
        default:
            return "清理\(displayName)"
        }
    }

    func confirmationMessage(projectName: String) -> String {
        switch self {
        case .photos:
            return "将清理 \(projectName) 日志和待办整改中的照片原文件，并断开照片关联。文本记录会保留。"
        case .videos:
            return "将清理 \(projectName) 随手记视频和资料中的视频原文件，并断开视频关联。"
        case .cad:
            return "将清理 \(projectName) 的 CAD 图纸原文件和图纸索引。"
        case .tickets:
            return "将清理 \(projectName) 的发票、收据和付款申请资料原文件，并断开财务/仓库关联。"
        case .all:
            return "将清理 \(projectName) 的照片、视频、CAD 图纸和票据资料原文件，保留其他文本记录。"
        }
    }
}

private struct ProjectStorageCleanupDetailView: View {
    let usage: ProjectStorageUsage
    let onCleanup: (ProjectStorageCleanupCategory) -> Void

    var body: some View {
        List {
            Section("占用汇总") {
                usageRow(title: "照片", icon: "photo.fill", tint: .appWarning, bytes: usage.photoBytes)
                usageRow(title: "视频", icon: "video.fill", tint: .appPhoto, bytes: usage.videoBytes)
                usageRow(title: "CAD 图纸", icon: "compass.drawing", tint: .appDoc, bytes: usage.cadBytes)
                usageRow(title: "票据资料", icon: "doc.text.fill", tint: .appRisk, bytes: usage.ticketBytes)
                usageRow(title: "备份估算", icon: "externaldrive.fill", tint: .appPrimaryAction, bytesText: usage.formattedBackupEstimatedBytes)
            }

            Section {
                HStack {
                    Text("项目总占用")
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
                Text("按类型清理")
            } footer: {
                Text("分项清理只处理对应文件类型，项目文本、金额、日志正文不会删除。")
            }

            Section {
                Button(role: .destructive) {
                    onCleanup(.all)
                } label: {
                    Label("清理该项目全部可清理文件", systemImage: "trash")
                }
                .disabled(usage.totalBytes == 0)
            } footer: {
                Text("备份是全局快照，不会按单个项目直接删除；如需释放备份空间，请回到“数据管理 → 备份”处理。")
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
                Text("清理\(category.displayName)")
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
