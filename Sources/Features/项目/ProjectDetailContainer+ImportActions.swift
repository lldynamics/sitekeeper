import SwiftUI
import PhotosUI
import UIKit

extension ProjectDetailView {
    func scanTarget(for record: ProjectFinancialRecord) -> ProjectScanTarget {
        ProjectScanTarget(
            title: "\(record.category.displayName)-\(record.date)",
            category: ProjectDetailFinanceDocumentHelper.documentCategory(for: record.category),
            amount: record.amount,
            linkedFinancialRecordId: record.id,
            linkedConstructionMethodIDs: [],
            note: record.note
        )
    }

    func importDrawings(_ urls: [URL]) {
        var importedCount = 0
        var failedNames: [String] = []
        var currentDrawings = projectStore.projectDrawings.filter { $0.projectId == projectId }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
                failedNames.append(url.lastPathComponent)
                continue
            }

            let drawing: ProjectDrawing
            do {
                drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
            } catch {
                failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
                continue
            }

            let nextVersion = ProjectDetailDrawingHelper.nextDrawingVersion(name: drawing.name, drawings: currentDrawings)
            var versioned = drawing
            versioned.version = nextVersion
            versioned.isCurrentVersion = true
            ProjectDetailAssetActions.updateCurrentVersionFlags(for: versioned, store: store)
            store.projectDrawings.append(versioned)
            currentDrawings.append(versioned)
            importedCount += 1
        }

        if importedCount > 0 {
            store.scheduleSave()
        }
        if !failedNames.isEmpty {
            presentImportError("以下文件导入失败：\(failedNames.joined(separator: "、"))")
        } else if importedCount == 0 {
            presentImportError("没有可导入的图纸文件，请选择 PDF / DWG / DXF。")
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
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing) {
        case .success(let url):
            assetState.quickLookURL = url
        case .failure(let message):
            presentImportError(message)
        }
    }

    func importProjectDocuments(_ urls: [URL], linkedFinancialRecordId: UUID? = nil) {
        let failures = ProjectDetailAssetActions.importProjectDocuments(
            urls,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
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
