import SwiftUI
import Foundation

extension DataHealthView {
    private var latestScan: DataHealthScanSummary? {
        store.latestDataHealthScan
    }

    private var latestSnapshot: DataHealthScanSnapshot? {
        store.latestDataHealthSnapshot
    }

    var projectIdSet: Set<UUID> {
        Set(store.projects.map(\.id))
    }

    var missingPhotoFiles: [String] {
        latestSnapshot?.missingPhotoFileNames ?? []
    }

    var missingDocumentFiles: [String] {
        latestSnapshot?.missingDocumentFileNames ?? []
    }

    var missingQuickNoteAttachmentFiles: [String] {
        latestSnapshot?.missingQuickNoteAttachmentFileNames ?? []
    }

    var orphanQuickNoteAttachmentFiles: [String] {
        latestSnapshot?.orphanQuickNoteAttachmentFileNames ?? []
    }

    var orphanPhotoFiles: [String] {
        latestSnapshot?.orphanPhotoFileNames ?? []
    }

    var orphanDrawingFiles: [String] {
        latestSnapshot?.orphanDrawingFileNames ?? []
    }

    var orphanDocumentFiles: [String] {
        latestSnapshot?.orphanDocumentFileNames ?? []
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
        latestSnapshot?.storageIssues ?? []
    }

    var widgetHealth: WidgetDataHealthSnapshot {
        latestSnapshot?.widgetHealth
            ?? latestScan?.widgetHealth
            ?? WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
    }

    var photoThumbnailCacheBytes: Int {
        latestSnapshot?.storageUsage.photoThumbnailCacheBytes ?? 0
    }

    var quickNoteThumbnailCacheBytes: Int {
        latestSnapshot?.storageUsage.quickNoteThumbnailCacheBytes ?? 0
    }

    var mediaThumbnailCacheBytes: Int {
        photoThumbnailCacheBytes + quickNoteThumbnailCacheBytes
    }

    var photoStorageBytes: Int {
        latestSnapshot?.storageUsage.photoStorageBytes ?? 0
    }

    var projectDocumentBytes: Int {
        latestSnapshot?.storageUsage.projectDocumentBytes ?? 0
    }

    var projectDrawingBytes: Int {
        latestSnapshot?.storageUsage.projectDrawingBytes ?? 0
    }

    var quickNoteAttachmentBytes: Int {
        latestSnapshot?.storageUsage.quickNoteAttachmentBytes ?? 0
    }

    var projectAssetBytes: Int {
        projectDocumentBytes + projectDrawingBytes + quickNoteAttachmentBytes
    }

    var cloudBackupBytes: Int {
        latestSnapshot?.storageUsage.cloudBackupBytes ?? 0
    }

    var historyRecordBytes: Int {
        latestSnapshot?.storageUsage.historyRecordBytes ?? 0
    }

    var totalStorageBytes: Int {
        latestSnapshot?.storageUsage.totalStorageBytes ?? 0
    }

    var missingPhotoFileIssues: [DataHealthIssue] {
        let missingPhotoSet = Set(missingPhotoFiles)
        var issues: [DataHealthIssue] = []
        for log in store.dailyLogs {
            if let fileName = log.photoFileName,
               missingPhotoSet.contains(fileName) {
                let route = DataHealthIssueRoute.dailyLog(projectId: log.projectId, logId: log.id)
                issues.append(
                    DataHealthIssue(
                        id: "missing-log-photo-\(log.id.uuidString)-legacy-\(fileName)",
                        title: l("日志照片缺失"),
                        detail: issueDetail([projectName(log.projectId), log.date, fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开日志"),
                        route: route,
                        actions: [
                            .navigate(title: l("打开日志补照片"), route: route),
                            .repair(
                                title: l("移除缺失引用"),
                                repair: .clearDailyLogLegacyPhoto(logId: log.id, fileName: fileName)
                            )
                        ]
                    )
                )
            }
            for photo in log.photos where missingPhotoSet.contains(photo.fileName) {
                let route = DataHealthIssueRoute.dailyLog(projectId: log.projectId, logId: log.id)
                issues.append(
                    DataHealthIssue(
                        id: "missing-log-photo-\(log.id.uuidString)-\(photo.id.uuidString)",
                        title: l("日志照片缺失"),
                        detail: issueDetail([projectName(log.projectId), log.date, photo.tag.displayName, photo.fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开日志"),
                        route: route,
                        actions: [
                            .navigate(title: l("打开日志补照片"), route: route),
                            .repair(
                                title: l("移除缺失引用"),
                                repair: .removeDailyLogPhoto(logId: log.id, photoId: photo.id)
                            )
                        ]
                    )
                )
            }
        }
        for todo in store.siteTodos {
            if let fileName = todo.rectificationBeforePhotoFileName,
               missingPhotoSet.contains(fileName) {
                let route = DataHealthIssueRoute.siteTodo(projectId: todo.projectId, todoId: todo.id)
                issues.append(
                    DataHealthIssue(
                        id: "missing-todo-photo-\(todo.id.uuidString)-before-\(fileName)",
                        title: l("待办整改前照片缺失"),
                        detail: issueDetail([projectName(todo.projectId), todo.title, l("整改前"), fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开待办"),
                        route: route,
                        actions: [
                            .navigate(title: l("打开待办补照片"), route: route),
                            .repair(
                                title: l("移除缺失引用"),
                                repair: .clearSiteTodoBeforePhoto(todoId: todo.id, fileName: fileName)
                            )
                        ]
                    )
                )
            }
            if let fileName = todo.rectificationAfterPhotoFileName,
               missingPhotoSet.contains(fileName) {
                let route = DataHealthIssueRoute.siteTodo(projectId: todo.projectId, todoId: todo.id)
                issues.append(
                    DataHealthIssue(
                        id: "missing-todo-photo-\(todo.id.uuidString)-after-\(fileName)",
                        title: l("待办整改后照片缺失"),
                        detail: issueDetail([projectName(todo.projectId), todo.title, l("整改后"), fileName]),
                        systemImage: "photo.badge.exclamationmark",
                        color: .appRisk,
                        actionTitle: l("打开待办"),
                        route: route,
                        actions: [
                            .navigate(title: l("打开待办补照片"), route: route),
                            .repair(
                                title: l("移除缺失引用"),
                                repair: .clearSiteTodoAfterPhoto(todoId: todo.id, fileName: fileName)
                            )
                        ]
                    )
                )
            }
        }
        return issues.sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }
    }

    var missingDocumentFileIssues: [DataHealthIssue] {
        let missingDocumentSet = Set(missingDocumentFiles)
        return store.projectDocuments
            .filter { missingDocumentSet.contains($0.fileName) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { document in
                let route = DataHealthIssueRoute.document(projectId: document.projectId, documentId: document.id)
                return DataHealthIssue(
                    id: "missing-document-\(document.id.uuidString)",
                    title: l("项目资料原文件缺失"),
                    detail: issueDetail([projectName(document.projectId), document.title, document.fileName]),
                    systemImage: "doc.badge.exclamationmark",
                    color: .appRisk,
                    actionTitle: l("打开资料"),
                    route: route,
                    actions: [
                        .navigate(title: l("打开资料补原件"), route: route),
                        .repair(
                            title: l("移除缺失记录"),
                            repair: .removeProjectDocument(documentId: document.id)
                        )
                    ]
                )
            }
    }

    var missingQuickNoteAttachmentIssues: [DataHealthIssue] {
        let missingAttachmentSet = Set(missingQuickNoteAttachmentFiles)
        let issues: [DataHealthIssue] = store.quickNotes.flatMap { note in
            note.attachments
                .filter { missingAttachmentSet.contains($0.fileName) }
                .map { attachment in
                    let route = DataHealthIssueRoute.quickNote(noteId: note.id)
                    return DataHealthIssue(
                        id: "missing-quicknote-attachment-\(note.id.uuidString)-\(attachment.id.uuidString)",
                        title: l("随手记附件缺失"),
                        detail: issueDetail([note.title.isEmpty ? note.createdAt : note.title, attachment.displayName]),
                        systemImage: "paperclip.badge.ellipsis",
                        color: .appRisk,
                        actionTitle: l("打开随手记"),
                        projectId: note.projectId,
                        route: route,
                        actions: [
                            .navigate(title: l("打开随手记补附件"), route: route),
                            .repair(
                                title: l("移除缺失引用"),
                                repair: .removeQuickNoteAttachment(noteId: note.id, attachmentId: attachment.id)
                            )
                        ]
                    )
                }
        }
        return issues.sorted { lhs, rhs in
            lhs.detail.localizedStandardCompare(rhs.detail) == .orderedAscending
        }
    }

    var orphanPhotoFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanPhotoFiles, title: l("孤立照片文件"), systemImage: "photo.stack", color: .appWarning, kind: .photo)
    }

    var orphanDrawingFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDrawingFiles, title: l("孤立图纸文件"), systemImage: "doc.viewfinder", color: .appWarning, kind: .drawing)
    }

    var orphanDocumentFileIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanDocumentFiles, title: l("孤立票据文件"), systemImage: "doc.richtext", color: .appWarning, kind: .projectDocument)
    }

    var orphanQuickNoteAttachmentIssues: [DataHealthIssue] {
        fileOnlyIssues(orphanQuickNoteAttachmentFiles, title: l("孤立随手记附件"), systemImage: "paperclip", color: .appWarning, kind: .quickNoteAttachment)
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
                    route: .financialRecord(projectId: record.projectId, recordId: record.id),
                    actions: [
                        .repair(
                            title: l("修复该项"),
                            repair: .unlinkFinancialDocument(recordId: record.id, documentId: docId)
                        )
                    ]
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
                    route: .warehouseProject(projectId: movement.projectId),
                    actions: [
                        .repair(
                            title: l("修复该项"),
                            repair: .unlinkWarehouseDocument(movementId: movement.id, documentId: docId)
                        )
                    ]
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
                route: .document(projectId: document.projectId, documentId: document.id),
                actions: [
                    .repair(
                        title: l("修复该项"),
                        repair: .clearDocumentLinkedFinancialRecord(documentId: document.id)
                    )
                ]
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
                projectId: id,
                route: .material(materialId: item.id),
                repair: .clearMaterialProject(itemId: item.id)
            )
        }
        issues += store.quoteItems.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-quote-project-\(item.id.uuidString)",
                title: l("报价项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(id))]),
                systemImage: "doc.text",
                projectId: id,
                route: .quote(quoteId: item.id),
                repair: .clearQuoteProject(itemId: item.id)
            )
        }
        issues += store.laborRecords.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-labor-project-\(item.id.uuidString)",
                title: l("人工项目关联无效"),
                detail: issueDetail([item.date, item.workType, lf("原项目ID %@", shortId(id))]),
                systemImage: "person.2",
                projectId: id,
                route: .labor(laborId: item.id),
                repair: .clearLaborProject(recordId: item.id)
            )
        }
        issues += store.dailyLogs.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-log-project-\(item.id.uuidString)",
                title: l("日志项目关联无效"),
                detail: issueDetail([item.date, lf("原项目ID %@", shortId(id))]),
                systemImage: "book.pages",
                projectId: id,
                route: .dailyLog(projectId: nil, logId: item.id),
                repair: .clearDailyLogProject(logId: item.id)
            )
        }
        issues += store.siteTodos.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-todo-project-\(item.id.uuidString)",
                title: l("待办项目关联无效"),
                detail: issueDetail([item.title, lf("原项目ID %@", shortId(id))]),
                systemImage: "checklist",
                projectId: id,
                route: .siteTodo(projectId: nil, todoId: item.id),
                repair: .clearSiteTodoProject(todoId: item.id)
            )
        }
        issues += store.quickNotes.compactMap { item in
            guard let id = item.projectId, !projectIdSet.contains(id) else { return nil }
            return invalidProjectIssue(
                id: "invalid-quicknote-project-\(item.id.uuidString)",
                title: l("随手记项目关联无效"),
                detail: issueDetail([item.title.isEmpty ? item.createdAt : item.title, lf("原项目ID %@", shortId(id))]),
                systemImage: "square.and.pencil",
                projectId: id,
                route: .quickNote(noteId: item.id),
                repair: .clearQuickNoteProject(noteId: item.id)
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
                systemImage: "calendar.badge.exclamationmark",
                projectId: item.projectId
            )
        }
        issues += store.projectDrawings.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-drawing-project-\(item.id.uuidString)",
                title: l("图纸项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "doc.viewfinder",
                projectId: item.projectId
            )
        }
        issues += store.projectContacts.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-contact-project-\(item.id.uuidString)",
                title: l("联系人项目关联无效"),
                detail: issueDetail([item.name, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "person.crop.rectangle.stack",
                projectId: item.projectId,
                route: .contact(contactId: item.id)
            )
        }
        issues += store.projectFinancialRecords.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-financial-project-\(item.id.uuidString)",
                title: l("财务项目关联无效"),
                detail: issueDetail([item.date, item.category.displayName, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "receipt",
                projectId: item.projectId
            )
        }
        issues += store.projectDocuments.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-document-project-\(item.id.uuidString)",
                title: l("资料项目关联无效"),
                detail: issueDetail([item.title, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "doc.richtext",
                projectId: item.projectId
            )
        }
        issues += store.projectWarehouseMovements.compactMap { item in
            guard !projectIdSet.contains(item.projectId) else { return nil }
            return manualInvalidProjectIssue(
                id: "invalid-warehouse-project-\(item.id.uuidString)",
                title: l("仓库项目关联无效"),
                detail: issueDetail([item.date, item.materialName, lf("原项目ID %@", shortId(item.projectId))]),
                systemImage: "shippingbox",
                projectId: item.projectId
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
        latestScan?.totalIssues ?? 0
    }

    var referenceIssueCount: Int {
        latestScan.map { summary in
            summary.missingPhotoFiles
                + summary.missingDocumentFiles
                + summary.missingQuickNoteAttachmentFiles
                + summary.orphanAttachmentMappings
                + summary.orphanWarehouseAttachmentMappings
                + summary.danglingDocumentLinks
                + autoFixableInvalidProjectRefs.count
        } ?? 0
    }

    var orphanFileIssueCount: Int {
        latestScan.map { summary in
            summary.orphanPhotoFiles
                + summary.orphanDrawingFiles
                + summary.orphanDocumentFiles
                + summary.orphanQuickNoteAttachmentFiles
        } ?? 0
    }

    private func fileOnlyIssues(
        _ fileNames: [String],
        title: String,
        systemImage: String,
        color: Color,
        kind: DataHealthOrphanFileKind
    ) -> [DataHealthIssue] {
        fileNames.map { fileName in
            DataHealthIssue(
                id: "\(title)-\(fileName)",
                title: title,
                detail: fileName,
                systemImage: systemImage,
                color: color,
                actionTitle: nil,
                route: nil,
                actions: [
                    .moveToTrash(
                        title: l("移入回收站"),
                        file: DataHealthOrphanFile(kind: kind, fileName: fileName)
                    )
                ]
            )
        }
    }

    private func invalidProjectIssue(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        projectId: UUID? = nil,
        route: DataHealthIssueRoute? = nil,
        repair: DataHealthIssueRepair
    ) -> DataHealthIssue {
        DataHealthIssue(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            color: .appWarning,
            actionTitle: l("打开记录"),
            projectId: projectId,
            route: route,
            actions: [
                .repair(title: l("修复该项"), repair: repair)
            ]
        )
    }

    private func manualInvalidProjectIssue(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        projectId: UUID? = nil,
        route: DataHealthIssueRoute? = nil
    ) -> DataHealthIssue {
        DataHealthIssue(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            color: .appWarning,
            actionTitle: route == nil ? l("需手动处理") : l("打开记录"),
            projectId: projectId,
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
