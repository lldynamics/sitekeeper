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
                store.removeProjectDrawings(
                    ids: Set([replacement.id]),
                    deferredFileCleanup: DataStoreDeferredFileCleanup.drawingFiles(
                        [replacement.fileName],
                        summary: "projectDetail.importReplacement"
                    ),
                    recordsAuditImmediately: true
                )
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

            store.appendProjectDrawing(versioned)
            currentDrawings.append(versioned)
            importedCount += 1
        }

        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    var hasDrawingEntries = false
                    try SimpleZipArchiveReader.scan(fileURL: url) { entry, readData, _ in
                        let ext = (entry.path as NSString).pathExtension.lowercased()
                        guard ProjectDrawing.allowedFileExtensions.contains(ext) else { return }
                        hasDrawingEntries = true
                        do {
                            let entryData = try readData()
                            var drawing = try DrawingStorage.saveImportedDataOrThrow(
                                data: entryData,
                                sourceFileName: entry.path,
                                projectId: projectId
                            )
                            drawing.note = ProjectDetailDrawingHelper.packageNote(for: entry.path)
                            importDrawing(drawing)
                        } catch {
                            StorageIssueLog.record("图纸 ZIP 导入失败：\(entry.path)，\(error.localizedDescription)")
                            failedNames.append("\(entry.path)（\(error.localizedDescription)）")
                        }
                    }
                    if !hasDrawingEntries {
                        failedNames.append("\(url.lastPathComponent)（ZIP 内没有可导入的图纸）")
                    }
                } catch {
                    StorageIssueLog.record("图纸 ZIP 读取失败：\(url.lastPathComponent)，\(error.localizedDescription)")
                    failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
                }
                continue
            }

            do {
                let drawing = try DrawingStorage.saveImportedFileOrThrow(from: url, projectId: projectId)
                importDrawing(drawing)
            } catch {
                StorageIssueLog.record("图纸导入失败：\(url.lastPathComponent)，\(error.localizedDescription)")
                failedNames.append("\(url.lastPathComponent)（\(error.localizedDescription)）")
            }
        }

        if importedCount > 0 {
            store.scheduleSave()
        }
        if !failedNames.isEmpty {
            presentImportError("以下文件导入失败：\(failedNames.joined(separator: "、"))")
        } else if importedCount == 0 {
            presentImportError("没有可导入的图纸文件，请选择 DWG / DXF / PDF / ZIP。")
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
            if drawing.fileType.lowercased() == "pdf" {
                assetState.quickLookURL = url
            } else {
                assetState.drawingShareURL = url
            }
        case .failure(let message):
            StorageIssueLog.record("图纸原件打开失败：\(drawing.name.isEmpty ? drawing.fileName : drawing.name)，\(message)")
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
