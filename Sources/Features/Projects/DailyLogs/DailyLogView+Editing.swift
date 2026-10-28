import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    func save() {
        guard canSaveLog, !isSavingLog else { return }
        persistComposerDraft()
        guard draftError == nil else { return }
        isSavingLog = true
        let draft = composer
        let logId = draftRecordID
        Task { @MainActor in
            defer { isSavingLog = false }
            var attemptPhotoNames: [String] = []
            do {
                await store.awaitInitialLoad()
                guard store.loadState == .ready, !store.isApplyingBackup else {
                    throw DataStore.PersistenceBlockedError(message: store.persistenceErrorMessage)
                }
                try cleanupUncommittedDraftPhotos()
                let photoAttemptID = UUID()
                try businessDraftStore.registerPhotoAttempt(id: photoAttemptID, count: draft.photoDrafts.count, key: composerDraftKey)
                let fileNames = try await PhotoStorage.saveManyAsyncOrThrow(originals: draft.photoDrafts.map(\.data), logId: photoAttemptID)
                attemptPhotoNames = fileNames
                let photos = zip(fileNames, draft.photoDrafts).map { LogPhoto(fileName: $0.0, note: $0.1.note, tag: $0.1.tag, sourcePhotoID: $0.1.sourcePhotoID) }
                let log = DailyLog(
                    id: logId, date: draft.date, weather: draft.weather,
                    content: draft.content, workers: NumericInputSupport.quantity(draft.workers), photoFileName: fileNames.first, photos: photos,
                    safety: draft.safety, materials: draft.materials, tomorrowPlan: draft.tomorrowPlan,
                    qualityIssue: draft.qualityIssue, rectification: draft.rectification, confirmer: draft.confirmer,
                    linkedConstructionMethodIDs: sortedLinkedMethodIDs(draft.linkedMethodIDs), projectId: draft.projectId
                )
                try await businessDraftStore.commitNewDailyLog(log, in: store)
                draftCompleted = true
                clearDraft()
                closeComposer()
            } catch {
                let referenced = Set(store.dailyLogs.flatMap { $0.allPhotoFileNames })
                DataStoreDeferredFileCleanup.photoFiles(attemptPhotoNames.filter { !referenced.contains($0) }, summary: "dailyDraft.failedSave")?.perform()
                draftError = String(format: AppLocalization.string("保存失败，草稿已保留：%@"), error.localizedDescription)
            }
        }
    }

    func clearDraft() {
        draftRecordID = UUID()
        draftScopeID = initialProjectId
        composer.date = .today()
        cancelPhotoImportAndResetSession()
        composer.selectedPhotos = []
        composer.photoDrafts = []
        composer.appliedSeedSourceIDs = []
        composer.showLogCamera = false
        composer.cameraPhotoTag = .general
        composer.projectId = initialProjectId
        composer.content = ""
        composer.workers = ""
        composer.safety = ""
        composer.materials = ""
        composer.tomorrowPlan = ""
        composer.qualityIssue = ""
        composer.rectification = ""
        composer.confirmer = ""
        composer.linkedMethodIDs.removeAll()
        composer.weather = ""
    }

    func startEdit(_ log: DailyLog) {
        draftError = nil
        editor.baseRecord = BusinessDraftStore.fingerprint(log)
        editor.logId = log.id
        editor.date = log.date
        editor.weather = log.weather
        editor.content = log.content
        editor.workers = log.workers.wireText
        editor.safety = log.safety
        editor.materials = log.materials
        editor.tomorrowPlan = log.tomorrowPlan
        editor.qualityIssue = log.qualityIssue
        editor.rectification = log.rectification
        editor.confirmer = log.confirmer
        editor.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        editor.projectId = log.projectId
        editorDraftReady = false
        do { pendingEditorDraft = try businessDraftStore.load(DailyLogEditorState.self, key: .dailyEdit(log.id)) } catch { draftError = error.localizedDescription }
        editorDraftReady = pendingEditorDraft == nil && draftError == nil
        showEdit = true
    }

    func openFocusedLogIfNeeded() {
        guard let focusedLogId, !didOpenFocusedLog,
              let log = store.dailyLogs.first(where: { $0.id == focusedLogId }) else { return }
        didOpenFocusedLog = true
        viewMode = .list
        filterProjectId = log.projectId
        searchText = ""
        Task { @MainActor in
            startEdit(log)
        }
    }

    func saveEditedLog() {
        guard !isSavingLog, pendingEditorDraft == nil else { return }
        persistEditorDraft()
        guard draftError == nil else { return }
        guard let id = editor.logId,
              let index = store.dailyLogs.firstIndex(where: { $0.id == id }) else { return }
        let previous = store.dailyLogs[index]
        var log = previous
        guard BusinessDraftStore.fingerprint(log) == editor.baseRecord else {
            draftError = AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。")
            return
        }
        log.date = editor.date
        log.weather = editor.weather
        log.content = editor.content
        log.workers = NumericInputSupport.quantity(editor.workers)
        log.safety = editor.safety
        log.materials = editor.materials
        log.tomorrowPlan = editor.tomorrowPlan
        log.qualityIssue = editor.qualityIssue
        log.rectification = editor.rectification
        log.confirmer = editor.confirmer
        log.linkedConstructionMethodIDs = sortedLinkedMethodIDs(editor.linkedMethodIDs)
        log.projectId = editor.projectId
        isSavingLog = true
        Task { @MainActor in
            defer { isSavingLog = false }
            var committed = false
            do {
                await store.awaitInitialLoad()
                guard store.loadState == .ready, !store.isApplyingBackup,
                      let current = store.dailyLogs.first(where: { $0.id == id }),
                      BusinessDraftStore.fingerprint(current) == editor.baseRecord else {
                    throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
                }
                store.updateDailyLog(log)
                try await businessDraftStore.complete(key: .dailyEdit(id)) {
                    try await store.flushSaveOrThrow()
                    committed = true
                    editor.baseRecord = BusinessDraftStore.fingerprint(log)
                }
                editorDraftReady = false
                showEdit = false
            } catch {
                if !committed, let live = store.dailyLogs.first(where: { $0.id == id }),
                   BusinessDraftStore.fingerprint(live) == BusinessDraftStore.fingerprint(log) {
                    store.updateDailyLog(previous)
                }
                draftError = String(format: AppLocalization.string("保存失败，草稿已保留：%@"), error.localizedDescription)
            }
        }
    }

    func copyLogToToday(_ log: DailyLog) {
        composer.date = .today()
        // The copied content belongs to another day; weather needs a fresh observation.
        composer.weather = ""
        composer.content = log.content
        composer.workers = log.workers.wireText
        composer.safety = log.safety
        composer.materials = log.materials
        composer.tomorrowPlan = log.tomorrowPlan
        composer.qualityIssue = log.qualityIssue
        composer.rectification = log.rectification
        composer.confirmer = log.confirmer
        composer.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        composer.projectId = log.projectId
        composer.selectedPhotos = []
        composer.photoDrafts = []
        composer.appliedSeedSourceIDs = []
        showAdd = true
    }

    func applyDailyLogTemplate(_ template: ProjectTemplate) {
        composer.content = template.content
    }
}

extension DailyLogView {
    func deleteLogs(_ idx: IndexSet) {
        let ids = idx.map { filtered[$0].id }
        deleteLogIds(ids)
    }

    func deleteLogIds(_ ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.dailyLogs.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }

        let photoFileNames = targets.flatMap(\.allPhotoFileNames)
        let deletion = store.removeDailyLogs(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除施工日志 %lld 条"), Int64(targets.count)),
                detail: String(format: AppLocalization.string("关联照片文件 %lld 个"), Int64(photoFileNames.count)),
                source: "DailyLogView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.photoFiles(
                photoFileNames,
                summary: "dailyLog.photoFiles"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已删除 %lld 条施工日志"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreDailyLogs(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }
}
