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
        guard !urls.isEmpty else { return }
        let currentDrawings = projectStore.projectDrawings.filter { $0.projectId == projectId }
        let conflictNames = ProjectDetailDrawingHelper.conflictedDrawingNames(for: urls, in: currentDrawings)
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
        var importedCount = 0
        var failedNames: [String] = []
        var currentDrawings = projectStore.projectDrawings.filter { $0.projectId == projectId }

        func importDrawing(_ drawing: ProjectDrawing) {
            var versioned = drawing
            let resolved = ProjectDetailDrawingHelper.resolvedImportMetadata(
                for: drawing,
                in: currentDrawings,
                strategy: strategy
            )
            versioned.version = resolved.version
            versioned.isCurrentVersion = resolved.isCurrentVersion

            if let replacement = resolved.replacement {
                DrawingStorage.delete(fileName: replacement.fileName)
                store.projectDrawings.removeAll { $0.id == replacement.id }
                currentDrawings.removeAll { $0.id == replacement.id }
            }

            if strategy == .createNewVersion && versioned.isCurrentVersion {
                ProjectDetailAssetActions.updateCurrentVersionFlags(for: versioned, store: store)
                for index in currentDrawings.indices where currentDrawings[index].projectId == versioned.projectId {
                    if ProjectDetailDrawingHelper.normalizedDrawingNameKey(currentDrawings[index].name) ==
                        ProjectDetailDrawingHelper.normalizedDrawingNameKey(versioned.name),
                       currentDrawings[index].id != versioned.id {
                        currentDrawings[index].isCurrentVersion = false
                    }
                }
            }

            store.projectDrawings.append(versioned)
            currentDrawings.append(versioned)
            relinkDrawingFamily(forName: versioned.name, drawings: &currentDrawings)
            importedCount += 1
        }

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    let archiveData = try Data(contentsOf: url, options: [.mappedIfSafe])
                    let entries = try SimpleZipArchiveReader.read(archiveData)
                    let drawingEntries = entries.filter { entry in
                        let ext = (entry.path as NSString).pathExtension.lowercased()
                        return ProjectDrawing.allowedFileExtensions.contains(ext)
                    }
                    if drawingEntries.isEmpty {
                        failedNames.append("\(url.lastPathComponent)（ZIP 内没有可导入的图纸）")
                        continue
                    }
                    for entry in drawingEntries {
                        do {
                            let drawing = try DrawingStorage.saveImportedDataOrThrow(
                                data: entry.data,
                                sourceFileName: entry.path,
                                projectId: projectId
                            )
                            importDrawing(drawing)
                        } catch {
                            failedNames.append("\(entry.path)（\(error.localizedDescription)）")
                        }
                    }
                } catch {
                    failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
                }
                continue
            }

            do {
                let drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
                importDrawing(drawing)
            } catch {
                failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
            }
        }

        if importedCount > 0 {
            store.scheduleSave()
        }
        if !failedNames.isEmpty {
            presentImportError("以下文件导入失败：\(failedNames.joined(separator: "、"))")
        } else if importedCount == 0 {
            presentImportError("没有可导入的图纸文件，请选择 PDF / DWG / DXF / ZIP。")
        }
    }

    private func relinkDrawingFamily(forName drawingName: String, drawings: inout [ProjectDrawing]) {
        let nameKey = ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawingName)
        guard !nameKey.isEmpty else { return }
        for index in drawings.indices {
            guard drawings[index].projectId == projectId else { continue }
            guard ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawings[index].name) == nameKey else { continue }
            guard ProjectDetailDrawingHelper.isCADSource(drawings[index].fileType) else { continue }
            let linkedID = ProjectDetailDrawingHelper.matchingRenderablePreview(for: drawings[index], in: drawings)?.id
            if drawings[index].linkedPreviewDrawingID != linkedID {
                drawings[index].linkedPreviewDrawingID = linkedID
                if let storeIndex = store.projectDrawings.firstIndex(where: { $0.id == drawings[index].id }) {
                    store.projectDrawings[storeIndex].linkedPreviewDrawingID = linkedID
                }
            }
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
        let previewTarget = ProjectDetailDrawingHelper.matchingRenderablePreview(
            for: drawing,
            in: projectStore.projectDrawings
        ) ?? drawing
        switch ProjectDetailAssetActions.previewDrawingURL(for: previewTarget) {
        case .success(let url):
            assetState.cadPreviewRequest = ProjectCADPreviewRequest(
                drawingID: previewTarget.id,
                fileURL: url,
                displayName: previewTarget.name.isEmpty ? previewTarget.fileName : previewTarget.name,
                fileType: previewTarget.fileType,
                textEncoding: previewTarget.textEncoding,
                overlaySnapshotData: previewTarget.cadOverlaySnapshotData,
                onOverlaySnapshotChange: { drawingID, snapshotData in
                    updateDrawingOverlaySnapshot(drawingID: drawingID, snapshotData: snapshotData)
                },
                onTextEncodingChange: { drawingID, encoding in
                    updateDrawingTextEncoding(drawingID: drawingID, encoding: encoding)
                }
            )
        case .failure(let message):
            presentImportError(message)
        }
    }

    func updateDrawingOverlaySnapshot(drawingID: UUID, snapshotData: String) {
        guard let index = projectStore.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
        store.projectDrawings[index].cadOverlaySnapshotData = snapshotData
        store.scheduleSave()
    }

    func updateDrawingTextEncoding(drawingID: UUID, encoding: CADDrawingTextEncoding) {
        guard let index = projectStore.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
        store.projectDrawings[index].textEncoding = encoding
        store.scheduleSave()
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
