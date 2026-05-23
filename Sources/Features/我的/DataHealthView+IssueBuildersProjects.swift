import SwiftUI

extension DataHealthView {
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
}
