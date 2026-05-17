import SwiftUI

extension ProjectDetailContainer {
    func updateProjectPhoto(context: ProjectPhotoContext, note: String, tag: PhotoTag) {
        guard let logIndex = projectStore.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = projectStore.dailyLogs[logIndex]
        if let photoIndex = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            log.photos[photoIndex].note = note
            log.photos[photoIndex].tag = tag
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            log.photos.append(LogPhoto(fileName: legacy, note: note, tag: tag))
        }
        store.updateDailyLog(log)
        store.scheduleSave()
    }

    func deleteProjectPhoto(context: ProjectPhotoContext) {
        flushPendingProjectDeletionIfNeeded()
        let snapshot = store.dailyLogs
        guard let logIndex = projectStore.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = projectStore.dailyLogs[logIndex]
        var deletedFileName: String?
        if let index = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            let fileName = log.photos[index].fileName
            deletedFileName = fileName
            log.photos.remove(at: index)
            if log.photoFileName == fileName {
                log.photoFileName = log.photos.first?.fileName
            }
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            deletedFileName = legacy
            log.photoFileName = nil
        }
        guard let deletedFileName else { return }
        store.updateDailyLog(log)
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除项目照片"),
            commit: {
                DataStoreDeferredFileCleanup.photoFiles(
                    [deletedFileName],
                    summary: "projectDetail.photoFiles"
                )?.perform()
                store.scheduleSave()
            },
            undo: {
                store.replaceDailyLogs(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.dailyLogs,
                    deletedIDs: Set([context.logId])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除项目照片"),
                detail: projectDetailAuditDetail([deletedFileName]),
                source: "ProjectDetailView"
            )
        )
    }

    func deleteDocument(_ document: ProjectDocument) {
        deleteProjectDocumentWithUndo(document)
    }

    func saveDocumentEdit(_ document: ProjectDocument) {
        ProjectDetailAssetActions.saveDocumentEdit(document, store: store)
    }

    func saveDrawing(_ updated: ProjectDrawing) {
        ProjectDetailAssetActions.saveDrawing(updated, store: store)
    }

    func saveContact(_ updated: ProjectContact) {
        if projectStore.projectContacts.contains(where: { $0.id == updated.id }) {
            store.upsertProjectContact(updated)
            store.scheduleSave()
        }
    }

    func deleteContact(_ target: ProjectContact) {
        removeContactAssociation(contactID: target.id, from: projectId)
        store.scheduleSave()
    }

    func removeContactAssociation(contactID: UUID, from currentProjectID: UUID) {
        guard let contact = projectStore.projectContacts.first(where: { $0.id == contactID }) else { return }
        var updatedContact = contact
        if contact.projectId == currentProjectID {
            if let promotedProjectID = contact.relatedProjectIds.first(where: { $0 != currentProjectID }) {
                updatedContact.projectId = promotedProjectID
                updatedContact.relatedProjectIds.removeAll { $0 == currentProjectID || $0 == promotedProjectID }
                store.upsertProjectContact(updatedContact)
            } else {
                store.removeProjectContact(id: contactID)
            }
        } else {
            updatedContact.relatedProjectIds.removeAll { $0 == currentProjectID }
            store.upsertProjectContact(updatedContact)
        }
    }

    func setDrawingAsCurrentVersion(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.setDrawingAsCurrentVersion(drawing, store: store)
    }

    func deleteDrawing(_ drawing: ProjectDrawing) {
        ProjectDetailAssetActions.deleteDrawing(drawing, store: store)
    }

    func timelineDrawings(name: String, drawings: [ProjectDrawing]) -> [ProjectDrawing] {
        ProjectDetailAssetActions.timelineDrawings(name: name, relatedDrawings: drawings)
    }
}
