import Foundation

extension DataHealthView {
    func performIssueAction(_ action: DataHealthIssueAction, for issue: DataHealthIssue) {
        switch action.kind {
        case .navigate:
            break
        case .repair(let repair):
            repairDataHealthIssue(issue, repair: repair)
        case .moveOrphanFileToTrash(let file):
            moveOrphanFileToTrash(file, issue: issue)
        case .createTodo:
            createDataHealthRepairTodo(for: issue)
        }
    }

    func repairDataHealthIssue(_ issue: DataHealthIssue, repair: DataHealthIssueRepair) {
        OperationAuditLog.record(
            action: .repair,
            outcome: .started,
            summary: issue.title,
            detail: issue.detail,
            source: "DataHealthView.issueAction"
        )

        let changed = applyDataHealthIssueRepair(repair)
        guard changed else {
            OperationAuditLog.record(
                action: .repair,
                outcome: .cancelled,
                summary: issue.title,
                detail: l("该项已不存在或无需修复"),
                source: "DataHealthView.issueAction"
            )
            AppHaptics.warning()
            operationNotice = .info(l("该项已不存在或无需修复"))
            store.runDataHealthScanNow(reason: .manual)
            return
        }

        store.scheduleSave()
        store.runDataHealthScanNow(reason: .manual)
        OperationAuditLog.record(
            action: .repair,
            outcome: .succeeded,
            summary: issue.title,
            detail: issue.detail,
            source: "DataHealthView.issueAction"
        )
        AppHaptics.success()
        operationNotice = .info(l("已修复该项"))
    }

    func moveOrphanFileToTrash(_ file: DataHealthOrphanFile, issue: DataHealthIssue) {
        let cleanup = orphanFileCleanup(for: file)
        guard let cleanup else {
            AppHaptics.warning()
            operationNotice = .info(l("该文件已不存在或无法处理"))
            store.runDataHealthScanNow(reason: .manual)
            return
        }

        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: l("移入回收站"),
            detail: file.fileName,
            source: "DataHealthView.issueAction"
        )
        cleanup.perform()
        store.runDataHealthScanNow(reason: .manual)
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .succeeded,
            summary: issue.title,
            detail: file.fileName,
            source: "DataHealthView.issueAction"
        )
        AppHaptics.success()
        operationNotice = .info(l("已移入回收站，可在存储清理中恢复"))
    }

    func createDataHealthRepairTodo(for issue: DataHealthIssue) {
        let marker = "[data-health-issue:\(issue.id)]"
        let hasDuplicate = store.siteTodos.contains { todo in
            !todo.isDone && todo.note.contains(marker)
        }
        guard !hasDuplicate else {
            AppHaptics.warning()
            operationNotice = .info(l("该问题的专项待办已存在"))
            return
        }

        let todo = SiteTodo(
            title: String(format: l("处理：%@"), issue.title),
            dueDate: .day(CalendarDay(date: Date())),
            priority: .high,
            issueType: .general,
            note: [
                issue.detail,
                marker
            ].filter { !$0.isEmpty }.joined(separator: "\n"),
            projectId: projectId(for: issue.route)
        )
        store.insertSiteTodoAtTop(todo)
        store.scheduleSave()
        AppHaptics.success()
        operationNotice = .info(l("已生成专项待办"))
    }

    private func orphanFileCleanup(for file: DataHealthOrphanFile) -> DataStoreDeferredFileCleanup? {
        switch file.kind {
        case .photo:
            return DataStoreDeferredFileCleanup.photoFiles([file.fileName], summary: "dataHealth.orphanPhoto.single")
        case .drawing:
            return DataStoreDeferredFileCleanup.drawingFiles([file.fileName], summary: "dataHealth.orphanDrawing.single")
        case .projectDocument:
            return DataStoreDeferredFileCleanup.projectDocumentFiles([file.fileName], summary: "dataHealth.orphanProjectDocument.single")
        case .quickNoteAttachment:
            return DataStoreDeferredFileCleanup.quickNoteAttachmentFiles([file.fileName], summary: "dataHealth.orphanQuickNoteAttachment.single")
        }
    }

    private func projectId(for route: DataHealthIssueRoute?) -> UUID? {
        guard let route else { return nil }
        switch route {
        case .project(let projectId, _),
             .financialRecord(let projectId, _),
             .document(let projectId, _),
             .warehouseProject(let projectId):
            return projectId
        case .dailyLog(let projectId, _),
             .siteTodo(let projectId, _):
            return projectId
        case .material, .quote, .labor, .quickNote, .contact:
            return nil
        }
    }
}
