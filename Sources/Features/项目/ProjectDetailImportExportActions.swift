import Foundation

enum ProjectDetailImportExportActions {
    static var largePackageWarningBytes: Int { TransferLimitPolicy.projectPackageWarningBytes }

    enum PackageSizeDecision: Equatable {
        case normal
        case warn
    }

    static func makeProjectPackageExport(
        project: Project,
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        logs: [DailyLog],
        tasks: [ProgressTask],
        todos: [SiteTodo],
        drawings: [ProjectDrawing],
        contacts: [ProjectContact],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        quickNotes: [QuickNote],
        paidAmountOverride: Double,
        progress: ((ProjectPackageExportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) -> ProjectDetailActionResult<ExportPayload> {
        // 缺失文件已由 ProjectDetailExportWorkflow.packageRequestDecision 前置检查；
        // 此处保留断言以防直接调用此方法时跳过预检。
        assert(
            missingProjectPackageFiles(documents: documents, drawings: drawings, logs: logs, quickNotes: quickNotes).isEmpty,
            "缺失文件应在调用 makeProjectPackageExport 前通过 packageRequestDecision 检查"
        )

        do {
            let zipURL = try ReportBuilder.makeProjectPackageZIP(
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
                paidAmountOverride: paidAmountOverride,
                progress: progress,
                shouldCancel: shouldCancel
            )
            let defaultFilename = "\(project.name)_项目交付包.zip"
            let preparedURL = try ExportFileURLPreparer.prepare(sourceFileURL: zipURL, suggestedFileName: defaultFilename)
            return .success(ExportPayload(fileURL: preparedURL, contentType: .zipArchive, defaultFilename: defaultFilename))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    static func estimatedProjectPackageBytes(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> Int {
        var total = 0
        total += documents.reduce(0) { $0 + ProjectDocumentStorage.fileSize(for: $1.fileName) }
        total += drawings.reduce(0) { $0 + DrawingStorage.fileSize(for: $1.fileName) }
        for photo in logs.flatMap(\.photoAttachments) {
            total += PhotoStorage.fileSize(for: photo.fileName)
        }
        for attachment in quickNotes.flatMap(\.attachments) {
            total += QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
        }
        return total
    }

    static func packageSizeDecision(for bytes: Int) -> PackageSizeDecision {
        if bytes >= largePackageWarningBytes {
            return .warn
        }
        return .normal
    }

    static func formattedBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func missingProjectPackageFiles(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> [String] {
        var issues: [String] = []
        issues += documents.compactMap { document in
            ProjectDocumentStorage.exists(fileName: document.fileName) ? nil : "资料 \(document.title)"
        }
        issues += drawings.compactMap { drawing in
            DrawingStorage.exists(fileName: drawing.fileName) ? nil : "图纸 \(drawing.name)"
        }
        for log in logs {
            for photo in log.photoAttachments where !PhotoStorage.exists(fileName: photo.fileName) {
                issues.append("照片 \(log.date) \(photo.tag.displayName)")
            }
        }
        for note in quickNotes {
            for attachment in note.attachments where !QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
                issues.append("随手记附件 \(note.title.isEmpty ? note.createdAt : note.title)")
            }
        }
        return issues
    }
}
