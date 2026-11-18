import SwiftUI

extension DashboardView {
    func collectRecentActivities(limit: Int) -> [TimelineActivity] {
        var activities: [TimelineActivity] = []

        appendRecentWorkActivities(to: &activities)
        appendRecentFinanceActivities(to: &activities)
        appendRecentAssetActivities(to: &activities)

        return activities
            .sorted { lhs, rhs in
                let lhsDate = parseDashboardDate(lhs.date) ?? .distantPast
                let rhsDate = parseDashboardDate(rhs.date) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id > rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    private func appendRecentWorkActivities(to activities: inout [TimelineActivity]) {
        for log in projectStore.dailyLogs {
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AppLocalization.string("施工日志")
                : String(log.content.prefix(40))
            activities.append(
                TimelineActivity(
                    id: "log-\(log.id.uuidString)",
                    projectId: log.projectId,
                    type: .log,
                    title: title,
                    date: log.date,
                    subtitle: AppLocalization.string("施工日志")
                )
            )
        }

        activities += projectStore.progressTasks.map { task in
            TimelineActivity(
                id: "progress-\(task.id.uuidString)",
                projectId: task.projectId,
                type: .progress,
                title: task.title,
                date: task.dueDate.isEmpty ? task.startDate : task.dueDate,
                subtitle: DashboardSubtitleBuilder.progress(task.clampedCompletion * 100)
            )
        }

        activities += projectStore.siteTodos.map { todo in
            TimelineActivity(
                id: "todo-\(todo.id.uuidString)",
                projectId: todo.projectId,
                type: .todo,
                title: todo.title,
                date: todo.completedAt ?? todo.dueDate,
                subtitle: DashboardSubtitleBuilder.todoStatus(isDone: todo.isDone)
            )
        }
    }

    private func appendRecentFinanceActivities(to activities: inout [TimelineActivity]) {
        activities += financeStore.materialItems.map { item in
            TimelineActivity(
                id: "material-\(item.id.uuidString)",
                projectId: item.projectId,
                type: .material,
                title: item.name,
                date: item.arrivalDate,
                subtitle: item.purchaseStatus.displayName
            )
        }

        activities += financeStore.quoteItems.map { item in
            TimelineActivity(
                id: "quote-\(item.id.uuidString)",
                projectId: item.projectId,
                type: .quote,
                title: item.name,
                date: item.customerConfirmedDate,
                subtitle: item.status.displayName
            )
        }

        activities += financeStore.laborRecords.map { item in
            TimelineActivity(
                id: "labor-\(item.id.uuidString)",
                projectId: item.projectId,
                type: .labor,
                title: item.workType.isEmpty ? AppLocalization.string("人工记录") : item.workType,
                date: item.date,
                subtitle: DashboardSubtitleBuilder.labor(
                    workers: "\(item.workers)",
                    hours: "\(item.hours)"
                )
            )
        }

        activities += projectStore.projectFinancialRecords.map { record in
            TimelineActivity(
                id: "finance-\(record.id.uuidString)",
                projectId: record.projectId,
                type: .financial,
                title: "\(record.normalizedDirection.displayName) \(ReportBuilder.money(record.amount))",
                date: record.date,
                subtitle: record.normalizedCategory.displayName
            )
        }
    }

    private func appendRecentAssetActivities(to activities: inout [TimelineActivity]) {
        activities += projectStore.projectDocuments.map { document in
            TimelineActivity(
                id: "document-\(document.id.uuidString)",
                projectId: document.projectId,
                type: .document,
                title: document.title,
                date: document.createdAt,
                subtitle: DashboardSubtitleBuilder.document(
                    category: document.category.displayName,
                    pageCount: document.pageCount
                )
            )
        }

        activities += projectStore.projectWarehouseMovements.map { movement in
            TimelineActivity(
                id: "warehouse-\(movement.id.uuidString)",
                projectId: movement.projectId,
                type: .warehouse,
                title: "\(movement.normalizedMovementType.displayName) \(movement.materialName)",
                date: movement.date,
                subtitle: "\(movement.quantity)\(movement.unit)"
            )
        }

        activities += projectStore.quickNotes.map { note in
            TimelineActivity(
                id: "note-\(note.id.uuidString)",
                projectId: note.projectId,
                type: .note,
                title: note.title.isEmpty ? AppLocalization.string("随手记") : note.title,
                date: note.createdAt,
                subtitle: note.content
            )
        }

        activities += projectStore.projectDrawings.map { drawing in
            TimelineActivity(
                id: "drawing-\(drawing.id.uuidString)",
                projectId: drawing.projectId,
                type: .drawing,
                title: drawing.name,
                date: drawing.importedAt,
                subtitle: drawing.version
            )
        }
    }

    func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return projectNameByID[id]
    }

    func dashboardDestination(for suggestion: RealtimeSearchSuggestion) -> DashboardDestination {
        switch suggestion.category {
        case .command:
            return RealtimeSearchCommand(suggestionId: suggestion.id).map(dashboardCommandDestination(for:)) ?? .projectList()
        case .project:
            return .projectDetail(projectId: suggestion.entityId)
        case .contact:
            return .projectContacts(focusedContactId: suggestion.entityId)
        case .material:
            return .materialPriceDatabase(focusedEntryId: suggestion.entityId)
        case .method:
            return .constructionMethodLibrary(focusedMethodId: suggestion.entityId)
        case .log:
            let projectID = projectStore.dailyLogs.first(where: { $0.id == suggestion.entityId })?.projectId
            return .dailyLog(initialProjectId: projectID, focusedLogId: suggestion.entityId)
        case .todo:
            let projectID = projectStore.siteTodos.first(where: { $0.id == suggestion.entityId })?.projectId
            return .siteTodo(initialProjectId: projectID, focusedTodoId: suggestion.entityId)
        case .note:
            return .quickNote(focusedNoteId: suggestion.entityId)
        default:
            return dashboardBusinessSearchDestination(for: suggestion)
        }
    }

    func dashboardBusinessSearchDestination(for suggestion: RealtimeSearchSuggestion) -> DashboardDestination {
        switch suggestion.category {
        case .quote:
            return .quotation(focusedQuoteID: suggestion.entityId)
        case .financial:
            guard let record = projectStore.projectFinancialRecords.first(where: { $0.id == suggestion.entityId }) else { return .projectList() }
            return .projectDetail(projectId: record.projectId, focus: .financialRecord(record.id))
        case .file:
            guard let document = projectStore.projectDocuments.first(where: { $0.id == suggestion.entityId }) else { return .projectList() }
            return .projectDetail(projectId: document.projectId, focus: .document(document.id))
        case .drawing:
            guard let drawing = projectStore.projectDrawings.first(where: { $0.id == suggestion.entityId }) else { return .projectList() }
            return .projectDetail(projectId: drawing.projectId, focus: .drawing(drawing.id))
        default:
            return .projectList()
        }
    }

    func dashboardCommandDestination(for command: RealtimeSearchCommand) -> DashboardDestination {
        switch command {
        case .newDailyLog:
            return .dailyLog(initialProjectId: currentProject?.id, autoOpenComposer: true)
        case .newTodo:
            return .siteTodo(initialProjectId: currentProject?.id, autoOpenComposer: true)
        case .newQuickNote:
            return .quickNote()
        case .newBookkeeping:
            return bookkeepingEntryDestination
        case .attachReceipt:
            if let project = currentProject {
                return .projectDetail(
                    projectId: project.id,
                    autoOpenDocumentScanSetup: true,
                    initialMode: .assets
                )
            }
            return .projectList(initialOverviewFilter: .missingReceipt)
        case .exportDeliveryPackage:
            if let project = currentProject {
                return .projectDetail(projectId: project.id, autoOpenDeliveryGuide: true)
            }
            return .dataManagement(initialRoute: .export)
        case .backupNow:
            return .dataManagement(initialRoute: .backup)
        case .dataHealthCheck:
            return .dataManagement(initialRoute: .health)
        }
    }

    func warehouseLinkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let documentIds = Set(movement.linkedDocumentIds)
        guard !documentIds.isEmpty else { return [] }
        return projectStore.projectDocuments.filter { documentIds.contains($0.id) }
    }

    func dashboardReceivableAgeDays(for project: Project, receivableAmount: MoneyValue) -> Int? {
        guard receivableAmount > 0 else { return nil }
        guard let endDate = Formatters.date.date(from: project.expectedEndDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDate = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: today).day ?? 0
        return max(days, 0)
    }

    func parseDashboardDate(_ value: BusinessDateValue) -> Date? {
        value.date()
    }
}
