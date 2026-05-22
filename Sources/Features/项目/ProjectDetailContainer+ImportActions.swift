import SwiftUI
import PhotosUI
import UIKit

extension ProjectDetailContainer {
    func scanTarget(for record: ProjectFinancialRecord) -> ProjectScanTarget {
        ProjectScanTarget(
            title: "\(record.category.displayName)-\(record.date)",
            category: ProjectDetailFinanceDocumentHelper.documentCategory(for: record.category),
            amount: record.amount,
            linkedFinancialRecordId: record.id,
            linkedConstructionMethodIDs: [],
            formedAt: record.date,
            note: record.note
        )
    }

    func importDrawings(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let conflictNames = DrawingImportCoordinator.conflictedDrawingNames(for: urls, projectId: projectId, store: store)
        if conflictNames.isEmpty {
            performDrawingImport(urls, strategy: .createNewVersion)
            return
        }
        assetState.pendingDrawingImportURLs = urls
        assetState.drawingImportConflictNames = conflictNames
        assetState.showDrawingImportStrategyDialog = true
    }

    func applyPendingDrawingImportStrategy(_ strategy: ProjectDrawingImportStrategy) {
        let urls = assetState.pendingDrawingImportURLs
        clearPendingDrawingImportStrategy()
        guard !urls.isEmpty else { return }
        performDrawingImport(urls, strategy: strategy)
    }

    func clearPendingDrawingImportStrategy() {
        assetState.pendingDrawingImportURLs.removeAll()
        assetState.drawingImportConflictNames.removeAll()
        assetState.showDrawingImportStrategyDialog = false
    }

    private func performDrawingImport(_ urls: [URL], strategy: ProjectDrawingImportStrategy) {
        let result = DrawingImportCoordinator.importDrawings(
            urls,
            projectId: projectId,
            strategy: strategy,
            store: store,
            replacementCleanupSummary: "projectDetail.importReplacement"
        )
        if result.didImport {
            store.scheduleSave()
        }
        if let message = result.importErrorMessage {
            presentImportError(message)
        }
    }

    func saveScannedDocument(target: ProjectScanTarget, data: Data, pageCount: Int) {
        if let error = ProjectDetailAssetActions.saveScannedDocument(
            target: target,
            data: data,
            pageCount: pageCount,
            projectId: projectId,
            store: store
        ) {
            presentImportError(error)
        }
    }

    func previewDocument(_ document: ProjectDocument) {
        switch ProjectDetailAssetActions.previewDocumentURL(for: document) {
        case .success(let url):
            assetState.quickLookURL = url
        case .failure(let message):
            presentImportError(message)
        }
    }

    func previewDrawing(_ drawing: ProjectDrawing) {
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing, store: store) {
        case .success(let url):
            if drawing.fileType.lowercased() == "pdf" {
                assetState.quickLookURL = url
            } else {
                assetState.drawingShareDrawingID = drawing.id
                assetState.drawingShareURL = url
            }
        case .failure(let message):
            StorageIssueLog.recordEvent(
                "project_detail.drawing_open_source_failed",
                category: .fileStorage,
                details: [
                    "source": "ProjectDetailContainerImportActions.previewDrawing",
                    "drawing_id": drawing.id.uuidString,
                    "drawing_name": drawing.name.isEmpty ? drawing.fileName : drawing.name,
                    "error_message": message
                ]
            )
            presentImportError(message)
        }
    }

    func importProjectDocuments(
        _ urls: [URL],
        linkedFinancialRecordId: UUID? = nil,
        ledgerSettings: ProjectDocumentImportLedgerSettings? = nil
    ) {
        let failures = ProjectDetailAssetActions.importProjectDocuments(
            urls,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            ledgerSettings: ledgerSettings,
            store: store
        )
        if !failures.isEmpty {
            presentImportError("以下资料导入失败：\(failures.joined(separator: "、"))")
        }
    }

    func importPhotoItem(_ item: PhotosPickerItem, linkedFinancialRecordId: UUID? = nil) async {
        let result = await ProjectDetailFinanceDocumentActions.image(from: item)
        await MainActor.run {
            switch result {
            case .success(let image):
                importCapturedImage(image, note: "来源: 相册", linkedFinancialRecordId: linkedFinancialRecordId)
            case .failure(let message):
                presentImportError(message)
            }
        }
    }

    func importCapturedImage(_ image: UIImage, note: String = "来源: 拍照", linkedFinancialRecordId: UUID? = nil) {
        if let error = ProjectDetailAssetActions.importCapturedImage(
            image,
            note: note,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        ) {
            presentImportError(error)
        }
    }

    func presentImportError(_ message: String) {
        assetState.importErrorMessage = message
        assetState.showImportError = true
    }
}
