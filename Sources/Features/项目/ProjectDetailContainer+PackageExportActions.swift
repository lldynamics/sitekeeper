import SwiftUI

extension ProjectDetailContainer {
    func requestExportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        switch ProjectDetailExportWorkflow.packageRequestDecision(
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        ) {
        case .proceed:
            exportProjectPackage(project, snapshot: snapshot)
        case .warn(let warningMessage):
            exportState.pendingPackageProject = project
            exportState.packageSizeWarningMessage = warningMessage
            exportState.showPackageSizeWarning = true
        case .reject(let errorMessage):
            presentImportError(errorMessage)
        }
    }

    func exportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        exportState.projectPackageExportTask?.cancel()
        exportState.isExportingProjectPackage = true
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")

        exportState.projectPackageExportTask = ProjectDetailExportWorkflow.makeProjectPackageExportTask(
            project: project,
            projectId: projectId,
            materials: snapshot.relatedMaterials,
            quotes: snapshot.relatedQuotes,
            labor: snapshot.relatedLabor,
            logs: snapshot.relatedLogs,
            tasks: snapshot.relatedProgress,
            todos: snapshot.relatedTodos,
            drawings: snapshot.relatedDrawings,
            contacts: snapshot.relatedContacts,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            quickNotes: snapshot.relatedQuickNotes,
            paidAmountOverride: paidAmount(project, snapshot: snapshot),
            onProgress: { progress in
                exportState.projectPackageExportProgress = progress
            },
            onCancelled: {
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
            },
            onCompletion: { result in
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
                switch result {
                case .success(let payload):
                    exportState.exportPayload = payload
                    exportState.showExporter = true
                case .failure(let message):
                    if message != ProjectPackageArchiveError.cancelled.localizedDescription {
                        presentImportError(message)
                    }
                }
            }
        )
    }

    func exportPreDeliveryInspection(_ project: Project, snapshot: ProjectDetailSnapshot) {
        exportState.exportPayload = ProjectDetailExportWorkflow.makePreDeliveryInspectionPayload(
            project: project,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            todos: snapshot.relatedTodos,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        )
        exportState.showExporter = true
    }

    func cancelProjectPackageExport() {
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(
            completedSteps: exportState.projectPackageExportProgress.completedSteps,
            totalSteps: max(exportState.projectPackageExportProgress.totalSteps, 1),
            currentItem: "正在取消..."
        )
        exportState.projectPackageExportTask?.cancel()
    }

    private func paidAmount(_ project: Project, snapshot: ProjectDetailSnapshot) -> Double {
        ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
    }
}
