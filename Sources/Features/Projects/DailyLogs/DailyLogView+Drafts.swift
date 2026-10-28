import SwiftUI

extension DailyLogView {
    var businessDraftStore: BusinessDraftStore { .scoped(to: store.storeURL) }
    func closeComposer() {
        showAdd = false
        if standaloneComposer { dismissComposer() }
    }

    var composerDraftKey: BusinessDraftStore.Key { .daily(projectID: draftScopeID) }
    var composerDraft: DailyLogFormDraft { DailyLogFormDraft(composer: composer, recordID: draftRecordID) }

    func restoreComposerDraft() {
        guard !draftLoaded else { return }
        do {
            if let saved = try businessDraftStore.load(DailyLogFormDraft.self, key: composerDraftKey) {
                var restored = try saved.composer(store: businessDraftStore, key: composerDraftKey)
                guard restored.projectId == draftScopeID else { throw CocoaError(.fileReadCorruptFile) }
                if !seedInputsApplied {
                    mergeSeedInputs(into: &restored)
                }
                composer = restored
                draftRecordID = saved.recordID
            }
            seedInputsApplied = true
            draftLoaded = true
        } catch { draftError = String(format: AppLocalization.string("读取草稿失败，原文件已保留：%@"), error.localizedDescription) }
    }

    /// Content provenance survives reopening; an explicitly reimported removed photo can return.
    /// Byte comparison also recognizes old drafts written before provenance was stored.
    func mergeSeedInputs(into restored: inout DailyLogComposerState) {
        var hasNewContentInput = false
        for seed in initialPhotoDrafts {
            if let sourceID = seed.sourcePhotoID, !restored.appliedSeedSourceIDs.contains(sourceID) {
                hasNewContentInput = true
            }
            if let index = restored.photoDrafts.firstIndex(where: { photo in
                if let sourceID = seed.sourcePhotoID, photo.sourcePhotoID == sourceID { return true }
                return photo.data == seed.data
            }) {
                if restored.photoDrafts[index].sourcePhotoID == nil {
                    restored.photoDrafts[index].sourcePhotoID = seed.sourcePhotoID
                }
            } else {
                restored.photoDrafts.append(seed.photoDraft)
                if seed.sourcePhotoID == nil { hasNewContentInput = true }
            }
            if let sourceID = seed.sourcePhotoID { restored.appliedSeedSourceIDs.insert(sourceID) }
        }
        let content = initialContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = restored.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsContent = ("\n" + existing + "\n").contains("\n" + content + "\n")
        if !content.isEmpty, !containsContent, hasNewContentInput || initialPhotoDrafts.isEmpty {
            restored.content += (restored.content.isEmpty ? "" : "\n") + initialContent
        }
    }

    func switchComposerDraftScope(to projectID: UUID?) {
        guard draftLoaded, !draftCompleted, !isSavingLog, projectID != draftScopeID else { return }
        let previousScope = draftScopeID
        var previousComposer = composer
        previousComposer.projectId = previousScope
        do {
            for photo in previousComposer.photoDrafts { try businessDraftStore.savePhoto(photo.data, id: photo.id, key: composerDraftKey) }
            try businessDraftStore.save(DailyLogFormDraft(composer: previousComposer, recordID: draftRecordID), key: composerDraftKey)
            let targetKey = BusinessDraftStore.Key.daily(projectID: projectID)
            if let saved = try businessDraftStore.load(DailyLogFormDraft.self, key: targetKey) {
                let restored = try saved.composer(store: businessDraftStore, key: targetKey)
                guard restored.projectId == projectID else { throw CocoaError(.fileReadCorruptFile) }
                draftScopeID = projectID
                draftRecordID = saved.recordID
                composer = restored
            } else {
                draftScopeID = projectID
                draftRecordID = UUID()
            }
            persistComposerDraft()
        } catch {
            composer.projectId = previousScope
            draftError = String(format: AppLocalization.string("读取草稿失败，原文件已保留：%@"), error.localizedDescription)
        }
    }

    func persistComposerDraft() {
        guard draftLoaded, !draftCompleted, !isSavingLog, composer.projectId == draftScopeID else { return }
        do {
            for photo in composer.photoDrafts {
                try businessDraftStore.savePhoto(photo.data, id: photo.id, key: composerDraftKey)
            }
            try businessDraftStore.save(composerDraft, key: composerDraftKey)
            draftError = nil
        } catch { draftError = String(format: AppLocalization.string("草稿保存失败，请保留此页面并重试：%@"), error.localizedDescription) }
    }

    func persistEditorDraft() {
        guard showEdit, editorDraftReady, !isSavingLog, let id = editor.logId else { return }
        do {
            var persisted = editor
            persisted.dateText = editor.date.storageText
            try businessDraftStore.save(persisted, key: .dailyEdit(id))
            draftError = nil
        } catch { draftError = String(format: AppLocalization.string("草稿保存失败，请保留此页面并重试：%@"), error.localizedDescription) }
    }

    func cleanupUncommittedDraftPhotos() throws {
        let referenced = Set(store.dailyLogs.flatMap { $0.allPhotoFileNames })
        for name in try businessDraftStore.pendingPhotoFiles(key: composerDraftKey) where !referenced.contains(name) {
            let manager = FileManager.default
            if manager.fileExists(atPath: PhotoStorage.fileURL(for: name).path)
                || manager.fileExists(atPath: PhotoStorage.thumbnailStorageURL(for: name).path) {
                try DataStoreDeferredFileCleanup.deletePhotoFilesOrThrow([name], summary: "dailyDraft.discardUnreferenced")
            }
        }
    }

    func discardComposerDraft() {
        do {
            guard store.loadState == .ready, !store.isApplyingBackup else {
                throw DataStore.PersistenceBlockedError(message: store.persistenceErrorMessage)
            }
            try cleanupUncommittedDraftPhotos()
            try businessDraftStore.discard(key: composerDraftKey)
            draftCompleted = true
            clearDraft()
            closeComposer()
        } catch { draftError = error.localizedDescription }
    }

    var draftStatusSection: some View {
        Section {
            if let draftError { Text(draftError).foregroundStyle(.red) } else { Text(AppLocalization.string("自动保留草稿，关闭后可继续填写。")).foregroundStyle(.secondary) }
            if store.dailyLogs.contains(where: { $0.id == draftRecordID }) {
                Text(AppLocalization.string("这份草稿对应的记录已保存，请丢弃草稿或作为新记录继续。"))
                Button(AppLocalization.string("作为新记录继续")) { draftRecordID = UUID()
                persistComposerDraft() }
            }
            if isSavingLog { ProgressView(AppLocalization.string("正在保存，请稍候…")) }
        }
    }
}
