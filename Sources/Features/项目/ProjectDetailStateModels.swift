import Foundation
import SwiftUI

@MainActor
final class ProjectDetailExportStateModel: ObservableObject {
    @Published var exportPayload: ExportPayload?
    @Published var showExporter = false
    @Published var pendingPackageProject: Project?
    @Published var packageSizeWarningMessage = ""
    @Published var showPackageSizeWarning = false
    @Published var projectPackageExportTask: Task<Void, Never>?
    @Published var isExportingProjectPackage = false
    @Published var projectPackageExportProgress = ProjectPackageExportProgress(
        completedSteps: 0,
        totalSteps: 1,
        currentItem: "准备导出"
    )

    func cancelExportTask() {
        projectPackageExportTask?.cancel()
        projectPackageExportTask = nil
        isExportingProjectPackage = false
    }
}
