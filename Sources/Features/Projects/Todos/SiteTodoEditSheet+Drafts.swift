import SwiftUI

extension SiteTodoEditSheet {
    var draftStore: BusinessDraftStore { .scoped(to: store.storeURL) }
    var draftKey: BusinessDraftStore.Key {
        todo.map { .todoEdit($0.id) } ?? .todo(projectID: initialProjectId)
    }
    var isImportingPhoto: Bool { beforePhotoImportTask != nil || afterPhotoImportTask != nil }

    func loadDraft() {
        guard !draftLoaded else { return }
        do {
            if let saved = try draftStore.load(SiteTodoFormDraft.self, key: draftKey) {
                hasSavedDraft = true
                if todo != nil { pendingRestoration = saved } else { try restore(saved) }
            }
            draftLoaded = true
            draftError = nil
            // A camera invocation must not replace previously retained before/after evidence.
            if pendingRestoration == nil {
                if draft.beforePhotoID == nil, draft.record.rectificationBeforePhotoFileName == nil, let initialBeforePhotoData {
                    beforePhotoData = initialBeforePhotoData
                    draft.beforePhotoID = UUID()
                }
                if draft.afterPhotoID == nil, draft.record.rectificationAfterPhotoFileName == nil, let initialAfterPhotoData {
                    afterPhotoData = initialAfterPhotoData
                    draft.afterPhotoID = UUID()
                }
            }
        } catch { draftError = String(format: AppLocalization.string("读取草稿失败，原文件已保留：%@"), error.localizedDescription) }
    }

    func restore(_ saved: SiteTodoFormDraft) throws {
        // Read all blobs before changing the form, so a missing photo cannot partially restore it.
        let before = try saved.beforePhotoID.map { try draftStore.photo(id: $0, key: draftKey) }
        let after = try saved.afterPhotoID.map { try draftStore.photo(id: $0, key: draftKey) }
        var restored = saved
        if let todo {
            guard saved.record.id == todo.id else { throw CocoaError(.fileReadCorruptFile) }
            restored.baseRecord = store.siteTodos.first { $0.id == todo.id }.flatMap { BusinessDraftStore.fingerprint($0) }
        }
        beforePhotoData = before
        afterPhotoData = after
        draft = restored
        pendingRestoration = nil
    }

    func persistDraft() {
        guard draftLoaded, !draftCompleted, !isSaving, pendingRestoration == nil else { return }
        if !hasSavedDraft, todo != nil,
           BusinessDraftStore.fingerprint(draft.record) == draft.baseRecord,
           draft.beforePhotoID == nil, draft.afterPhotoID == nil { return }
        do {
            if let id = draft.beforePhotoID, let beforePhotoData { try draftStore.savePhoto(beforePhotoData, id: id, key: draftKey) }
            if let id = draft.afterPhotoID, let afterPhotoData { try draftStore.savePhoto(afterPhotoData, id: id, key: draftKey) }
            try draftStore.save(draft, key: draftKey)
            hasSavedDraft = true
            draftError = nil
        } catch { draftError = String(format: AppLocalization.string("草稿保存失败，请保留此页面并重试：%@"), error.localizedDescription) }
    }

    func saveDraft() {
        guard draftLoaded, !isSaving, !isImportingPhoto, pendingRestoration == nil else { return }
        persistDraft()
        guard draftError == nil else { return }
        isSaving = true
        let savedDraft = draft
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let record = try await draftStore.commitTodo(savedDraft, key: draftKey, editing: todo != nil, in: store)
                draftCompleted = true
                onSave(record)
                dismiss()
            } catch { draftError = String(format: AppLocalization.string("保存失败，草稿已保留：%@"), error.localizedDescription) }
        }
    }

    func discardDraft() {
        do {
            try draftStore.discardTodo(key: draftKey, in: store)
            draftCompleted = true
            dismiss()
        } catch { draftError = error.localizedDescription }
    }

    var draftStatusSection: some View {
        Section {
            if let draftError {
                Text(draftError).foregroundStyle(.red)
                if !draftLoaded {
                    Button(AppLocalization.string("重试"), action: loadDraft)
                }
            } else {
                Text(AppLocalization.string("自动保留草稿，关闭后可继续填写。")).foregroundStyle(.secondary)
            }
            if isSaving || isImportingPhoto { ProgressView(AppLocalization.string("正在保存，请稍候…")) }
            if let pendingRestoration {
                if pendingRestoration.baseRecord != todo.flatMap({ BusinessDraftStore.fingerprint($0) }) {
                    Text(AppLocalization.string("原记录在草稿保存后已有变化，恢复后请逐项核对。")).foregroundStyle(.orange)
                }
                Text(AppLocalization.string("恢复草稿只会填入表单；请核对当前记录后再保存。"))
                Button(AppLocalization.string("恢复草稿")) {
                    do { try restore(pendingRestoration) } catch { draftError = error.localizedDescription }
                }
                .accessibilityIdentifier("todo-restore-draft")
                Button(AppLocalization.string("保留当前记录并丢弃草稿"), role: .destructive) {
                    do {
                        try draftStore.discardTodo(key: draftKey, in: store)
                        self.pendingRestoration = nil
                        hasSavedDraft = false
                        draftError = nil
                    } catch { draftError = error.localizedDescription }
                }
            }
            if todo == nil, store.siteTodos.contains(where: { $0.id == draft.record.id }) {
                Text(AppLocalization.string("这份草稿对应的记录已保存，请丢弃草稿或作为新记录继续。"))
                Button(AppLocalization.string("作为新记录继续")) { draft.record.id = UUID() }
            }
            Button(AppLocalization.string("丢弃草稿"), role: .destructive) { showDiscardDraft = true }
                .accessibilityIdentifier("todo-discard-draft")
        }
    }
}
