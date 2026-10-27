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
        ledgerSettings: ProjectDocumentImportLedgerSettings? = nil,
        store: DataStore
    ) -> [String] {
        ProjectDetailFinanceDocumentActions.importProjectDocuments(
            urls,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            ledgerSettings: ledgerSettings,
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
        if store.projectDrawings.contains(where: { $0.id == updated.id }) {
            var value = updated
            value.version = ProjectDetailDrawingHelper.normalizedVersion(value.version)
            if value.isCurrentVersion {
                updateCurrentVersionFlags(for: value, store: store)
            }
            store.updateProjectDrawing(value)
            store.scheduleSave()
        }
    }

    static func setDrawingAsCurrentVersion(_ drawing: ProjectDrawing, store: DataStore) {
        var updated = drawing
        updated.isCurrentVersion = true
        saveDrawing(updated, store: store)
    }

    static func previewDrawingURL(for drawing: ProjectDrawing, store: DataStore? = nil) -> ProjectDetailActionResult<URL> {
        let url = DrawingStorage.fileURL(for: drawing.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            let message = AppLocalization.string("图纸文件不存在，可能已被清理。")
            if let store {
                recordDrawingOpenFailure(
                    drawingID: drawing.id,
                    availabilityStatus: .missing,
                    reason: ProjectDetailDrawingHelper.requiresExternalViewer(drawing.fileType) ? message : "",
                    store: store
                )
            }
            return .failure(message)
        }
        if let store {
            recordDrawingFileAvailable(drawingID: drawing.id, clearExternalFailure: false, store: store)
        }
        return .success(url)
    }

    static func recordDrawingExternalOpenResult(completed: Bool, drawingID: UUID?, store: DataStore) {
        guard let drawingID else { return }
        if completed {
            recordDrawingFileAvailable(drawingID: drawingID, clearExternalFailure: true, store: store)
        } else {
            recordDrawingOpenFailure(
                drawingID: drawingID,
                availabilityStatus: .available,
                reason: AppLocalization.string("外部打开未完成，可能是未选择外部专业看图软件或已取消。"),
                store: store
            )
        }
    }

    private static func recordDrawingFileAvailable(
        drawingID: UUID,
        clearExternalFailure: Bool,
        store: DataStore
    ) {
        let now = BusinessDateValue.now()
        var changed = false
        store.mutateProjectDrawing(id: drawingID) { drawing in
            if drawing.fileAvailabilityStatus != .available {
                drawing.fileAvailabilityStatus = .available
                changed = true
            }
            if drawing.fileAvailabilityCheckedAt != now {
                drawing.fileAvailabilityCheckedAt = now
                changed = true
            }
            if clearExternalFailure {
                if !drawing.externalOpenFailureReason.isEmpty {
                    drawing.externalOpenFailureReason = ""
                    changed = true
                }
                if !drawing.externalOpenFailedAt.isEmpty {
                    drawing.externalOpenFailedAt = .empty
                    changed = true
                }
            }
        }
        if changed {
            store.scheduleSave()
        }
    }

    private static func recordDrawingOpenFailure(
        drawingID: UUID,
        availabilityStatus: ProjectDrawingFileAvailabilityStatus,
        reason: String,
        store: DataStore
    ) {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = BusinessDateValue.now()
        var changed = false
        store.mutateProjectDrawing(id: drawingID) { drawing in
            if drawing.fileAvailabilityStatus != availabilityStatus {
                drawing.fileAvailabilityStatus = availabilityStatus
                changed = true
            }
            if drawing.fileAvailabilityCheckedAt != now {
                drawing.fileAvailabilityCheckedAt = now
                changed = true
            }
            if !trimmedReason.isEmpty {
                if drawing.externalOpenFailureReason != trimmedReason {
                    drawing.externalOpenFailureReason = trimmedReason
                    changed = true
                }
                if drawing.externalOpenFailedAt != now {
                    drawing.externalOpenFailedAt = now
                    changed = true
                }
            }
        }
        if changed {
            store.scheduleSave()
        }
    }

    static func deleteDrawing(_ drawing: ProjectDrawing, store: DataStore) {
        let deletion = store.removeProjectDrawings(
            ids: Set([drawing.id]),
            audit: DataStoreDeletionAuditContext(
                summary: AppLocalization.string("删除项目图纸"),
                detail: drawing.fileName,
                source: "ProjectDetailView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.drawingFiles(
                [drawing.fileName],
                summary: "projectDetail.drawings"
            ),
            recordsAuditImmediately: true
        )
        guard !deletion.isEmpty else { return }
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
        var drawings = store.projectDrawings
        for index in drawings.indices {
            if drawings[index].projectId == drawing.projectId,
               drawings[index].name == drawing.name,
               drawings[index].id != drawing.id {
                drawings[index].isCurrentVersion = false
            }
        }
        store.replaceProjectDrawings(drawings)
    }
}
