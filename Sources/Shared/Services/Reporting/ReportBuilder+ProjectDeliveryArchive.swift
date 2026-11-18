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
        paidAmountOverride: MoneyValue? = nil,
        progress: ((ProjectPackageExportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> URL {
        let sourceReferences = projectPackageSourceReferences(
            documents: documents, drawings: drawings, logs: logs,
            quickNotes: quickNotes, todos: todos
        )
        // Missing files remain reportable; unsafe metadata or a link/directory
        // target stops the export before reports or temporary files are generated.
        for reference in sourceReferences { _ = try reference.validatedFileURL() }
        let totalSteps = estimatedProjectPackageStepCount(
            sourceReferenceCount: sourceReferences.count,
            hasQuickNotes: !quickNotes.isEmpty,
            hasContacts: !contacts.isEmpty
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
        func recordPackageIssue(
            _ event: String,
            details: [String: String] = [:],
            error: Error? = nil
        ) {
            var payload = details
            payload["source"] = "ReportBuilder.makeProjectPackageZIP"
            payload["project_id"] = project.id.uuidString
            payload["project_name"] = project.name
            StorageIssueLog.recordEvent(
                event,
                category: .zipArchive,
                details: payload,
                error: error
            )
        }

        try failIfCancelled()
        let packagePDF = ReportBuilder.makeProjectPackagePDF(
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
                cleanupIncompleteProjectPackageZip(&zip, at: packageURL, recordIssue: recordPackageIssue)
            }
        }

        let folder = safeZipName(project.name, fallback: "untitled_project")
        let context = ProjectPackageStageContext(
            project: project,
            folder: folder,
            failIfCancelled: failIfCancelled,
            reportProgress: reportProgress,
            recordPackageIssue: recordPackageIssue
        )
        var stagedRawBytes = 0
        try writeProjectPackageGeneratedReports(
            zip: &zip,
            stagedRawBytes: &stagedRawBytes,
            context: context,
            packagePDF: packagePDF,
            logs: logs,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            todos: todos,
            quickNotes: quickNotes
        )
        try writeProjectPackageStoredAssets(
            zip: &zip,
            stagedRawBytes: &stagedRawBytes,
            context: context,
            references: sourceReferences
        )
        try writeProjectPackageQuickNotesAndContacts(
            zip: &zip,
            stagedRawBytes: &stagedRawBytes,
            context: context,
            quickNotes: quickNotes,
            contacts: contacts
        )

        let finishedURL = try zip.finish()
        writerFinished = true
        return finishedURL
    }

    private struct ProjectPackageStageContext {
        let project: Project
        let folder: String
        let failIfCancelled: () throws -> Void
        let reportProgress: (String) -> Void
        let recordPackageIssue: (String, [String: String], Error?) -> Void
    }

    private static func cleanupIncompleteProjectPackageZip(
        _ zip: inout StreamingZipArchiveWriter,
        at packageURL: URL,
        recordIssue: (String, [String: String], Error?) -> Void
    ) {
        do {
            try zip.close()
        } catch {
            recordIssue("project_package.close_zip_failed", ["archive_file": packageURL.lastPathComponent], error)
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
            recordIssue("project_package.cleanup_temporary_zip_failed", ["archive_file": packageURL.lastPathComponent], error)
        }
    }

    private static func makeProjectPackageReadmeText(
        project: Project,
        deliveryHealth: ProjectDeliveryPackageHealthReport,
        documentChecklist: DocumentArchiveChecklistSnapshot,
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        pdfName: String
    ) -> String {
        let deliveryDirectory = ProjectPackageSchema.deliveryDirectory
        let currentDrawings = currentProjectPackageDrawings(drawings)
        let missingDrawingOriginalEntries = projectPackageMissingDrawingEntries(drawings)
        let openDrawingIssues = projectPackageOpenDrawingIssueRows(drawings: drawings, todos: todos)
        return [
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
            tsv(["delivery_health_drawing_without_current_count", "\(deliveryHealth.drawingGroupsWithoutCurrent.count)"]),
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
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.checklistFileName)", "delivery_checklist", loc("交付检查清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.preDeliveryInspectionFileName)", "pre_delivery_inspection", loc("交付前体检明细")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)", "document_checklist", loc("施工资料清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)", "current_drawing_register", loc("当前版图纸清单")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)", "drawing_missing_check", loc("缺失图纸检查")]),
            tsv(["\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)", "open_drawing_issues", loc("未关闭图纸问题")]),
            tsv(["\(ProjectPackageSchema.documentDirectory)/", "source_documents", loc("票据/资料原始文件")]),
            tsv(["\(ProjectPackageSchema.drawingDirectory)/", "source_drawings", loc("图纸原始文件")]),
            tsv(["\(ProjectPackageSchema.photoDirectory)/", "source_site_photos", loc("日志和整改照片文件")]),
            tsv(["\(ProjectPackageSchema.quickNoteDirectory)/", "quick_notes", loc("随手记清单和原始附件")]),
            tsv(["\(ProjectPackageSchema.contactDirectory)/", "contacts", loc("联系人清单")])
        ].joined(separator: "\n")
    }

    private static func writeProjectPackageGeneratedReports(
        zip: inout StreamingZipArchiveWriter,
        stagedRawBytes: inout Int,
        context: ProjectPackageStageContext,
        packagePDF: Data,
        logs: [DailyLog],
        drawings: [ProjectDrawing],
        contacts: [ProjectContact],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        todos: [SiteTodo],
        quickNotes: [QuickNote]
    ) throws {
        let folder = context.folder
        let deliveryDirectory = ProjectPackageSchema.deliveryDirectory
        let pdfName = ProjectPackageSchema.pdfFileName(folder: folder)
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
            requiredCategories: context.project.requiredDocumentCategories
        )
        let preDeliveryInspection = projectPreDeliveryInspectionTSVText(
            project: context.project,
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes,
            backupState: deliveryHealth.backupState
        )
        let readme = makeProjectPackageReadmeText(
            project: context.project,
            deliveryHealth: deliveryHealth,
            documentChecklist: documentChecklist,
            drawings: drawings,
            todos: todos,
            pdfName: pdfName
        )
        let checklist = projectDeliveryChecklistText(
            project: context.project,
            logs: logs,
            drawings: drawings,
            contacts: contacts,
            financialRecords: financialRecords,
            documents: documents,
            todos: todos,
            quickNotes: quickNotes
        )
        let entries: [(path: String, data: Data, label: String)] = [
            ("\(folder)/\(deliveryDirectory)/\(pdfName)", packagePDF, loc("写入交付包 PDF")),
            ("\(folder)/\(ProjectPackageSchema.readmeFileName)", Data(readme.utf8), loc("写入说明文件")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.checklistFileName)", Data(checklist.utf8), loc("写入交付检查清单")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.preDeliveryInspectionFileName)", Data(preDeliveryInspection.utf8), loc("写入交付前体检明细")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.documentChecklistFileName)", Data(projectDocumentChecklistTSVText(documentChecklist).utf8), loc("写入施工资料清单")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.currentDrawingRegisterFileName)", Data(projectCurrentDrawingRegisterTSVText(drawings).utf8), loc("写入当前版图纸清单")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.drawingMissingCheckFileName)", Data(projectDrawingMissingCheckTSVText(drawings).utf8), loc("写入缺失图纸检查")),
            ("\(folder)/\(deliveryDirectory)/\(ProjectPackageSchema.openDrawingIssuesFileName)", Data(projectOpenDrawingIssuesTSVText(drawings: drawings, todos: todos).utf8), loc("写入未关闭图纸问题"))
        ]
        for entry in entries {
            try context.failIfCancelled()
            try addGeneratedFileToProjectPackageZip(zip: &zip, data: entry.data, path: entry.path, stagedRawBytes: &stagedRawBytes)
            context.reportProgress(entry.label)
        }
    }

    private static func writeProjectPackageStoredAssets(
        zip: inout StreamingZipArchiveWriter,
        stagedRawBytes: inout Int,
        context: ProjectPackageStageContext,
        references: [ProjectPackageSourceReference]
    ) throws {
        for reference in references {
            try context.failIfCancelled()
            let sourceURL = try reference.validatedFileURL()
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                context.recordPackageIssue("project_package.missing_original_file", reference.issueDetails, nil)
                context.reportProgress(reference.checkProgress)
                continue
            }
            try addStoredFileToProjectPackageZip(
                zip: &zip,
                sourceFileURL: sourceURL,
                fileBytes: reference.fileBytes,
                path: "\(context.folder)/\(reference.archivePath)",
                stagedRawBytes: &stagedRawBytes
            )
            context.reportProgress(reference.writeProgress)
        }
    }

    private static func writeProjectPackageQuickNotesAndContacts(
        zip: inout StreamingZipArchiveWriter,
        stagedRawBytes: inout Int,
        context: ProjectPackageStageContext,
        quickNotes: [QuickNote],
        contacts: [ProjectContact]
    ) throws {
        let folder = context.folder
        if !quickNotes.isEmpty {
            let header = tsv(["created_at", "content", "attachment_summary_raw", "attachment_summary_display"])
            let lines = quickNotes.sorted(by: { $0.createdAt > $1.createdAt }).map { note in
                let content = QuickNoteText.displayContent(for: note)
                let attachmentSummary = quickNoteAttachmentSummaryColumns(note.attachments)
                return tsv([note.createdAt.storageText, content, attachmentSummary.raw, attachmentSummary.display])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + lines).joined(separator: "\n").utf8),
                path: "\(folder)/\(ProjectPackageSchema.quickNoteDirectory)/\(ProjectPackageSchema.quickNotesFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            context.reportProgress(loc("写入随手记清单"))
        }

        if !contacts.isEmpty {
            let header = tsv(["name", "role_key", "role_display", "company", "phone", "note"])
            let rows = contacts.sorted { $0.name < $1.name }.map {
                tsv([$0.name, $0.normalizedRole.exportKey, $0.roleDisplayName, $0.company, $0.phone, $0.note])
            }
            try addGeneratedFileToProjectPackageZip(
                zip: &zip,
                data: Data(([header] + rows).joined(separator: "\n").utf8),
                path: "\(folder)/\(ProjectPackageSchema.contactDirectory)/\(ProjectPackageSchema.contactsFileName)",
                stagedRawBytes: &stagedRawBytes
            )
            context.reportProgress(loc("写入联系人清单"))
        }
    }
}
