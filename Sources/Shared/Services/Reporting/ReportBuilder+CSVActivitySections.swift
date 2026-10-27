import Foundation

extension ReportBuilder {
    static func dailyLogCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeDailyLogs else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("daily_logs"))
        rows.append(csv(["date", "weather", "workers", "content", "safety", "materials", "tomorrow_plan", "quality_issue", "rectification", "confirmer", "photo_count", "project_id"]))
        rows += snapshot.dailyLogs.map { log in
            csv([
                log.date,
                log.weather,
                log.workers,
                log.content,
                log.safety,
                log.materials,
                log.tomorrowPlan,
                log.qualityIssue,
                log.rectification,
                log.confirmer,
                "\(log.photoAttachments.count)",
                log.projectId?.uuidString ?? ""
            ])
        }
        rows.append("")
        return rows
    }

    static func progressCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeProgress else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("progress_tasks"))
        rows.append(csv(["title", "start_date", "due_date", "completion_percent", "note", "project_id"]))
        rows += snapshot.progressTasks.map { task in
            csv([
                task.title,
                task.startDate,
                task.dueDate,
                String(format: "%.0f", task.clampedCompletion * 100),
                task.note,
                task.projectId.uuidString
            ])
        }
        rows.append("")
        return rows
    }

    static func todoCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeTodos else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("site_todos"))
        rows.append(csv(["title", "owner", "due_date", "priority_key", "priority_display", "issue_type_key", "issue_type_display", "drawing_issue_location", "drawing_issue_layer_or_page", "drawing_issue_measurement", "drawing_issue_close_evidence", "status_key", "status_display", "completed_at", "rectification_before_photo", "rectification_after_photo", "note", "project_id"]))
        rows += snapshot.siteTodos.map { todo in
            csv([
                todo.title,
                todo.owner,
                todo.dueDate,
                todo.priority.exportKey,
                todo.priority.displayName,
                todo.issueType.exportKey,
                todo.issueType.displayName,
                todo.drawingIssueLocation,
                todo.drawingIssueLayerOrPage,
                todo.drawingIssueMeasurement,
                todo.drawingIssueCloseEvidence,
                siteTodoStatusKey(todo),
                siteTodoStatusDisplay(todo),
                todo.completedAt ?? "",
                todo.rectificationBeforePhotoFileName ?? "",
                todo.rectificationAfterPhotoFileName ?? "",
                todo.note,
                todo.projectId?.uuidString ?? ""
            ])
        }
        rows.append("")
        return rows
    }

    static func quickNoteCSVRows(
        snapshot: BackupSnapshot,
        options: ExportContentOptions
    ) -> [String] {
        guard options.includeQuickNotes else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("quick_notes"))
        rows.append(csv(["title", "content", "created_at", "updated_at", "attachment_count", "project_id"]))
        rows += snapshot.quickNotes.map { note in
            csv([
                note.title,
                note.content,
                note.createdAt,
                note.updatedAt,
                "\(note.attachments.count)",
                note.projectId?.uuidString ?? ""
            ])
        }
        rows.append("")
        return rows
    }

    static func operationAuditCSVRows(options: ExportContentOptions) -> [String] {
        guard options.includeOperationAuditLogs else { return [] }
        var rows: [String] = []
        rows.append(csvMachineSection("operation_audit_log"))
        rows.append(csv(["timestamp", "action_key", "action_display", "outcome_key", "outcome_display", "summary", "detail", "source", "id"]))
        rows += options.operationAuditEntries.map { entry in
            csv([
                Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp)),
                entry.action.rawValue,
                operationAuditActionDisplayName(entry.action),
                entry.outcome.rawValue,
                operationAuditOutcomeDisplayName(entry.outcome),
                entry.summary,
                entry.detail,
                entry.source,
                entry.id.uuidString
            ])
        }
        rows.append("")
        return rows
    }

    private static func siteTodoStatusKey(_ todo: SiteTodo) -> String {
        if todo.isDone { return "done" }
        if todo.isOverdue { return "overdue" }
        return "pending"
    }

    private static func siteTodoStatusDisplay(_ todo: SiteTodo) -> String {
        if todo.isDone { return locDone }
        if todo.isOverdue { return locOverdue }
        return locPending
    }
}
