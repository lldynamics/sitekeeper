import SwiftUI
import UniformTypeIdentifiers

struct DataHealthView: View {
    @Environment(DataStore.self) private var store
    @State private var showReferenceFixConfirm = false
    @State private var showOrphanFileCleanupConfirm = false
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var storageIssuesVersion = UUID()
    private let showsNavigationTitle: Bool

    init(showsNavigationTitle: Bool = true) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    private func l(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: key, comment: "")
    }

    private func lf(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    private var projectIdSet: Set<UUID> {
        Set(store.projects.map(\.id))
    }

    private var missingPhotoFiles: [String] {
        let logPhotoNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotoNames = store.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }.compactMap { $0 }
        let names = Set(logPhotoNames + todoPhotoNames)
        return names.filter { !PhotoStorage.exists(fileName: $0) }.sorted()
    }

    private var missingDocumentFiles: [String] {
        store.projectDocuments
            .filter { !ProjectDocumentStorage.exists(fileName: $0.fileName) }
            .map(\.fileName)
            .sorted()
    }

    private var missingQuickNoteAttachmentFiles: [String] {
        let allAttachments = store.quickNotes.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        return allAttachments
            .filter { !QuickNoteAttachmentStorage.exists(fileName: $0.fileName) }
            .map(\.fileName)
            .sorted()
    }

    private var orphanQuickNoteAttachmentFiles: [String] {
        QuickNoteAttachmentStorage.orphanFileNames(
            for: store.quickNotes,
            extraAttachments: store.constructionMethods.flatMap(\.attachments) + store.constructionMethods.flatMap(\.tutorialAttachments)
        )
    }

    private var orphanPhotoFiles: [String] {
        PhotoStorage.orphanFileNames(logs: store.dailyLogs, todos: store.siteTodos)
    }

    private var orphanDrawingFiles: [String] {
        DrawingStorage.orphanFileNames(for: store.projectDrawings)
    }

    private var orphanDocumentFiles: [String] {
        ProjectDocumentStorage.orphanFileNames(for: store.projectDocuments)
    }

    private var orphanAttachmentMappings: [String] {
        orphanAttachmentMappingIssues.map(\.exportText)
    }

    private var orphanWarehouseAttachmentMappings: [String] {
        orphanWarehouseAttachmentMappingIssues.map(\.exportText)
    }

    private var danglingDocumentLinks: [String] {
        danglingDocumentLinkIssues.map(\.exportText)
    }

    private var autoFixableInvalidProjectRefs: [String] {
        autoFixableInvalidProjectRefIssues.map(\.exportText)
    }

    private var manualInvalidProjectRefs: [String] {
        manualInvalidProjectRefIssues.map(\.exportText)
    }

    private var invalidProjectRefs: [String] {
        autoFixableInvalidProjectRefs + manualInvalidProjectRefs
    }

    private var storageIssues: [String] {
        _ = storageIssuesVersion
        return StorageIssueLog.entries()
    }

    private var widgetHealth: WidgetDataHealthSnapshot {
        guard let defaults = UserDefaults(suiteName: "group.com.chengjinfang.sitekeeper") else {
            return WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
        }
        let data: WidgetExportData
        if let raw = defaults.data(forKey: "widget_data"),
           let decoded = try? JSONDecoder().decode(WidgetExportData.self, from: raw) {
            data = decoded
        } else {
            data = WidgetExportData(projects: [], pendingTodos: 0, materialStockCount: 0, lowStockCount: 0)
        }
        let timestamp = defaults.double(forKey: "widget_data_updated_at")
        return WidgetDataHealthSnapshot(
            appGroupReadable: true,
            lastUpdatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil,
            projectCount: data.projects.count,
            pendingTodos: data.pendingTodos
        )
    }

    private var photoThumbnailCacheBytes: Int {
        PhotoStorage.thumbnailCacheUsageBytes()
    }

    private var quickNoteThumbnailCacheBytes: Int {
        QuickNoteAttachmentStorage.thumbnailCacheUsageBytes()
    }

    private var mediaThumbnailCacheBytes: Int {
        photoThumbnailCacheBytes + quickNoteThumbnailCacheBytes
    }

    private var referencedPhotoFileNames: Set<String> {
        let logNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoNames = store.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }
            .compactMap { $0 }
        return Set(logNames + todoNames)
    }

    private var photoStorageBytes: Int {
        referencedPhotoFileNames.reduce(0) { total, fileName in
            total + PhotoStorage.fileSize(for: fileName)
        }
    }

    private var projectDocumentBytes: Int {
        Set(store.projectDocuments.map(\.fileName)).reduce(0) { total, fileName in
            total + ProjectDocumentStorage.fileSize(for: fileName)
        }
    }

    private var projectDrawingBytes: Int {
        Set(store.projectDrawings.map(\.fileName)).reduce(0) { total, fileName in
            total + DrawingStorage.fileSize(for: fileName)
        }
    }

    private var quickNoteAttachmentBytes: Int {
        let attachments = store.quickNotes.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let names = Set(attachments.map(\.fileName))
        return names.reduce(0) { total, fileName in
            total + QuickNoteAttachmentStorage.fileSize(for: fileName)
        }
    }

    private var projectAssetBytes: Int {
        projectDocumentBytes + projectDrawingBytes + quickNoteAttachmentBytes
    }

    private var cloudBackupBytes: Int {
        (try? CloudBackupService.listBackups().reduce(0) { $0 + $1.byteSize }) ?? 0
    }

    private var historyRecordBytes: Int {
        (try? JSONEncoder().encode(store.historyRecords).count) ?? 0
    }

    private var totalStorageBytes: Int {
        photoStorageBytes
            + projectAssetBytes
            + mediaThumbnailCacheBytes
            + cloudBackupBytes
            + historyRecordBytes
    }

    private var missingPhotoFileIssues: [DataHealthIssue] {
        var issues: [DataHealthIssue] = []
        for log in store.dailyLogs {
            if let fileName = log.photoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                issues.append(
                    DataHealthIssue(
                        id: "missing-log-photo-\(log.id.uuidString)-legacy-\(fileName)",
                        title: l("日志照片缺失"),
                        detail: issueDetail([projectName(log.projectId), log.date, fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开日志"),
                        route: .dailyLog(projectId: log.projectId, logId: log.id)
                    )
                )
            }
            for photo in log.photos where !PhotoStorage.exists(fileName: photo.fileName) {
                issues.append(
                    DataHealthIssue(
                        id: "missing-log-photo-\(log.id.uuidString)-\(photo.id.uuidString)",
                        title: l("日志照片缺失"),
                        detail: issueDetail([projectName(log.projectId), log.date, photo.tag.displayName, photo.fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开日志"),
                        route: .dailyLog(projectId: log.projectId, logId: log.id)
                    )
                )
            }
        }
        for todo in store.siteTodos {
            if let fileName = todo.rectificationBeforePhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                issues.append(
                    DataHealthIssue(
                        id: "missing-todo-photo-\(todo.id.uuidString)-before-\(fileName)",
                        title: l("待办整改前照片缺失"),
                        detail: issueDetail([projectName(todo.projectId), todo.title, l("整改前"), fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开待办"),
                        route: .siteTodo(projectId: todo.projectId, todoId: todo.id)
                    )
                )
            }
            if let fileName = todo.rectificationAfterPhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                issues.append(
                    DataHealthIssue(
                        id: "missing-todo-photo-\(todo.id.uuidString)-after-\(fileName)",
                        title: l("待办整改后照片缺失"),
                        detail: issueDetail([projectName(todo.projectId), todo.title, l("整改后"), fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开待办"),
                        route: .siteTodo(projectId: todo.projectId, todoId: todo.id)
                    )
                )
            }
        }
        return issues.sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }
    }

    private var missingDocumentFileIssues: [DataHealthIssue] {
        store.projectDocuments
            .filter { !ProjectDocumentStorage.exists(fileName: $0.fileName) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { document in
                DataHealthIssue(
                    id: "missing-document-\(document.id.uuidString)",
                    title: l("项目资料原文件缺失"),
                    detail: issueDetail([projectName(document.projectId), document.title, document.fileName]),
                    systemImage: "doc.badge.exclamationmark",
                    color: .appRisk,
                    actionTitle: l("打开资料"),
                    route: .document(projectId: document.projectId, documentId: document.id)
                )
            }
    }

    private var missingQuickNoteAttachmentIssues: [DataHealthIssue] {
        store.quickNotes.flatMap { note in
            note.attachments
                .filter { !QuickNoteAttachmentStorage.exists(fileName: $0.fileName) }
                .map { attachment in
                    DataHealthIssue(
                        id: "missing-quicknote-attachment-\(note.id.uuidString)-\(attachment.id.uuidString)",
                        title: l("随手记附件缺失"),
                        detail: issueDetail([note.title.isEmpty ? note.createdAt : note.title, attachment.displayName]),
                        systemImage: "paperclip.badge.ellipsis",
                        color: .appRisk,
                        actionTitle: l("打开随手记"),
                        route: .quickNote(noteId: note.id)
                    )
                }
        }
        .sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }
    }

    private var orphanPhotoFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanPhotoFiles, title: l("孤立照片文件"), systemImage: "photo.stack", color: .appWarning)
    }

    private var orphanDrawingFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDrawingFiles, title: l("孤立图纸文件"), systemImage: "doc.viewfinder", color: .appWarning)
    }

    private var orphanDocumentFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDocumentFiles, title: l("孤立票据文件"), systemImage: "doc.richtext", color: .appWarning)
    }

    private var orphanQuickNoteAttachmentIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanQuickNoteAttachmentFiles, title: l("孤立随手记附件"), systemImage: "paperclip", color: .appWarning)
    }

    private var orphanAttachmentMappingIssues: [DataHealthIssue] {
        let docIdSet = Set(store.projectDocuments.map(\.id))
        return store.projectFinancialRecords.flatMap { record in
            record.linkedDocumentIds.compactMap { docId in
                guard !docIdSet.contains(docId) else { return nil }
                return DataHealthIssue(
                    id: "orphan-financial-attachment-\(record.id.uuidString)-\(docId.uuidString)",
                    title: l("账目附件映射悬空"),
                    detail: issueDetail([projectName(record.projectId), record.date, record.category.displayName, lf("缺失票据ID %@", shortId(docId))]),
                    systemImage: "receipt.badge.exclamationmark",
                    color: .appWarning,
                    actionTitle: l("打开账目"),
                    route: .financialRecord(projectId: record.projectId, recordId: record.id)
                )
            }
        }
    }

    private var orphanWarehouseAttachmentMappingIssues: [DataHealthIssue] {
        let docIdSet = Set(store.projectDocuments.map(\.id))
        return store.projectWarehouseMovements.flatMap { movement in
            movement.linkedDocumentIds.compactMap { docId in
                guard !docIdSet.contains(docId) else { return nil }
                let material = movement.materialName.isEmpty ? l("未命名材料") : movement.materialName
                return DataHealthIssue(
                    id: "orphan-warehouse-attachment-\(movement.id.uuidString)-\(docId.uuidString)",
                    title: l("仓库附件映射悬空"),
                    detail: issueDetail([projectName(movement.projectId), movement.date, material, lf("缺失附件ID %@", shortId(docId))]),
                    systemImage: "shippingbox.and.arrow.backward",
                    color: .appWarning,
                    actionTitle: l("打开仓库"),
                    route: .warehouseProject(projectId: movement.projectId)
                )
            }
        }
    }

    private var danglingDocumentLinkIssues: [DataHealthIssue] {
        let recordIdSet = Set(store.projectFinancialRecords.map(\.id))
        return store.projectDocuments.compactMap { document in
            guard let linkedId = document.linkedFinancialRecordId,
                  !recordIdSet.contains(linkedId) else { return nil }
            return DataHealthIssue(
                id: "dangling-document-link-\(document.id.uuidString)",
                title: l("资料关联账目缺失"),
                detail: issueDetail([projectName(document.projectId), document.title, lf("缺失账目ID %@", shortId(linkedId))]),
                systemImage: "link.badge.plus",
                color: .appWarning,
                actionTitle: l("打开资料"),
                route: .document(projectId: document.projectId, documentId: document.id)
            )
        }
    }

    private var autoFixableInvalidProjectRefIssues: [DataHealthIssue] {
        var issues: [DataHealthIssue] = []
        issues += store.materialItems.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-material-project-\(item.id.uuidString)",
                title: l("材料项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(id))]),
                systemImage: "shippingbox",
                route: .material(materialId: item.id)
            )
        }
        issues += store.quoteItems.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-quote-project-\(item.id.uuidString)",
                title: l("报价项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(id))]),
                systemImage: "doc.text",
                route: .quote(quoteId: item.id)
            )
        }
        issues += store.laborRecords.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-labor-project-\(item.id.uuidString)",
                title: l("人工项目关联无效"),
                detail: issueDetail([item.date, item.workType, lf("原项目ID %@", shortId(id))]),
                systemImage: "person.2",
                route: .labor(laborId: item.id)
            )
        }
        issues += store.dailyLogs.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-log-project-\(item.id.uuidString)",
                title: l("日志项目关联无效"),
                detail: issueDetail([item.date, lf("原项目ID %@", shortId(id))]),
                systemImage: "book.pages",
                route: .dailyLog(projectId: nil, logId: item.id)
            )
        }
        issues += store.siteTodos.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-todo-project-\(item.id.uuidString)",
                title: l("待办项目关联无效"),
                detail: issueDetail([item.title, lf("原项目ID %@", shortId(id))]),
                systemImage: "checklist",
                route: .siteTodo(projectId: nil, todoId: item.id)
            )
        }
        issues += store.quickNotes.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-quicknote-project-\(item.id.uuidString)",
                title: l("随手记项目关联无效"),
                detail: issueDetail([item.title.isEmpty ? item.createdAt : item.title, lf("原项目ID %@", shortId(id))]),
                systemImage: "square.and.pencil",
                route: .quickNote(noteId: item.id)
            )
        }
        issues += store.lightingCircuitPlans.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-circuit-project-\(item.id.uuidString)",
                title: l("照明回路项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(id))]),
                systemImage: "bolt.square",
                route: nil as DataHealthIssueRoute?
            )
        }
        return issues
    }

    private var manualInvalidProjectRefIssues: [DataHealthIssue] {
        var issues: [DataHealthIssue] = []
        issues += store.progressTasks.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-progress-project-\(item.id.uuidString)",
                title: l("进度项目关联无效"),
                detail: issueDetail([item.title, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "calendar.badge.exclamationmark"
            )
        }
        issues += store.projectDrawings.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-drawing-project-\(item.id.uuidString)",
                title: l("图纸项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "doc.viewfinder"
            )
        }
        issues += store.projectContacts.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-contact-project-\(item.id.uuidString)",
                title: l("联系人项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "person.crop.rectangle.stack",
                route: .contact(contactId: item.id)
            )
        }
        issues += store.projectFinancialRecords.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-financial-project-\(item.id.uuidString)",
                title: l("财务项目关联无效"),
                detail: issueDetail([item.date, item.category.displayName, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "receipt"
            )
        }
        issues += store.projectDocuments.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-document-project-\(item.id.uuidString)",
                title: l("资料项目关联无效"),
                detail: issueDetail([item.title, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "doc.richtext"
            )
        }
        issues += store.projectWarehouseMovements.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-warehouse-project-\(item.id.uuidString)",
                title: l("仓库项目关联无效"),
                detail: issueDetail([item.date, item.materialName, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "shippingbox"
            )
        }
        return issues
    }

    private var storageIssueRows: [DataHealthIssue] {
        storageIssues.enumerated().map { offset, text in
            DataHealthIssue(
                id: "storage-issue-\(offset)-\(text.hashValue)",
                title: l("存储错误记录"),
                detail: text,
                systemImage: "externaldrive.badge.exclamationmark",
                color: .appRisk,
                actionTitle: nil,
                route: nil
            )
        }
    }

    private var totalIssues: Int {
        missingPhotoFiles.count
        + missingDocumentFiles.count
        + missingQuickNoteAttachmentFiles.count
        + orphanQuickNoteAttachmentFiles.count
        + orphanPhotoFiles.count
        + orphanDrawingFiles.count
        + orphanDocumentFiles.count
        + orphanAttachmentMappings.count
        + orphanWarehouseAttachmentMappings.count
        + danglingDocumentLinks.count
        + invalidProjectRefs.count
        + storageIssues.count
    }

    private var referenceIssueCount: Int {
        missingPhotoFiles.count
        + missingDocumentFiles.count
        + missingQuickNoteAttachmentFiles.count
        + orphanAttachmentMappings.count
        + orphanWarehouseAttachmentMappings.count
        + danglingDocumentLinks.count
        + autoFixableInvalidProjectRefs.count
    }

    private var orphanFileIssueCount: Int {
        orphanPhotoFiles.count
        + orphanDrawingFiles.count
        + orphanDocumentFiles.count
        + orphanQuickNoteAttachmentFiles.count
    }

    var body: some View {
        List {
            Section(l("健康概览")) {
                LabeledContent(l("问题总数"), value: "\(totalIssues)")
                LabeledContent(l("缺失照片"), value: "\(missingPhotoFiles.count)")
                LabeledContent(l("缺失票据文件"), value: "\(missingDocumentFiles.count)")
                LabeledContent(l("缺失随手记附件"), value: "\(missingQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立照片文件"), value: "\(orphanPhotoFiles.count)")
                LabeledContent(l("孤立图纸文件"), value: "\(orphanDrawingFiles.count)")
                LabeledContent(l("孤立票据文件"), value: "\(orphanDocumentFiles.count)")
                LabeledContent(l("孤立随手记附件"), value: "\(orphanQuickNoteAttachmentFiles.count)")
                LabeledContent(l("孤立附件映射"), value: "\(orphanAttachmentMappings.count)")
                LabeledContent(l("仓库悬空附件映射"), value: "\(orphanWarehouseAttachmentMappings.count)")
                LabeledContent(l("资料悬空关联"), value: "\(danglingDocumentLinks.count)")
                LabeledContent(l("无效项目关联"), value: "\(invalidProjectRefs.count)")
                LabeledContent(l("可自动修复项目关联"), value: "\(autoFixableInvalidProjectRefs.count)")
                LabeledContent(l("需手动处理项目关联"), value: "\(manualInvalidProjectRefs.count)")
                LabeledContent(l("存储错误记录"), value: "\(storageIssues.count)")
            }

            Section(l("存储空间")) {
                LabeledContent(l("照片"), value: QuickNoteAttachmentStorage.formattedFileSize(photoStorageBytes))
                LabeledContent(l("资料（票据/图纸/附件）"), value: QuickNoteAttachmentStorage.formattedFileSize(projectAssetBytes))
                LabeledContent(l("备份（iCloud）"), value: QuickNoteAttachmentStorage.formattedFileSize(cloudBackupBytes))
                LabeledContent(l("历史计算"), value: "\(store.historyRecords.count) 条 · \(QuickNoteAttachmentStorage.formattedFileSize(historyRecordBytes))")
                LabeledContent(l("缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                LabeledContent(l("合计"), value: QuickNoteAttachmentStorage.formattedFileSize(totalStorageBytes))
            }

            Section(l("Widget 与缓存")) {
                LabeledContent(l("App Group 可读"), value: widgetHealth.appGroupReadable ? l("是") : l("否"))
                LabeledContent(l("Widget 项目数"), value: "\(widgetHealth.projectCount)")
                LabeledContent(l("Widget 待办数"), value: "\(widgetHealth.pendingTodos)")
                LabeledContent(
                    l("Widget 最近同步"),
                    value: widgetHealth.lastUpdatedAt.map { Formatters.dateTime.string(from: $0) } ?? l("暂无")
                )
                LabeledContent(l("照片缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(photoThumbnailCacheBytes))
                LabeledContent(l("附件缩略图缓存"), value: QuickNoteAttachmentStorage.formattedFileSize(quickNoteThumbnailCacheBytes))
                LabeledContent(l("缩略图缓存合计"), value: QuickNoteAttachmentStorage.formattedFileSize(mediaThumbnailCacheBytes))
                Button(role: .destructive) {
                    clearMediaThumbnailCaches()
                } label: {
                    Label(l("清理缩略图缓存"), systemImage: "trash")
                }
                .disabled(mediaThumbnailCacheBytes == 0)
            }

            Section(l("处理")) {
                Button {
                    showReferenceFixConfirm = true
                } label: {
                    Label(l("修复引用与关联（不删原件）"), systemImage: "wrench.and.screwdriver")
                }
                .disabled(referenceIssueCount == 0)
                Button(role: .destructive) {
                    showOrphanFileCleanupConfirm = true
                } label: {
                    Label(l("清理孤立原文件"), systemImage: "trash")
                }
                .disabled(orphanFileIssueCount == 0)
                Button {
                    exportHealthReport()
                } label: {
                    Label(l("导出健康报告"), systemImage: "square.and.arrow.up")
                }
                if !storageIssues.isEmpty {
                    Button(role: .destructive) {
                        StorageIssueLog.clear()
                        storageIssuesVersion = UUID()
                    } label: {
                        Label(l("清空存储错误记录"), systemImage: "trash")
                    }
                }
            }

            issueSection(title: l("缺失照片文件"), items: missingPhotoFileIssues)
            issueSection(title: l("缺失票据文件"), items: missingDocumentFileIssues)
            issueSection(title: l("缺失随手记附件"), items: missingQuickNoteAttachmentIssues)
            issueSection(title: l("孤立照片文件"), items: orphanPhotoFileIssues)
            issueSection(title: l("孤立图纸文件"), items: orphanDrawingFileIssues)
            issueSection(title: l("孤立票据文件"), items: orphanDocumentFileIssues)
            issueSection(title: l("孤立随手记附件"), items: orphanQuickNoteAttachmentIssues)
            issueSection(title: l("孤立附件映射"), items: orphanAttachmentMappingIssues)
            issueSection(title: l("仓库悬空附件映射"), items: orphanWarehouseAttachmentMappingIssues)
            issueSection(title: l("资料悬空关联"), items: danglingDocumentLinkIssues)
            issueSection(title: l("无效项目关联（可自动修复）"), items: autoFixableInvalidProjectRefIssues)
            issueSection(title: l("无效项目关联（需手动处理）"), items: manualInvalidProjectRefIssues)
            issueSection(title: l("存储错误记录"), items: storageIssueRows)
        }
        .modifier(OptionalInlineTitleModifier(
            isEnabled: showsNavigationTitle,
            title: l("数据健康检查")
        ))
        .alert(l("修复引用与关联？"), isPresented: $showReferenceFixConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("修复"), role: .destructive) {
                repairReferenceIssues()
            }
        } message: {
            Text(l("将修复缺失引用、财务/仓库悬空附件映射、资料悬空关联和可置空的无效项目关联，不会删除任何照片、图纸、票据或随手记原文件。无法自动修复的项目关联会保留在“需手动处理项目关联”列表。"))
        }
        .alert(l("清理孤立原文件？"), isPresented: $showOrphanFileCleanupConfirm) {
            Button(l("取消"), role: .cancel) {}
            Button(l("清理"), role: .destructive) {
                cleanupOrphanFiles()
            }
        } message: {
            Text(l("将删除未被任何记录引用的照片、图纸、票据和随手记附件。请先确认这些原件无需保留。"))
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .plainText,
            defaultFilename: exportPayload?.defaultFilename ?? l("数据健康报告.txt")
        ) { _ in }
    }

    @ViewBuilder
    private func issueSection(title: String, items: [DataHealthIssue]) -> some View {
        Section("\(title) (\(items.count))") {
            if items.isEmpty {
                Text(l("未发现问题"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.prefix(50))) { item in
                    issueRow(item)
                }
                if items.count > 50 {
                    Text(l("仅显示前 50 条"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func issueRow(_ item: DataHealthIssue) -> some View {
        if let route = item.route {
            NavigationLink {
                issueDestination(route)
            } label: {
                issueLabel(item, canNavigate: true)
            }
        } else {
            issueLabel(item, canNavigate: false)
        }
    }

    private func issueLabel(_ item: DataHealthIssue, canNavigate: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let actionTitle = item.actionTitle {
                    Text(canNavigate ? actionTitle : lf("%@（目标不可用）", actionTitle))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(canNavigate ? .appWarning : .secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.exportText)
    }

    @ViewBuilder
    private func issueDestination(_ route: DataHealthIssueRoute) -> some View {
        switch route {
        case .project(let projectId, let mode):
            ProjectDetailView(projectId: projectId, initialMode: mode)
        case .financialRecord(let projectId, let recordId):
            ProjectDetailView(projectId: projectId, initialMode: .finance, focus: .financialRecord(recordId))
        case .document(let projectId, let documentId):
            ProjectDetailView(projectId: projectId, initialMode: .records, focus: .document(documentId))
        case .dailyLog(let projectId, let logId):
            DailyLogView(initialProjectId: projectId, focusedLogId: logId)
        case .siteTodo(let projectId, let todoId):
            SiteTodoView(initialProjectId: projectId, focusedTodoId: todoId)
        case .material(let materialId):
            MaterialListView(focusedMaterialId: materialId)
        case .quote(let quoteId):
            QuotationView(focusedQuoteId: quoteId)
        case .labor(let laborId):
            LaborRecordView(focusedLaborId: laborId)
        case .quickNote(let noteId):
            QuickNoteView(focusedNoteId: noteId)
        case .contact(let contactId):
            ProjectContactDatabaseView(focusedContactId: contactId)
        case .warehouseProject(let projectId):
            if let project = store.projects.first(where: { $0.id == projectId }) {
                ProjectWarehouseView(project: project)
            } else {
                ContentUnavailableView(l("项目不存在"), systemImage: "questionmark.folder")
            }
        }
    }

    private func fileOnlyIssues(_ fileNames: [String], title: String, systemImage: String, color: Color) -> [DataHealthIssue] {
        fileNames.map { fileName in
            DataHealthIssue(
                id: "\(title)-\(fileName)",
                title: title,
                detail: fileName,
                systemImage: systemImage,
                color: color,
                actionTitle: nil,
                route: nil
            )
        }
    }

    private func invalidProjectIssue(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        route: DataHealthIssueRoute? = nil
    ) -> DataHealthIssue {
        DataHealthIssue(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            color: .appWarning,
            actionTitle: l("打开记录"),
            route: route
        )
    }

    private func manualInvalidProjectIssue(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        route: DataHealthIssueRoute? = nil
    ) -> DataHealthIssue {
        DataHealthIssue(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            color: .appWarning,
            actionTitle: route == nil ? l("需手动处理") : l("打开记录"),
            route: route
        )
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return store.projects.first(where: { $0.id == id })?.name ?? lf("项目ID %@", shortId(id))
    }

    private func issueDetail(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func shortId(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func repairReferenceIssues() {
        let beforeCount = referenceIssueCount
        OperationAuditLog.record(
            action: .repair,
            outcome: .started,
            summary: l("修复引用与关联（不删原件）"),
            detail: String(format: l("%d 项"), beforeCount),
            source: "DataHealthView"
        )
        for index in store.dailyLogs.indices {
            if let fileName = store.dailyLogs[index].photoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                store.dailyLogs[index].photoFileName = nil
            }
            store.dailyLogs[index].photos.removeAll { !PhotoStorage.exists(fileName: $0.fileName) }
        }

        let missingDocumentIds = Set(
            store.projectDocuments
                .filter { !ProjectDocumentStorage.exists(fileName: $0.fileName) }
                .map(\.id)
        )
        if !missingDocumentIds.isEmpty {
            store.projectDocuments.removeAll { missingDocumentIds.contains($0.id) }
        }

        for index in store.quickNotes.indices {
            store.quickNotes[index].attachments.removeAll {
                !QuickNoteAttachmentStorage.exists(fileName: $0.fileName)
            }
        }

        for index in store.siteTodos.indices {
            if let fileName = store.siteTodos[index].rectificationBeforePhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                store.siteTodos[index].rectificationBeforePhotoFileName = nil
            }
            if let fileName = store.siteTodos[index].rectificationAfterPhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                store.siteTodos[index].rectificationAfterPhotoFileName = nil
            }
        }

        let validDocumentIds = Set(store.projectDocuments.map(\.id))
        for index in store.projectFinancialRecords.indices {
            store.projectFinancialRecords[index].linkedDocumentIds.removeAll { !validDocumentIds.contains($0) }
        }
        for index in store.projectWarehouseMovements.indices {
            store.projectWarehouseMovements[index].linkedDocumentIds.removeAll { !validDocumentIds.contains($0) }
        }

        let validRecordIds = Set(store.projectFinancialRecords.map(\.id))
        for index in store.projectDocuments.indices {
            if let linkedId = store.projectDocuments[index].linkedFinancialRecordId,
               !validRecordIds.contains(linkedId) {
                store.projectDocuments[index].linkedFinancialRecordId = nil
            }
        }

        let validProjectIds = Set(store.projects.map(\.id))
        for index in store.materialItems.indices where invalidOptionalProjectId(store.materialItems[index].projectId, validProjectIds: validProjectIds) {
            store.materialItems[index].projectId = nil
        }
        for index in store.quoteItems.indices where invalidOptionalProjectId(store.quoteItems[index].projectId, validProjectIds: validProjectIds) {
            store.quoteItems[index].projectId = nil
        }
        for index in store.laborRecords.indices where invalidOptionalProjectId(store.laborRecords[index].projectId, validProjectIds: validProjectIds) {
            store.laborRecords[index].projectId = nil
        }
        for index in store.dailyLogs.indices where invalidOptionalProjectId(store.dailyLogs[index].projectId, validProjectIds: validProjectIds) {
            store.dailyLogs[index].projectId = nil
        }
        for index in store.siteTodos.indices where invalidOptionalProjectId(store.siteTodos[index].projectId, validProjectIds: validProjectIds) {
            store.siteTodos[index].projectId = nil
        }
        for index in store.quickNotes.indices where invalidOptionalProjectId(store.quickNotes[index].projectId, validProjectIds: validProjectIds) {
            store.quickNotes[index].projectId = nil
        }
        for index in store.lightingCircuitPlans.indices where invalidOptionalProjectId(store.lightingCircuitPlans[index].projectId, validProjectIds: validProjectIds) {
            store.lightingCircuitPlans[index].projectId = nil
        }

        store.scheduleSave()
        let afterCount = referenceIssueCount
        let fixedCount = max(beforeCount - afterCount, 0)
        OperationAuditLog.record(
            action: .repair,
            outcome: .succeeded,
            summary: l("修复"),
            detail: "\(String(format: l("%d 项"), fixedCount)) → \(String(format: l("%d 项"), afterCount))",
            source: "DataHealthView"
        )
    }

    private func clearMediaThumbnailCaches() {
        PhotoStorage.clearThumbnailCache()
        QuickNoteAttachmentStorage.clearThumbnailCache()
        storageIssuesVersion = UUID()
    }

    private func cleanupOrphanFiles() {
        let beforeCount = orphanFileIssueCount
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: l("清理孤立原文件"),
            detail: String(format: l("%d 项"), beforeCount),
            source: "DataHealthView"
        )
        DataStoreDeferredFileCleanup.combined(
            summary: "dataHealth.cleanupOrphanFiles",
            cleanups: [
                DataStoreDeferredFileCleanup.photoFiles(
                    orphanPhotoFiles,
                    summary: "dataHealth.orphanPhotos"
                ),
                DataStoreDeferredFileCleanup.drawingFiles(
                    orphanDrawingFiles,
                    summary: "dataHealth.orphanDrawings"
                ),
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    orphanDocumentFiles,
                    summary: "dataHealth.orphanProjectDocuments"
                ),
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    orphanQuickNoteAttachmentFiles,
                    summary: "dataHealth.orphanQuickNoteAttachments"
                )
            ]
        )
        .perform()
        store.scheduleSave()
        let afterCount = orphanFileIssueCount
        let cleanedCount = max(beforeCount - afterCount, 0)
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .succeeded,
            summary: l("清理"),
            detail: "\(String(format: l("%d 项"), cleanedCount)) → \(String(format: l("%d 项"), afterCount))",
            source: "DataHealthView"
        )
    }

    private func invalidOptionalProjectId(_ id: UUID?, validProjectIds: Set<UUID>) -> Bool {
        guard let id else { return false }
        return !validProjectIds.contains(id)
    }

    private func exportHealthReport() {
        let sections: [(String, [String])] = [
            (l("缺失照片文件"), missingPhotoFileIssues.map(\.exportText)),
            (l("缺失票据文件"), missingDocumentFileIssues.map(\.exportText)),
            (l("缺失随手记附件"), missingQuickNoteAttachmentIssues.map(\.exportText)),
            (l("孤立照片文件"), orphanPhotoFileIssues.map(\.exportText)),
            (l("孤立图纸文件"), orphanDrawingFileIssues.map(\.exportText)),
            (l("孤立票据文件"), orphanDocumentFileIssues.map(\.exportText)),
            (l("孤立随手记附件"), orphanQuickNoteAttachmentIssues.map(\.exportText)),
            (l("孤立附件映射"), orphanAttachmentMappingIssues.map(\.exportText)),
            (l("仓库悬空附件映射"), orphanWarehouseAttachmentMappingIssues.map(\.exportText)),
            (l("资料悬空关联"), danglingDocumentLinkIssues.map(\.exportText)),
            (l("无效项目关联（可自动修复）"), autoFixableInvalidProjectRefIssues.map(\.exportText)),
            (l("无效项目关联（需手动处理）"), manualInvalidProjectRefIssues.map(\.exportText)),
            (l("存储错误记录"), storageIssueRows.map(\.exportText))
        ]
        var lines = [
            lf("%@ 数据健康报告", AppBrand.displayName),
            lf("生成时间: %@", Formatters.now()),
            lf("问题总数: %d", totalIssues),
            ""
        ]
        for (title, items) in sections {
            lines.append("[\(title)] \(items.count)")
            if items.isEmpty {
                lines.append(l("未发现问题"))
            } else {
                lines.append(contentsOf: items)
            }
            lines.append("")
        }
        exportPayload = ExportPayload(
            data: Data(lines.joined(separator: "\n").utf8),
            contentType: .plainText,
            defaultFilename: l("数据健康报告.txt")
        )
        showExporter = true
    }
}

private struct OptionalInlineTitleModifier: ViewModifier {
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

private struct DataHealthIssue: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let actionTitle: String?
    let route: DataHealthIssueRoute?

    var exportText: String {
        detail.isEmpty ? title : "\(title): \(detail)"
    }
}

private enum DataHealthIssueRoute {
    case project(projectId: UUID, mode: ProjectDetailMode?)
    case financialRecord(projectId: UUID, recordId: UUID)
    case document(projectId: UUID, documentId: UUID)
    case dailyLog(projectId: UUID?, logId: UUID)
    case siteTodo(projectId: UUID?, todoId: UUID)
    case material(materialId: UUID)
    case quote(quoteId: UUID)
    case labor(laborId: UUID)
    case quickNote(noteId: UUID)
    case contact(contactId: UUID)
    case warehouseProject(projectId: UUID)
}
