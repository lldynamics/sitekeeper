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
        paidAmountOverride: MoneyValue,
        progress: ((ProjectPackageExportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) -> ProjectDetailActionResult<ExportPayload> {
        // 缺失文件已由 ProjectDetailExportWorkflow.packageRequestDecision 前置检查；
        // 此处保留断言以防直接调用此方法时跳过预检。
        assert(
            missingProjectPackageFiles(documents: documents, drawings: drawings, logs: logs, quickNotes: quickNotes, todos: todos).isEmpty,
            "Missing files must be checked by packageRequestDecision before makeProjectPackageExport is called."
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
            let defaultFilename = ReportBuilder.projectPackageArchiveFileName(projectName: project.name)
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
        quickNotes: [QuickNote],
        todos: [SiteTodo] = []
    ) -> Int {
        ReportBuilder.projectPackageSourceReferences(
            documents: documents, drawings: drawings, logs: logs, quickNotes: quickNotes, todos: todos
        ).reduce(0) { $0 + $1.fileBytes }
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
        quickNotes: [QuickNote],
        todos: [SiteTodo] = []
    ) -> [String] {
        ReportBuilder.projectPackageMissingOriginalEntries(
            documents: documents, drawings: drawings, logs: logs, quickNotes: quickNotes, todos: todos
        )
    }
}
