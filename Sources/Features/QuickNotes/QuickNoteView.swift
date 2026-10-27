import SwiftUI

struct QuickNoteView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.expandedPhoneWorkspaceWidth) private var rootWorkspaceWidth
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
    @State private var publishNotice: OperationToastNotice?
    @State private var isPublishing = false
    @State private var publishingNoteId: UUID?
    @State private var lastSavedNoteId: UUID?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var didOpenFocusedNote = false
    @State private var didRestoreDraft = false
    @State private var workspaceSelection = QuickNoteWorkspaceSelection.all
    @State private var projectSearchText = ""
    @State private var containerWidth: CGFloat = 0
    @State private var hasAttachmentActivity = false
    @FocusState private var isProjectSearchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var workspaceMinimumWidth: CGFloat = 820
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
        Group {
            if embedsNavigationStack {
                NavigationStack {
                    quickNoteSurface
                }
            } else {
                quickNoteSurface
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { containerWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in containerWidth = width }
            }
        }
    }

    private var quickNoteSurface: some View {
        // Both panes and the composer keep one structural identity across width changes.
        HStack(spacing: 0) {
            workspaceProjectList
                // The outer workspace owns the screen safe area; this is an interior pane.
                .ignoresSafeArea(.container, edges: usesExpandedWorkspace ? .horizontal : [])
                .frame(width: workspaceSidebarWidth)
                .clipped()
                .opacity(usesExpandedWorkspace ? 1 : 0)
                .allowsHitTesting(usesExpandedWorkspace)
                .accessibilityHidden(!usesExpandedWorkspace)

            noteList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .leading) {
            if usesExpandedWorkspace {
                ExpandedPhoneColumnDivider()
                    .frame(width: 1)
                    .offset(x: workspaceSidebarWidth - 0.5)
            }
        }
        .background(Color(.systemGroupedBackground), ignoresSafeAreaEdges: usesExpandedWorkspace ? [] : .all)
        .modifier(ExpandedPhoneScrollEdgeModifier(isExpanded: usesExpandedWorkspace))
        .navigationTitle(AppLocalization.string("随手记"))
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索随手记"))
        .task(id: searchRequest) {
            await searchModel.refresh(notes: store.quickNotes, projects: store.projects, keyword: searchText)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: draftContent) { _, _ in
            followWorkspaceSelectionIfDraftIsEmpty()
            saveDraftState()
        }
        .onChange(of: draftAttachments.map(\.id)) { _, _ in
            followWorkspaceSelectionIfDraftIsEmpty()
            saveDraftState()
        }
        .onChange(of: draftProjectId) { _, _ in saveDraftState() }
        .onChange(of: usesExpandedWorkspace) { _, expanded in
            if !expanded { isProjectSearchFocused = false }
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

    private var usesExpandedWorkspace: Bool {
        ExpandedPhoneWorkspaceLayout.isAvailable(width: availableWorkspaceWidth, minimumWidth: workspaceMinimumWidth)
    }

    private var availableWorkspaceWidth: CGFloat {
        rootWorkspaceWidth > 0 ? rootWorkspaceWidth : containerWidth
    }

    private var workspaceSidebarWidth: CGFloat {
        usesExpandedWorkspace ? ExpandedPhoneWorkspaceLayout.sidebarWidth(
            containerWidth: availableWorkspaceWidth, minimumWorkspaceWidth: workspaceMinimumWidth
        ) : 0
    }

    private var hasDraft: Bool {
        !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
    }

    private var visibleNotes: [QuickNote] {
        searchModel.notes.filter { note in
            guard note.id != publishingNoteId else { return false }
            switch workspaceSelection {
            case .all: return true
            case .unlinked: return note.projectId == nil
            case let .project(id): return note.projectId == id
            }
        }
    }

    private var workspaceTitle: String {
        switch workspaceSelection {
        case .all: AppLocalization.string("quick_note_workspace_all")
        case .unlinked: AppLocalization.string("quick_note_composer_no_project_option")
        case let .project(id): store.projects.first(where: { $0.id == id })?.name
                ?? AppLocalization.string("quick_note_workspace_missing_project")
        }
    }

    private var noteList: some View {
        List {
            if usesExpandedWorkspace || workspaceSelection != .all {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workspaceTitle)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if workspaceSelection != .all {
                        Button(AppLocalization.string("quick_note_workspace_all")) { workspaceSelection = .all }
                            .frame(minHeight: 44)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // The draft's project stays explicit even when browsing a different project's history.
            QuickNoteProjectSelectionCard(
                projects: store.projects,
                projectId: draftProjectBinding,
                title: AppLocalization.string("quick_note_workspace_draft_project")
            )
                .disabled(isPublishing || hasAttachmentActivity)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            QuickNoteTimelineView(
                notes: visibleNotes,
                projects: store.projects,
                confirmedSavedNoteId: lastSavedNoteId,
                usesWorkspaceCards: usesExpandedWorkspace,
                onEdit: { editingNote = $0 },
                onConvert: { editingNote = $0 },
                onDelete: deleteNotes(_:),
                onPreview: { previewAttachment = $0 }
            )
            .disabled(isPublishing)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { messageComposer }
        .accessibilityIdentifier("quick-note-records-pane")
    }

    private var draftProjectBinding: Binding<UUID?> {
        Binding(get: { draftProjectId }, set: { id in
            guard !isPublishing, !hasAttachmentActivity else { return }
            draftProjectId = id
        })
    }

    private var workspaceProjectList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("quick_note_workspace_projects"))
                .font(.headline)
                .padding(.horizontal, 16)
            TextField(AppLocalization.string("quick_note_workspace_search_projects"), text: $projectSearchText)
                .focused($isProjectSearchFocused)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("quick-note-project-search")
            List {
                workspaceProjectRow(title: AppLocalization.string("quick_note_workspace_all"), selection: .all)
                workspaceProjectRow(title: AppLocalization.string("quick_note_composer_no_project_option"), selection: .unlinked)
                ForEach(store.projects.filter { projectSearchText.isEmpty || $0.name.localizedStandardContains(projectSearchText) }) { project in
                    workspaceProjectRow(title: project.name, selection: .project(project.id))
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(ExpandedPhoneSidebarScrollModifier(isExpanded: usesExpandedWorkspace))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 16)
        .background(Color(.secondarySystemGroupedBackground), ignoresSafeAreaEdges: [])
        .accessibilityIdentifier("quick-note-projects-pane")
    }

    private func workspaceProjectRow(title: String, selection: QuickNoteWorkspaceSelection) -> some View {
        Button {
            workspaceSelection = selection
            followWorkspaceSelectionIfDraftIsEmpty()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == .all ? "tray.full" : "building.2")
                    .foregroundStyle(Color.appPrimaryAction)
                Text(title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if workspaceSelection == selection {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appPrimaryAction)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: usesExpandedWorkspace ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
        .listRowInsets(usesExpandedWorkspace ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : nil)
        .listRowBackground(workspaceSelection == selection ? Color.appPrimaryAction.opacity(0.08) : Color.clear)
        .accessibilityAddTraits(workspaceSelection == selection ? .isSelected : [])
    }

    private func followWorkspaceSelectionIfDraftIsEmpty() {
        guard !hasDraft, !hasAttachmentActivity, !isPublishing else { return }
        switch workspaceSelection {
        case .all: break
        case .unlinked: draftProjectId = nil
        case let .project(id): draftProjectId = id
        }
    }

    private var messageComposer: some View {
        VStack(spacing: 0) {
            if hasAttachmentActivity {
                Text(String(format: AppLocalization.string("quick_note_workspace_attachment_in_progress"), draftProjectTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            } else if hasDraft, workspaceSelection != .all, !draftMatchesWorkspaceSelection {
                Text(String(format: AppLocalization.string("quick_note_workspace_draft_keeps_project"), draftProjectTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            QuickNoteComposerView(
                projects: store.projects,
                content: $draftContent,
                projectId: $draftProjectId,
                attachments: $draftAttachments,
                mode: .compact,
                isPublishing: isPublishing,
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
                },
                onAttachmentActivityChange: { isActive in
                    hasAttachmentActivity = isActive
                    if !isActive { followWorkspaceSelectionIfDraftIsEmpty() }
                }
            )
            .disabled(isPublishing)
            .operationToast(notice: $publishNotice)
        }
        .background(.bar)
    }

    private var draftMatchesWorkspaceSelection: Bool {
        switch workspaceSelection {
        case .all: true
        case .unlinked: draftProjectId == nil
        case let .project(id): draftProjectId == id
        }
    }

    private var draftProjectTitle: String {
        store.projects.first(where: { $0.id == draftProjectId })?.name
            ?? AppLocalization.string("quick_note_composer_no_project_option")
    }
}

private enum QuickNoteWorkspaceSelection: Equatable {
    case all
    case unlinked
    case project(UUID)
}

private extension QuickNoteView {
    func publishDraft() {
        guard !isPublishing, !hasAttachmentActivity else { return }
        let originalContent = draftContent
        let content = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !draftAttachments.isEmpty else { return }
        let note = QuickNote(
            title: QuickNoteText.title(from: content, attachments: draftAttachments),
            content: content,
            projectId: draftProjectId,
            attachments: draftAttachments
        )
        saveDraftState()
        isPublishing = true
        publishingNoteId = note.id
        Task { @MainActor in
            defer {
                isPublishing = false
                publishingNoteId = nil
                followWorkspaceSelectionIfDraftIsEmpty()
            }
            let expectedFingerprint = BusinessDraftStore.fingerprint(note)
            var didInsert = false
            do {
                await store.awaitInitialLoad()
                try store.requireBusinessWritesAllowed()
                guard expectedFingerprint != nil else { throw CocoaError(.fileWriteUnknown) }
                store.insertQuickNoteAtTop(note)
                didInsert = true
                try await store.flushSaveOrThrow()

                // A media import already in flight can append to the next draft while saving.
                if draftContent == originalContent { draftContent = "" }
                let publishedAttachmentIds = Set(note.attachments.map(\.id))
                draftAttachments.removeAll { publishedAttachmentIds.contains($0.id) }
                saveDraftState()
                lastSavedNoteId = note.id
                publishNotice = .info(AppLocalization.string("quick_note_saved_notice"))
            } catch {
                if didInsert, let expectedFingerprint,
                   let current = store.quickNotes.first(where: { $0.id == note.id }),
                   BusinessDraftStore.fingerprint(current) == expectedFingerprint {
                    store.replaceQuickNotes(store.quickNotes.filter { $0.id != note.id })
                }
                saveDraftState()
                publishNotice = .info(String(
                    format: AppLocalization.string("quick_note_save_failed_notice"),
                    error.localizedDescription
                ))
            }
        }
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
            if lastSavedNoteId == updated.id { lastSavedNoteId = nil }
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
        if let lastSavedNoteId, ids.contains(lastSavedNoteId) { self.lastSavedNoteId = nil }

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
        guard !isPublishing, !hasAttachmentActivity else { return }
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
        followWorkspaceSelectionIfDraftIsEmpty()
    }
}
