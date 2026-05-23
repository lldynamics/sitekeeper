import Foundation

extension ProjectDocumentsView {
    func applyChecklistTemplate(_ template: ProjectDocumentChecklistTemplate) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updatedProject = store.projects[index]
        updatedProject.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
            template.categories
        )
        guard store.updateProject(updatedProject) else { return }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已套用%@模板"), template.name))
    }

    func beginSaveCurrentChecklistTemplate() {
        let normalizedProjectName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = normalizedProjectName.isEmpty ? String(localized: "项目") : normalizedProjectName
        templateName = String(format: String(localized: "%@资料清单"), baseName)
        showSaveTemplatePrompt = true
    }

    func saveCurrentChecklistTemplate() {
        let normalizedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? String(localized: "资料清单模板") : normalizedName
        let template = ProjectTemplate.documentChecklistTemplate(
            name: resolvedName,
            categories: checklistSnapshot.requiredCategories
        )
        if let existing = store.templates.first(where: {
            $0.category == .projectDocumentChecklist &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == resolvedName
        }) {
            var updatedTemplate = template
            updatedTemplate.id = existing.id
            store.upsertTemplate(updatedTemplate, insertAtTopWhenNew: true)
        } else {
            store.insertTemplateAtTop(template)
        }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已保存资料清单模板"))
    }

    func missingChecklistItemsWithoutOpenTodo(_ items: [DocumentArchiveChecklistItem]) -> [DocumentArchiveChecklistItem] {
        items.filter { item in
            item.isMissing && !hasOpenArchiveTodo(for: item.category)
        }
    }

    func hasOpenArchiveTodo(for category: ProjectDocumentCategory) -> Bool {
        hasOpenTodo(title: archiveTodoTitle(for: category))
    }

    func hasOpenTodo(title: String) -> Bool {
        store.siteTodos.contains { todo in
            todo.projectId == project.id &&
            !todo.isDone &&
            todo.title == title
        }
    }

    func createMissingDocumentTodos(from items: [DocumentArchiveChecklistItem]) {
        let missingItems = missingChecklistItemsWithoutOpenTodo(items)
        guard !missingItems.isEmpty else {
            operationNotice = .info(String(localized: "缺项待办已存在"))
            return
        }
        let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        for item in missingItems {
            store.insertSiteTodoAtTop(SiteTodo(
                title: archiveTodoTitle(for: item.category),
                owner: project.managerName,
                dueDate: Formatters.date.string(from: dueDate),
                priority: .medium,
                issueType: .general,
                note: String(format: String(localized: "施工资料清单缺项：%@。补录后到项目资料页更新报验状态和归档信息。"), item.category.displayName),
                projectId: project.id
            ))
        }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已生成 %lld 条缺项待办"), Int64(missingItems.count)))
    }

    func remediationTodoDraftsWithoutOpenTodo(
        _ drafts: [ProjectDocumentDeliveryInspectionTodoDraft]
    ) -> [ProjectDocumentDeliveryInspectionTodoDraft] {
        var seenTitles = Set<String>()
        return drafts.filter { draft in
            seenTitles.insert(draft.title).inserted && !hasOpenTodo(title: draft.title)
        }
    }

    func createDeliveryInspectionTodos(from inspection: ProjectDocumentDeliveryInspection) {
        let drafts = remediationTodoDraftsWithoutOpenTodo(inspection.remediationTodoDrafts)
        guard !drafts.isEmpty else {
            operationNotice = .info(String(localized: "体检整改待办已存在"))
            return
        }

        let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        for draft in drafts {
            store.insertSiteTodoAtTop(SiteTodo(
                title: draft.title,
                owner: project.managerName,
                dueDate: Formatters.date.string(from: dueDate),
                priority: draft.priority,
                issueType: draft.issueType,
                note: draft.note,
                projectId: project.id
            ))
        }

        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已生成 %lld 条体检整改待办"), Int64(drafts.count)))
    }

    func applyStageRecommendation(_ missingCategories: [ProjectDocumentCategory]) {
        guard !missingCategories.isEmpty else { return }
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updatedProject = store.projects[index]
        let merged = updatedProject.requiredDocumentCategories + missingCategories
        updatedProject.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(merged)
        guard store.updateProject(updatedProject) else { return }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已启用%@推荐"), recommendedStage.displayName))
    }

    func archiveTodoTitle(for category: ProjectDocumentCategory) -> String {
        String(format: String(localized: "补齐施工资料：%@"), category.displayName)
    }
}
