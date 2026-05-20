import Foundation

extension ReportBuilder {
    static func makeProjectPackageZIP(
        project: Project,
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        logs: [DailyLog],
        tasks: [ProgressTask],
        todos: [SiteTodo],
        drawings: [ProjectDrawing] = [],
        contacts: [ProjectContact] = [],
        financialRecords: [ProjectFinancialRecord] = [],
        documents: [ProjectDocument] = [],
        quickNotes: [QuickNote] = [],
        paidAmountOverride: Double? = nil,
        progress: ((ProjectPackageExportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> URL {
        let totalSteps = estimatedProjectPackageStepCount(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes,
            contacts: contacts
        )
        var completedSteps = 0
        func failIfCancelled() throws {
            if shouldCancel?() == true || Task.isCancelled {
                throw ProjectPackageArchiveError.cancelled
            }
        }
        func reportProgress(_ item: String) {
            completedSteps += 1
            progress?(ProjectPackageExportProgress(completedSteps: completedSteps, totalSteps: totalSteps, currentItem: item))
        }

        try failIfCancelled()
        let packagePDF = makeProjectPackagePDF(
            project: project,
            materials: materials,
            quotes: quotes,
            labor: labor,
            logs: logs,
            tasks: tasks,
            todos: todos,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            quickNotes: quickNotes,
            paidAmountOverride: paidAmountOverride
        )

        let packageURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "project-package")
        var zip = try StreamingZipArchiveWriter(fileURL: packageURL)
        var writerFinished = false
        defer {
            if !writerFinished {
                do {
                    try zip.close()
                } catch {
                    StorageIssueLog.record(locFormat("项目交付包 ZIP 关闭失败：%@，%@", packageURL.lastPathComponent, error.localizedDescription))
                }
                do {
                    _ = try FileOps.removeIfExists(
                        at: packageURL,
                        context: .init(
                            event: "project_package.cleanup_temporary_zip",
                            category: .zipArchive,
                            source: "ReportBuilder.exportProjectPackage"
                        )
                    )
                } catch {
                    StorageIssueLog.record(locFormat("项目交付包临时文件清理失败：%@，%@", packageURL.lastPathComponent, error.localizedDescription))
                }
            }
        }

        let folder = safeZipName(project.name, fallback: "untitled_project")
        let deliveryDirectory = ProjectPackageSchema.deliveryDirectory
        let documentDirectory = ProjectPackageSchema.documentDirectory
        let drawingDirectory = ProjectPackageSchema.drawingDirectory
        let photoDirectory = ProjectPackageSchema.photoDirectory
        let quickNoteDirectory = ProjectPackageSchema.quickNoteDirectory
        let contactDirectory = ProjectPackageSchema.contactDirectory
        let pdfName = ProjectPackageSchema.pdfFileName(folder: folder)
        let checklistFileName = ProjectPackageSchema.checklistFileName
        let deliveryHealth = projectDeliveryHealthReport(
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes
        )
        let documentChecklist = DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: project.requiredDocumentCategories
        )
        let currentDrawings = currentProjectPackageDrawings(drawings)
        let missingDrawingOriginalEntries = projectPackageMissingDrawingEntries(drawings)
        let openDrawingIssues = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos)
        var stagedRawBytes = 0
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: packagePDF,
            path: "\(folder)/\(deliveryDirectory)/\(pdfName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入交付包 PDF"))

        let readme = [
            tsv(["schema_version", ProjectPackageSchema.version]),
            tsv(["package_type", ProjectPackageSchema.type]),
            tsv(["project_name", project.name]),
            tsv(["exported_at", Formatters.now()]),
            tsv(["delivery_health_score", "\(deliveryHealth.score)"]),
            tsv(["delivery_health_verdict", deliveryHealth.machineVerdict]),
            tsv(["delivery_health_verdict_display", deliveryHealth.verdictDisplayName]),
            tsv(["delivery_health_failed_checks", deliveryHealth.failedCheckKeys]),
            tsv(["delivery_health_failed_checks_display", deliveryHealth.failedCheckDisplayText]),
            tsv(["delivery_health_missing_receipts", "\(deliveryHealth.missingReceiptCount)"]),
            tsv(["delivery_health_drawing_count", "\(deliveryHealth.drawingCount)"]),
            tsv(["delivery_health_open_todos", "\(deliveryHealth.openTodoCount)"]),
            tsv(["delivery_health_backup_fresh", deliveryHealth.backupState.isFresh ? "true" : "false"]),
            tsv(["delivery_health_latest_backup_at", deliveryHealth.backupState.latestBackupExportValue]),
            tsv(["delivery_health_missing_originals", "\(deliveryHealth.missingOriginalEntries.count)"]),
            tsv(["drawing_register_current_count", "\(currentDrawings.count)"]),
            tsv(["drawing_original_count", "\(drawings.count)"]),
            tsv(["drawing_missing_original_count", "\(missingDrawingOriginalEntries.count)"]),
            tsv(["drawing_open_issue_count", "\(openDrawingIssues.count)"]),
            tsv(["document_checklist_required_categories", "\(documentChecklist.requiredCount)"]),
            tsv(["document_checklist_covered_categories", "\(documentChecklist.coveredCount)"]),
            tsv(["document_checklist_missing_categories", "\(documentChecklist.missingCount)"]),
            tsv(["document_checklist_action_count", "\(documentChecklist.actionCount)"]),
            tsv(["document_checklist_returned_count", "\(documentChecklist.returnedDocumentCount)"]),
            tsv(["document_checklist_archived_count", "\(documentChecklist.archivedDocumentCount)"]),
            "",
            "[contents]",
            tsv(["path", "kind_raw", "kind_display"]),
            tsv(["\(deliveryDirectory)/\(pdfName)", "project_delivery_pdf", loc("项目交付包 PDF")]),
            tsv(["\(deliveryDirectory)/\(checklistFileName)", "delivery_checklist", loc("交付检查清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)", "document_checklist", loc("施工资料清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)", "current_drawing_register", loc("当前版图纸清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)", "drawing_missing_check", loc("缺失图纸检查")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)", "open_drawing_issues", loc("未关闭图纸问题")]),
            tsv(["\(documentDirectory)/", "source_documents", loc("票据/资料原始文件")]),
            tsv(["\(drawingDirectory)/", "source_drawings", loc("图纸原始文件")]),
            tsv(["\(photoDirectory)/", "source_site_photos", loc("日志和整改照片文件")]),
            tsv(["\(quickNoteDirectory)/", "quick_notes", loc("随手记清单和原始附件")]),
            tsv(["\(contactDirectory)/", "contacts", loc("联系人清单")])
        ].joined(separator: "\n")
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(readme.utf8),
            path: "\(folder)/\(ProjectPackageSchema.readmeFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入说明文件"))

        let checklist = projectDeliveryChecklistText(
            project: project,
            logs: logs,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            todos: todos,
            quickNotes: quickNotes
        )
        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(checklist.utf8),
            path: "\(folder)/\(deliveryDirectory)/\(checklistFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入交付检查清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectDocumentChecklistTSVText(documentChecklist).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入施工资料清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectCurrentDrawingRegisterTSVText(drawings).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入当前版图纸清单"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectDrawingMissingCheckTSVText(drawings).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入缺失图纸检查"))

        try failIfCancelled()
        try addGeneratedFileToProjectPackageZip(
            zip: &zip,
            data: Data(projectOpenDrawingIssuesTSVText(drawings: drawings, todos: todos).utf8),
            path: "\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)",
            stagedRawBytes: &stagedRawBytes
        )
        reportProgress(loc("写入未关闭图纸问题"))

        for document in documents {
            try failIfCancelled()
            let fileBytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            let sourceURL = ProjectDocumentStorage.fileURL(for: document.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                StorageIssueLog.record(locFormat("项目交付包缺少票据原件：%@", document.fileName))
                reportProgress(locFormat("检查票据 %@", document.title))
                continue
            }
            let title = safeZipName(document.title)
            let fileName = document.fileName.lowercased().hasSuffix(".pdf") ? document.fileName : "\(document.fileName).pdf"
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/\(documentDirectory)/\(title)-\(fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(locFormat("打包票据 %@", document.title))
        }

        for drawing in drawings {
            try failIfCancelled()
            let fileBytes = DrawingStorage.fileSize(for: drawing.fileName)
            let sourceURL = DrawingStorage.fileURL(for: drawing.fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                StorageIssueLog.record(locFormat("项目交付包缺少图纸原件：%@", drawing.fileName))
                reportProgress(locFormat("检查图纸 %@", drawing.name))
                continue
            }
            let name = safeZipName(drawing.name)
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: fileBytes,
                path: "\(folder)/\(drawingDirectory)/\(name)-\(drawing.fileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(locFormat("打包图纸 %@", drawing.name))
        }

        for log in logs {
            for photo in log.photoAttachments {
                try failIfCancelled()
                let fileBytes = PhotoStorage.fileSize(for: photo.fileName)
                let sourceURL = PhotoStorage.fileURL(for: photo.fileName)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    StorageIssueLog.record(locFormat("项目交付包缺少现场照片原件：%@", photo.fileName))
                    reportProgress(locFormat("检查照片 %@ %@", log.date, photo.tag.displayName))
                    continue
                }
                let tag = safeZipName(photo.tag.displayName)
                try addStoredFileToProjectPackageZip(
                    zip: &zip,
                    sourceFileURL: sourceURL,
                    fileBytes: fileBytes,
                    path: "\(folder)/\(photoDirectory)/\(log.date)-\(tag)-\(photo.fileName)",
                    stagedRawBytes: &stagedRawBytes
                )
                reportProgress(locFormat("打包照片 %@ %@", log.date, photo.tag.displayName))
            }
        }

        if !quickNotes.isEmpty {
            let header = tsv(["created_at", "content", "attachment_summary_raw", "attachment_summary_display"])
            let lines = quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).map { note in
                let content = QuickNoteText.displayContent(for: note)
                let attachmentSummary = quickNoteAttachmentSummaryColumns(note.attachments)
                return tsv([note.createdAt, content, attachmentSummary.raw, attachmentSummary.display])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + lines).joined(separator: "\n").utf8),
                path: "\(folder)/\(quickNoteDirectory)/\(ProjectPackageSchema.quickNotesFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(loc("写入随手记清单"))
            for note in quickNotes {
                for attachment in note.attachments {
                    try failIfCancelled()
                    let fileBytes = QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
                    let sourceURL = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        StorageIssueLog.record(locFormat("项目交付包缺少随手记附件原件：%@", attachment.fileName))
                        reportProgress(locFormat("检查随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
                        continue
                    }
                    let title = safeZipName(note.title, fallback: "quick_note")
                    let kind = attachment.attachmentKind.rawValue
                    let created = safeZipName(note.createdAt)
                    try addStoredFileToProjectPackageZip(
                        zip: &zip,
                        sourceFileURL: sourceURL,
                        fileBytes: fileBytes,
                        path: "\(folder)/\(quickNoteDirectory)/\(kind)/\(created)-\(title)-\(attachment.fileName)",
                        stagedRawBytes: &stagedRawBytes
                    )
                    reportProgress(locFormat("打包随手记附件 %@", note.title.isEmpty ? note.createdAt : note.title))
                }
            }
        }

        if !contacts.isEmpty {
            let header = tsv(["name", "role_key", "role_display", "company", "phone", "note"])
            let rows = contacts.sorted { $0.name < $1.name }.map {
                tsv([$0.name, $0.normalizedRole.exportKey, $0.roleDisplayName, $0.company, $0.phone, $0.note])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + rows).joined(separator: "\n").utf8),
                path: "\(folder)/\(contactDirectory)/\(ProjectPackageSchema.contactsFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            reportProgress(loc("写入联系人清单"))
        }

        let finishedURL = try zip.finish()
        writerFinished = true
        return finishedURL
    }
}
