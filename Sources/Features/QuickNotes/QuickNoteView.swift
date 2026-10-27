import SwiftUI

struct QuickNoteView: View {
    @Environment(DataStore.self) private var store
    let focusedNoteId: UUID?
    let embedsNavigationStack: Bool
    @State private var searchText = ""
    @State private var searchModel = QuickNoteSearchModel()
    @State private var draftContent = ""
    @State private var draftProjectId: UUID?
    @State private var draftAttachments: [QuickNoteAttachment] = []
    @State private var editingNote: QuickNote?
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var showClearComposerConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var didOpenFocusedNote = false
    @State private var didRestoreDraft = false
    @AppStorage(UserPreferenceKeys.quickNoteDraftContent) private var storedDraftContent = ""
    @AppStorage(UserPreferenceKeys.quickNoteDraftProjectId) private var storedDraftProjectId = ""
    @AppStorage(UserPreferenceKeys.quickNoteDraftAttachments) private var storedDraftAttachments = ""

    init(focusedNoteId: UUID? = nil, embedsNavigationStack: Bool = true) {
        self.focusedNoteId = focusedNoteId
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var searchRequest: QuickNoteSearchRequest {
        QuickNoteSearchRequest(version: store.projectStore.fileSearchVersion,
                               keyword: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                quickNoteSurface
            }
        } else {
            quickNoteSurface
        }
    }

    private var quickNoteSurface: some View {
        List {
            QuickNoteTimelineView(
                notes: searchModel.notes,
                projects: store.projects,
                onEdit: { editingNote = $0 },
                onConvert: { editingNote = $0 },
                onDelete: deleteNotes(_:),
                onPreview: { previewAttachment = $0 }
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppLocalization.string("随手记"))
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索随手记"))
        .task(id: searchRequest) {
            await searchModel.refresh(notes: store.quickNotes, projects: store.projects, keyword: searchText)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: draftContent) { _, _ in saveDraftState() }
        .onChange(of: draftProjectId) { _, _ in saveDraftState() }
        .safeAreaInset(edge: .bottom) {
            messageComposer
        }
        .sheet(item: $editingNote) { note in
            QuickNoteEditSheet(note: note, projects: store.projects) { updated in
                saveEditedNote(original: note, updated: updated)
            } onDelete: { target in
                deleteNotes([target])
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            QuickNoteAttachmentPreview(attachment: attachment)
        }
        .confirmationDialog(AppLocalization.string("清空当前草稿？"), isPresented: $showClearComposerConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string("清空草稿"), role: .destructive) {
                clearComposerDraft(deleteFiles: true)
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("将清空文字、附件和关联工程。"))
        }
        .onAppear {
            restoreDraftIfNeeded()
            openFocusedNoteIfNeeded()
        }
        .onDisappear {
            saveDraftState()
            undoableDeletion.flushPendingCommit()
        }
        .operationToast(notice: $operationNotice)
    }

    private var messageComposer: some View {
        QuickNoteComposerView(
            projects: store.projects,
            content: $draftContent,
            projectId: $draftProjectId,
            attachments: $draftAttachments,
            mode: .compact,
            onPublish: {
                publishDraft()
            },
            onPreview: { previewAttachment = $0 },
            onAttachmentAdded: { _ in
                saveDraftState()
            },
            onAttachmentRemoved: { _ in
                saveDraftState()
            },
            onDiscardDraftRequest: {
                showClearComposerConfirm = true
            }
        )
    }
}

private extension QuickNoteView {
    func publishDraft() {
        let content = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !draftAttachments.isEmpty else { return }
        store.insertQuickNoteAtTop(
            QuickNote(
                title: QuickNoteText.title(from: content, attachments: draftAttachments),
                content: content,
                projectId: draftProjectId,
                attachments: draftAttachments
            )
        )
        draftContent = ""
        draftAttachments = []
        clearStoredDraft()
        store.scheduleSave()
    }

    func saveEditedNote(original: QuickNote, updated: QuickNote) {
        let updatedFileNames = Set(updated.attachments.map(\.fileName))
        let removedAttachments = original.attachments.filter { !updatedFileNames.contains($0.fileName) }
        if store.quickNotes.contains(where: { $0.id == updated.id }) {
            let restoreSnapshot = store.quickNotes.map { note in
                guard note.id == updated.id else { return note }
                var restore = updated
                restore.attachments = uniqueAttachments(original.attachments + updated.attachments)
                return restore
            }
            store.updateQuickNote(updated)
            store.scheduleSave()
            queueAttachmentRemovalUndo(
                removedAttachments,
                restoreSnapshot: restoreSnapshot,
                noteId: updated.id
            )
        }
    }

    func deleteNotes(_ notes: [QuickNote]) {
        let ids = Set(notes.map(\.id))
        guard !ids.isEmpty else { return }

        let requestedByID = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let restoreSnapshot = store.quickNotes.map { note in
            requestedByID[note.id] ?? note
        }
        let targets = restoreSnapshot.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let attachments = uniqueAttachments(
            targets.flatMap(\.attachments) + notes.flatMap(\.attachments)
        )
        let deletion = store.removeQuickNotes(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除随手记 %lld 条"), Int64(targets.count)),
                detail: String(format: AppLocalization.string("关联附件文件 %lld 个"), Int64(attachments.count)),
                source: "QuickNoteView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.quickNoteAttachments(
                attachments,
                summary: "quickNote.attachments"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已删除 %lld 条随手记"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.replaceQuickNotes(UndoableDeletionCoordinator.restoringItems(
                    snapshot: restoreSnapshot,
                    current: store.quickNotes,
                    deletedIDs: ids
                ))
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func uniqueAttachments(_ attachments: [QuickNoteAttachment]) -> [QuickNoteAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            guard !attachment.fileName.isEmpty else { return false }
            return seen.insert(attachment.fileName).inserted
        }
    }

    func queueAttachmentRemovalUndo(
        _ attachments: [QuickNoteAttachment],
        restoreSnapshot: [QuickNote],
        noteId: UUID
    ) {
        let dedupedAttachments = uniqueAttachments(attachments)
        guard !dedupedAttachments.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: AppLocalization.string("已移除 %lld 个随手记附件"), Int64(dedupedAttachments.count)),
            commit: {
                DataStoreDeferredFileCleanup.quickNoteAttachments(
                    dedupedAttachments,
                    summary: "quickNote.removeAttachments"
                )?.perform()
                store.scheduleSave()
            },
            undo: {
                store.replaceQuickNotes(UndoableDeletionCoordinator.restoringItems(
                    snapshot: restoreSnapshot,
                    current: store.quickNotes,
                    deletedIDs: Set([noteId])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除随手记附件 %lld 个"), Int64(dedupedAttachments.count)),
                detail: dedupedAttachments.map(\.displayName).joined(separator: "、"),
                source: "QuickNoteView"
            )
        )
    }

    func openFocusedNoteIfNeeded() {
        guard let focusedNoteId, !didOpenFocusedNote,
              let note = store.quickNotes.first(where: { $0.id == focusedNoteId }) else { return }
        didOpenFocusedNote = true
        Task { @MainActor in
            editingNote = note
        }
    }

    func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true
        draftContent = storedDraftContent
        draftProjectId = UUID(uuidString: storedDraftProjectId)
        if let data = storedDraftAttachments.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode([QuickNoteAttachment].self, from: data)
                draftAttachments = decoded.filter { QuickNoteAttachmentStorage.exists(fileName: $0.fileName) }
            } catch {
                StorageIssueLog.recordEvent(
                    "quick_note.draft_attachments_decode_failed",
                    category: .dataStore,
                    details: [
                        "source": "QuickNoteView.restoreDraftIfNeeded",
                        "stored_bytes": "\(data.count)"
                    ],
                    error: error
                )
            }
        }
        saveDraftState()
    }

    func saveDraftState() {
        guard didRestoreDraft else { return }
        storedDraftContent = draftContent
        storedDraftProjectId = draftProjectId?.uuidString ?? ""
        do {
            let data = try JSONEncoder().encode(draftAttachments)
            if let text = String(data: data, encoding: .utf8) {
                storedDraftAttachments = text
            } else {
                StorageIssueLog.recordEvent(
                    "quick_note.draft_attachments_utf8_encode_failed",
                    category: .dataStore,
                    details: [
                        "source": "QuickNoteView.saveDraftState",
                        "attachment_count": "\(draftAttachments.count)"
                    ]
                )
            }
        } catch {
            StorageIssueLog.recordEvent(
                "quick_note.draft_attachments_encode_failed",
                category: .dataStore,
                details: [
                    "source": "QuickNoteView.saveDraftState",
                    "attachment_count": "\(draftAttachments.count)"
                ],
                error: error
            )
        }
    }

    func clearStoredDraft() {
        storedDraftContent = ""
        storedDraftProjectId = ""
        storedDraftAttachments = ""
    }

    func clearComposerDraft(deleteFiles: Bool) {
        if deleteFiles {
            DataStoreDeferredFileCleanup.quickNoteAttachments(
                draftAttachments,
                summary: "quickNote.clearDraftAttachments"
            )?.perform()
        }
        draftContent = ""
        draftProjectId = nil
        draftAttachments = []
        clearStoredDraft()
    }
}
