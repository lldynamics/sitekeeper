import SwiftUI
import Foundation

extension DataHealthView {
    var projectIdSet: Set<UUID> {
        Set(store.projects.map(\.id))
    }

    var missingPhotoFiles: [String] {
        let logPhotoNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoPhotoNames = store.siteTodos
            .flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }
            .compactMap { $0 }
        let names = Set(logPhotoNames + todoPhotoNames)
        return names.filter { !PhotoStorage.exists(fileName: $0) }.sorted()
    }

    var missingDocumentFiles: [String] {
        store.projectDocuments
            .filter { !ProjectDocumentStorage.exists(fileName: $0.fileName) }
            .map(\.fileName)
            .sorted()
    }

    var missingQuickNoteAttachmentFiles: [String] {
        let allAttachments = store.quickNotes.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        return allAttachments
            .filter { !QuickNoteAttachmentStorage.exists(fileName: $0.fileName) }
            .map(\.fileName)
            .sorted()
    }

    var orphanQuickNoteAttachmentFiles: [String] {
        QuickNoteAttachmentStorage.orphanFileNames(
            for: store.quickNotes,
            extraAttachments: store.constructionMethods.flatMap(\.attachments) + store.constructionMethods.flatMap(\.tutorialAttachments)
        )
    }

    var orphanPhotoFiles: [String] {
        PhotoStorage.orphanFileNames(logs: store.dailyLogs, todos: store.siteTodos)
    }

    var orphanDrawingFiles: [String] {
        DrawingStorage.orphanFileNames(for: store.projectDrawings)
    }

    var orphanDocumentFiles: [String] {
        ProjectDocumentStorage.orphanFileNames(for: store.projectDocuments)
    }

    var orphanAttachmentMappings: [String] {
        orphanAttachmentMappingIssues.map(\.exportText)
    }

    var orphanWarehouseAttachmentMappings: [String] {
        orphanWarehouseAttachmentMappingIssues.map(\.exportText)
    }

    var danglingDocumentLinks: [String] {
        danglingDocumentLinkIssues.map(\.exportText)
    }

    var autoFixableInvalidProjectRefs: [String] {
        autoFixableInvalidProjectRefIssues.map(\.exportText)
    }

    var manualInvalidProjectRefs: [String] {
        manualInvalidProjectRefIssues.map(\.exportText)
    }

    var invalidProjectRefs: [String] {
        autoFixableInvalidProjectRefs + manualInvalidProjectRefs
    }

    var storageIssues: [String] {
        _ = storageIssuesVersion
        return StorageIssueLog.entries()
    }

    var widgetHealth: WidgetDataHealthSnapshot {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else {
            return WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
        }
        let data: WidgetExportData
        if let raw = defaults.data(forKey: WidgetSharedDefaults.dataKey),
           let decoded = try? JSONDecoder().decode(WidgetExportData.self, from: raw) {
            data = decoded
        } else {
            data = WidgetExportData(projects: [], pendingTodos: 0, materialStockCount: 0, lowStockCount: 0)
        }
        let timestamp = defaults.double(forKey: WidgetSharedDefaults.updatedAtKey)
        return WidgetDataHealthSnapshot(
            appGroupReadable: true,
            lastUpdatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil,
            projectCount: data.projects.count,
            pendingTodos: data.pendingTodos
        )
    }

    var photoThumbnailCacheBytes: Int {
        PhotoStorage.thumbnailCacheUsageBytes()
    }

    var quickNoteThumbnailCacheBytes: Int {
        QuickNoteAttachmentStorage.thumbnailCacheUsageBytes()
    }

    var mediaThumbnailCacheBytes: Int {
        photoThumbnailCacheBytes + quickNoteThumbnailCacheBytes
    }

    var referencedPhotoFileNames: Set<String> {
        let logNames = store.dailyLogs.flatMap(\.allPhotoFileNames)
        let todoNames = store.siteTodos
            .flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }
            .compactMap { $0 }
        return Set(logNames + todoNames)
    }

    var photoStorageBytes: Int {
        referencedPhotoFileNames.reduce(0) { total, fileName in
            total + PhotoStorage.fileSize(for: fileName)
        }
    }

    var projectDocumentBytes: Int {
        Set(store.projectDocuments.map(\.fileName)).reduce(0) { total, fileName in
            total + ProjectDocumentStorage.fileSize(for: fileName)
        }
    }

    var projectDrawingBytes: Int {
        Set(store.projectDrawings.map(\.fileName)).reduce(0) { total, fileName in
            total + DrawingStorage.fileSize(for: fileName)
        }
    }

    var quickNoteAttachmentBytes: Int {
        let attachments = store.quickNotes.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let names = Set(attachments.map(\.fileName))
        return names.reduce(0) { total, fileName in
            total + QuickNoteAttachmentStorage.fileSize(for: fileName)
        }
    }

    var projectAssetBytes: Int {
        projectDocumentBytes + projectDrawingBytes + quickNoteAttachmentBytes
    }

    var cloudBackupBytes: Int {
        (try? CloudBackupService.listBackups().reduce(0) { $0 + $1.byteSize }) ?? 0
    }

    var historyRecordBytes: Int {
        (try? JSONEncoder().encode(store.historyRecords).count) ?? 0
    }

    var totalStorageBytes: Int {
        photoStorageBytes
            + projectAssetBytes
            + mediaThumbnailCacheBytes
            + cloudBackupBytes
            + historyRecordBytes
    }

    var missingPhotoFileIssues: [DataHealthIssue] {
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

    var missingDocumentFileIssues: [DataHealthIssue] {
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

    var missingQuickNoteAttachmentIssues: [DataHealthIssue] {
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

    var orphanPhotoFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanPhotoFiles, title: l("孤立照片文件"), systemImage: "photo.stack", color: .appWarning)
    }

    var orphanDrawingFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDrawingFiles, title: l("孤立图纸文件"), systemImage: "doc.viewfinder", color: .appWarning)
    }

    var orphanDocumentFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDocumentFiles, title: l("孤立票据文件"), systemImage: "doc.richtext", color: .appWarning)
    }

    var orphanQuickNoteAttachmentIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanQuickNoteAttachmentFiles, title: l("孤立随手记附件"), systemImage: "paperclip", color: .appWarning)
    }

    var orphanAttachmentMappingIssues: [DataHealthIssue] {
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

    var orphanWarehouseAttachmentMappingIssues: [DataHealthIssue] {
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

    var danglingDocumentLinkIssues: [DataHealthIssue] {
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

    var autoFixableInvalidProjectRefIssues: [DataHealthIssue] {
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
        return issues
    }

    var manualInvalidProjectRefIssues: [DataHealthIssue] {
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

    var storageIssueRows: [DataHealthIssue] {
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

    var totalIssues: Int {
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

    var referenceIssueCount: Int {
        missingPhotoFiles.count
            + missingDocumentFiles.count
            + missingQuickNoteAttachmentFiles.count
            + orphanAttachmentMappings.count
            + orphanWarehouseAttachmentMappings.count
            + danglingDocumentLinks.count
            + autoFixableInvalidProjectRefs.count
    }

    var orphanFileIssueCount: Int {
        orphanPhotoFiles.count
            + orphanDrawingFiles.count
            + orphanDocumentFiles.count
            + orphanQuickNoteAttachmentFiles.count
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
}
