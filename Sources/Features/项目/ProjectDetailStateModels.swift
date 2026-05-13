import Foundation
import Observation
import SwiftUI
import PhotosUI
import UIKit

@MainActor
@Observable
final class ProjectDetailExportStateModel {
    var exportPayload: ExportPayload?
    var showExporter = false
    var pendingPackageProject: Project?
    var packageSizeWarningMessage = ""
    var showPackageSizeWarning = false
    var projectPackageExportTask: Task<Void, Never>?
    var isExportingProjectPackage = false
    var projectPackageExportProgress = ProjectPackageExportProgress(
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

struct ProjectDetailFinanceState {
    var financialAddSeed: ProjectFinancialRecord?
    var editingFinancialRecord: ProjectFinancialRecord?
    var attachmentManagingRecord: ProjectFinancialRecord?
    var showFinancialDeleteConfirm = false
    var pendingDeleteFinancialRecordIDs: Set<UUID> = []
}

struct ProjectDetailAssetState {
    var showDocumentFileImporter = false
    var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    var selectedPhotoItem: PhotosPickerItem?
    var editingDrawing: ProjectDrawing?
    var editingDocument: ProjectDocument?
    var editingContact: ProjectContact?
    var timelineContext: DrawingTimelineContext?
    var selectedPhotoContext: ProjectPhotoContext?
    var quickLookURL: URL?
    var cadPreviewRequest: ProjectCADPreviewRequest?
    var showDrawingImporter = false
    var pendingDrawingImportURLs: [URL] = []
    var drawingImportConflictNames: [String] = []
    var showDrawingImportStrategyDialog = false
    var scanTarget: ProjectScanTarget?
    var importErrorMessage = ""
    var showImportError = false
}
