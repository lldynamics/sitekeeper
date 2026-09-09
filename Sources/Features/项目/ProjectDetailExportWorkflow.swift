import Foundation
import UniformTypeIdentifiers

enum ProjectDetailPackageRequestDecision {
    case proceed
    case warn(String)
    case reject(String)
}

enum ProjectDetailPackageExportTaskResult: Sendable {
    case success(ExportPayload)
    case failure(String)
}

enum ProjectDetailExportWorkflow {
    static func makePreDeliveryInspectionPayload(
        project: Project,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        todos: [SiteTodo],
        logs: [DailyLog],
        quickNotes: [QuickNote],
        backupState: ReportBuilder.ProjectDeliveryPackageBackupState = .current()
    ) -> ExportPayload {
        let rows = ReportBuilder.projectPreDeliveryInspectionRows(
            project: project,
            financialRecords: financialRecords,
            documents: documents,
            drawings: drawings,
            todos: todos,
            logs: logs,
            quickNotes: quickNotes,
            backupState: backupState
        )
        let header = [
            String(localized: "project.preDeliveryInspection.export.column.check"),
            String(localized: "project.preDeliveryInspection.export.column.status"),
            String(localized: "project.preDeliveryInspection.export.column.severity"),
            String(localized: "project.preDeliveryInspection.export.column.objectType"),
            String(localized: "project.preDeliveryInspection.export.column.object"),
            String(localized: "project.preDeliveryInspection.export.column.owner"),
            String(localized: "project.preDeliveryInspection.export.column.dueDate"),
            String(localized: "project.preDeliveryInspection.export.column.fileName"),
            String(localized: "project.preDeliveryInspection.export.column.detail"),
            String(localized: "project.preDeliveryInspection.export.column.action")
        ]
        let bodyLines = rows.map { row in
            ReportBuilder.tsv([
                row.checkDisplay,
                row.statusDisplay,
                preDeliveryInspectionSeverityDisplay(row.severity),
                preDeliveryInspectionObjectTypeDisplay(row.objectType),
                row.objectName,
                row.owner,
                row.dueDate,
                row.fileName,
                row.detail,
                row.recommendedAction
            ])
        }
        let summaryLines = [
            ReportBuilder.tsv([String(localized: "project.preDeliveryInspection.export.meta.project"), project.name]),
            ReportBuilder.tsv([String(localized: "project.preDeliveryInspection.export.meta.exportedAt"), Formatters.now()]),
            ""
        ]
        let content = summaryLines + [ReportBuilder.tsv(header)] + bodyLines
        let safeProjectName = ReportBuilder.safeZipName(project.name, fallback: "untitled_project")
        let defaultFilename = String(
            format: String(localized: "project.preDeliveryInspection.export.filename.format"),
            safeProjectName,
            Formatters.date.string(from: Date())
        )

        return ExportPayload(
            data: Data(("\u{FEFF}" + content.joined(separator: "\n")).utf8),
            contentType: .tabSeparatedText,
            defaultFilename: defaultFilename
        )
    }

    static func packageRequestDecision(
        documents: [ProjectDocument],
        drawings: [ProjectDrawing],
        logs: [DailyLog],
        quickNotes: [QuickNote]
    ) -> ProjectDetailPackageRequestDecision {
        // ① 先检查缺失文件（阻断性错误，让用户第一时间看到）
        let missingFiles = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )
        if !missingFiles.isEmpty {
            let preview = missingFiles.prefix(8).joined(separator: String(localized: "、"))
            let more = missingFiles.count > 8
                ? String(
                    format: String(localized: " 等 %lld 项"),
                    Int64(missingFiles.count)
                )
                : ""
            return .reject(
                String(
                    format: String(localized: "交付包存在缺失原件：%@%@。请先到数据健康检查处理后再导出。"),
                    preview,
                    more
                )
            )
        }

        // ② 再检查体积（警告性，不阻断）
        let estimatedBytes = ProjectDetailImportExportActions.estimatedProjectPackageBytes(
            documents: documents,
            drawings: drawings,
            logs: logs,
            quickNotes: quickNotes
        )
        switch ProjectDetailImportExportActions.packageSizeDecision(for: estimatedBytes) {
        case .normal:
            return .proceed
        case .warn:
            return .warn(
                String(
                    format: String(localized: "预计原始附件约 %@。导出不设体积上限，会使用 ZIP64 流式打包；大照片、视频和图纸原件会增加导出时间，并需要设备有足够剩余空间。"),
                    ProjectDetailImportExportActions.formattedBytes(estimatedBytes)
                )
            )
        }
    }

    private static func preDeliveryInspectionSeverityDisplay(_ rawValue: String) -> String {
        switch rawValue {
        case "blocker":
            return String(localized: "project.preDeliveryInspection.export.severity.blocker")
        case "warning":
            return String(localized: "project.preDeliveryInspection.export.severity.warning")
        case "ok":
            return String(localized: "project.preDeliveryInspection.export.severity.ok")
        default:
            return rawValue
        }
    }

    private static func preDeliveryInspectionObjectTypeDisplay(_ rawValue: String) -> String {
        switch rawValue {
        case "project":
            return String(localized: "project.preDeliveryInspection.export.object.project")
        case "drawing":
            return String(localized: "project.preDeliveryInspection.export.object.drawing")
        case "todo":
            return String(localized: "project.preDeliveryInspection.export.object.todo")
        case "financial_record":
            return String(localized: "project.preDeliveryInspection.export.object.financialRecord")
        case "drawing_group":
            return String(localized: "project.preDeliveryInspection.export.object.drawingGroup")
        default:
            return rawValue
        }
    }

    @MainActor
    static func makeProjectPackageExportTask(
        project: Project,
        projectId: UUID,
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
        onProgress: @escaping @MainActor @Sendable (ProjectPackageExportProgress) -> Void,
        onCancelled: @escaping @MainActor @Sendable () -> Void,
        onCompletion: @escaping @MainActor @Sendable (ProjectDetailPackageExportTaskResult) -> Void
    ) -> Task<Void, Never> {
        let relatedTodos = todos.filter { $0.projectId == projectId }

        return Task {
            do {
                let result = try await FileIOTaskRunner.runWithRelay(
                    priority: .userInitiated,
                    logContext: .init(
                        event: "project.package_export",
                        source: "ProjectDetailExportWorkflow.makeProjectPackageExportTask",
                        category: .zipArchive,
                        details: [
                            "project_id": projectId.uuidString
                        ]
                    )
                ) { relay in
                    ProjectDetailImportExportActions.makeProjectPackageExport(
                        project: project,
                        materials: materials,
                        quotes: quotes,
                        labor: labor,
                        logs: logs,
                        tasks: tasks,
                        todos: relatedTodos,
                        drawings: drawings,
                        contacts: contacts,
                        financialRecords: financialRecords,
                        documents: documents,
                        quickNotes: quickNotes,
                        paidAmountOverride: paidAmountOverride,
                        progress: { progress in
                            Task { @MainActor in
                                onProgress(progress)
                            }
                        },
                        shouldCancel: { relay.isCancelled() || Task.isCancelled }
                    )
                }

                guard !Task.isCancelled else {
                    onCancelled()
                    return
                }

                switch result {
                case .success(let payload):
                    onCompletion(.success(payload))
                case .failure(let message):
                    onCompletion(.failure(message))
                }
            } catch {
                onCancelled()
            }
        }
    }
}
