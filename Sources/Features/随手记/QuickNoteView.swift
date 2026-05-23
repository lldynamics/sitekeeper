import SwiftUI

struct QuickNoteView: View {
    @Environment(DataStore.self) private var store
    let focusedNoteId: UUID?
    let embedsNavigationStack: Bool
    @State private var searchText = ""
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

    private var filteredNotes: [QuickNote] {
        store.quickNotes
            .filter(matchesSearch(_:))
            .sorted { $0.createdAt > $1.createdAt }
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
                notes: filteredNotes,
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
        .navigationTitle(String(localized: "随手记"))
        .searchable(text: $searchText, prompt: String(localized: "搜索随手记"))
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
        .confirmationDialog(String(localized: "清空当前草稿？"), isPresented: $showClearComposerConfirm, titleVisibility: .visible) {
            Button(String(localized: "清空草稿"), role: .destructive) {
                clearComposerDraft(deleteFiles: true)
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "将清空文字、附件和关联工程。"))
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

    private func matchesSearch(_ note: QuickNote) -> Bool {
        SearchMatcher.filter(
            [note],
            keyword: searchText,
            extraFields: { note in [projectName(note.projectId)] }
        ).isEmpty == false
    }

    private func publishDraft() {
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

    private func saveEditedNote(original: QuickNote, updated: QuickNote) {
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

    private func deleteNotes(_ notes: [QuickNote]) {
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
                summary: String(format: String(localized: "删除随手记 %lld 条"), Int64(targets.count)),
                detail: String(format: String(localized: "关联附件文件 %lld 个"), Int64(attachments.count)),
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
            message: String(format: String(localized: "已删除 %lld 条随手记"), Int64(deletion.deletedCount)),
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

    private func uniqueAttachments(_ attachments: [QuickNoteAttachment]) -> [QuickNoteAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            guard !attachment.fileName.isEmpty else { return false }
            return seen.insert(attachment.fileName).inserted
        }
    }

    private func queueAttachmentRemovalUndo(
        _ attachments: [QuickNoteAttachment],
        restoreSnapshot: [QuickNote],
        noteId: UUID
    ) {
        let dedupedAttachments = uniqueAttachments(attachments)
        guard !dedupedAttachments.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已移除 %lld 个随手记附件"), Int64(dedupedAttachments.count)),
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
                summary: String(format: String(localized: "删除随手记附件 %lld 个"), Int64(dedupedAttachments.count)),
                detail: dedupedAttachments.map(\.displayName).joined(separator: "、"),
                source: "QuickNoteView"
            )
        )
    }

    private func openFocusedNoteIfNeeded() {
        guard let focusedNoteId, !didOpenFocusedNote,
              let note = store.quickNotes.first(where: { $0.id == focusedNoteId }) else { return }
        didOpenFocusedNote = true
        Task { @MainActor in
            editingNote = note
        }
    }

    private func restoreDraftIfNeeded() {
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

    private func saveDraftState() {
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

    private func clearStoredDraft() {
        storedDraftContent = ""
        storedDraftProjectId = ""
        storedDraftAttachments = ""
    }

    private func clearComposerDraft(deleteFiles: Bool) {
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

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return store.projects.first(where: { $0.id == id })?.name ?? ""
    }
}

enum QuickNoteText {
    static func displayContent(for note: QuickNote) -> String {
        if !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note.content
        }
        if !note.attachments.isEmpty {
            return attachmentSummary(note.attachments)
        }
        return note.title.isEmpty ? "未命名记录" : note.title
    }

    static func attachmentSummary(_ attachments: [QuickNoteAttachment]) -> String {
        let mediaCount = attachments.filter { [.photo, .video].contains($0.attachmentKind) }.count
        var parts: [String] = []
        if mediaCount > 0 {
            parts.append("媒体 \(mediaCount)")
        }
        let grouped = Dictionary(grouping: attachments, by: { $0.attachmentKind })
        for kind in [QuickNoteAttachmentKind.audio, .drawing, .file] {
            guard let count = grouped[kind]?.count, count > 0 else { continue }
            parts.append("\(kind.title) \(count)")
        }
        return parts.joined(separator: " · ")
    }

    static func title(from content: String, attachments: [QuickNoteAttachment]) -> String {
        let compact = content.replacingOccurrences(of: "\n", with: " ")
        if !compact.isEmpty { return String(compact.prefix(24)) }
        let summary = attachmentSummary(attachments)
        return summary.isEmpty ? "随手记" : summary
    }
}
