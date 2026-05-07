import Foundation
import UIKit

@MainActor
enum ProjectDetailAssetActions {
    static func saveScannedDocument(
        target: ProjectScanTarget,
        data: Data,
        pageCount: Int,
        projectId: UUID,
        store: DataStore
    ) -> String? {
        ProjectDetailFinanceDocumentActions.saveScannedDocument(
            target: target,
            data: data,
            pageCount: pageCount,
            projectId: projectId,
            store: store
        )
    }

    static func previewDocumentURL(for document: ProjectDocument) -> ProjectDetailActionResult<URL> {
        ProjectDetailFinanceDocumentActions.previewURL(for: document)
    }

    static func deleteDocument(_ document: ProjectDocument, store: DataStore) {
        ProjectDetailFinanceDocumentActions.deleteDocument(document, store: store)
    }

    static func saveDocumentEdit(_ document: ProjectDocument, store: DataStore) {
        ProjectDetailFinanceDocumentActions.saveDocumentEdit(document, store: store)
    }

    static func importProjectDocuments(
        _ urls: [URL],
        projectId: UUID,
        linkedFinancialRecordId: UUID?,
        store: DataStore
    ) -> [String] {
        ProjectDetailFinanceDocumentActions.importProjectDocuments(
            urls,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        )
    }

    static func importCapturedImage(
        _ image: UIImage,
        note: String,
        projectId: UUID,
        linkedFinancialRecordId: UUID?,
        store: DataStore
    ) -> String? {
        ProjectDetailFinanceDocumentActions.importCapturedImage(
            image,
            note: note,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        )
    }

    static func importAttachmentData(
        _ data: Data,
        fileExtension: String,
        title: String,
        note: String,
        projectId: UUID,
        linkedFinancialRecordId: UUID?,
        store: DataStore
    ) -> String? {
        ProjectDetailFinanceDocumentActions.importAttachmentData(
            data,
            fileExtension: fileExtension,
            title: title,
            note: note,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        )
    }

    static func saveDrawing(_ updated: ProjectDrawing, store: DataStore) {
        if let index = store.projectDrawings.firstIndex(where: { $0.id == updated.id }) {
            var value = updated
            value.version = ProjectDetailDrawingHelper.normalizedVersion(value.version)
            if value.isCurrentVersion {
                updateCurrentVersionFlags(for: value, store: store)
            }
            store.projectDrawings[index] = value
            store.scheduleSave()
        }
    }

    static func setDrawingAsCurrentVersion(_ drawing: ProjectDrawing, store: DataStore) {
        var updated = drawing
        updated.isCurrentVersion = true
        saveDrawing(updated, store: store)
    }

    static func previewDrawingURL(for drawing: ProjectDrawing) -> ProjectDetailActionResult<URL> {
        let url = DrawingStorage.fileURL(for: drawing.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure("图纸文件不存在，可能已被清理。")
        }
        return .success(url)
    }

    static func deleteDrawing(_ drawing: ProjectDrawing, store: DataStore) {
        DrawingStorage.delete(fileName: drawing.fileName)
        store.projectDrawings.removeAll { $0.id == drawing.id }
        store.scheduleSave()
    }

    static func timelineDrawings(name: String, relatedDrawings: [ProjectDrawing]) -> [ProjectDrawing] {
        relatedDrawings
            .filter { $0.name == name }
            .sorted { lhs, rhs in
                let lv = ProjectDetailDrawingHelper.versionNumber(lhs.version) ?? 0
                let rv = ProjectDetailDrawingHelper.versionNumber(rhs.version) ?? 0
                if lv == rv {
                    return lhs.importedAt > rhs.importedAt
                }
                return lv > rv
            }
    }

    static func updateCurrentVersionFlags(for drawing: ProjectDrawing, store: DataStore) {
        for index in store.projectDrawings.indices {
            if store.projectDrawings[index].projectId == drawing.projectId,
               store.projectDrawings[index].name == drawing.name,
               store.projectDrawings[index].id != drawing.id {
                store.projectDrawings[index].isCurrentVersion = false
            }
        }
    }
}
