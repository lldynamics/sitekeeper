import SwiftUI

extension DataHealthView {
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
}
