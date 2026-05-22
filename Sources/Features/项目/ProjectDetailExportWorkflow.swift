import Foundation

enum ProjectDetailPackageRequestDecision {
    case proceed
    case warn(String)
    case reject(String)
}

enum ProjectDetailPackageExportTaskResult {
    case success(ExportPayload)
    case failure(String)
}

enum ProjectDetailExportWorkflow {
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
        onProgress: @escaping @MainActor (ProjectPackageExportProgress) -> Void,
        onCancelled: @escaping @MainActor () -> Void,
        onCompletion: @escaping @MainActor (ProjectDetailPackageExportTaskResult) -> Void
    ) -> Task<Void, Never> {
        let relatedTodos = todos.filter { $0.projectId == projectId }
        let relay = TaskCancellationRelay()

        return Task {
            let result = await withTaskCancellationHandler {
                await Task.detached(priority: .userInitiated) {
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
                }.value
            } onCancel: {
                relay.cancel()
            }

            guard !Task.isCancelled else {
                await onCancelled()
                return
            }

            switch result {
            case .success(let payload):
                await onCompletion(.success(payload))
            case .failure(let message):
                await onCompletion(.failure(message))
            }
        }
    }
}
