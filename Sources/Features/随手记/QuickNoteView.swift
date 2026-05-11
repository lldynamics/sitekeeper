import SwiftUI

struct QuickNoteView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let focusedNoteId: UUID?
    let embedsNavigationStack: Bool
    @State private var searchText = ""
    @State private var draftContent = ""
    @State private var draftProjectId: UUID?
    @State private var draftAttachments: [QuickNoteAttachment] = []
    @State private var draftAttachmentFileNames = Set<String>()
    @State private var editingNote: QuickNote?
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var showComposer = false
    @State private var showClearComposerConfirm = false
    @State private var composerDetent: PresentationDetent = .large
    @State private var didOpenFocusedNote = false
    @State private var didRestoreDraft = false
    @State private var hasRecoveredDraft = false
    @AppStorage("quickNoteDraftContent") private var storedDraftContent = ""
    @AppStorage("quickNoteDraftProjectId") private var storedDraftProjectId = ""
    @AppStorage("quickNoteDraftAttachments") private var storedDraftAttachments = ""

    init(focusedNoteId: UUID? = nil, embedsNavigationStack: Bool = true) {
        self.focusedNoteId = focusedNoteId
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var filteredNotes: [QuickNote] {
        store.quickNotes
            .filter(matchesSearch(_:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var canPublishDraft: Bool {
        !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
    }

    private var useFullScreenComposer: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var composerSheetPresented: Binding<Bool> {
        Binding(
            get: { showComposer && !useFullScreenComposer },
            set: { newValue in
                if !newValue {
                    showComposer = false
                }
            }
        )
    }

    private var composerFullScreenPresented: Binding<Bool> {
        Binding(
            get: { showComposer && useFullScreenComposer },
            set: { newValue in
                if !newValue {
                    showComposer = false
                }
            }
        )
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
                onCreate: { showComposer = true },
                onEdit: { editingNote = $0 },
                onConvert: { editingNote = $0 },
                onDelete: deleteNotes(_:),
                onPreview: { previewAttachment = $0 }
            )
        }
        .navigationTitle("随手记")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    HStack(spacing: 6) {
                        Text("发布")
                        if hasRecoveredDraft && canPublishDraft {
                            Circle()
                                .fill(.orange)
                                .frame(width: 7, height: 7)
                            Text("恢复草稿")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .accessibilityLabel(hasRecoveredDraft && canPublishDraft ? "发布，检测到未发布草稿" : "发布")
                .accessibilityHint("双击打开随手记发布面板")
            }
        }
        .searchable(text: $searchText, prompt: "搜索随手记")
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: draftContent) { _, _ in saveDraftState() }
        .onChange(of: draftProjectId) { _, _ in saveDraftState() }
        .sheet(isPresented: composerSheetPresented) {
            composerPresentation
                .presentationDetents([.large], selection: $composerDetent)
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: composerFullScreenPresented) {
            composerPresentation
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
        .onAppear {
            restoreDraftIfNeeded()
            openFocusedNoteIfNeeded()
        }
        .onDisappear(perform: saveDraftState)
    }

    private var composerPresentation: some View {
        NavigationStack {
            List {
                QuickNoteComposerView(
                    projects: store.projects,
                    content: $draftContent,
                    projectId: $draftProjectId,
                    attachments: $draftAttachments,
                    onPublish: {
                        publishDraft()
                        if !canPublishDraft {
                            showComposer = false
                        }
                    },
                    onPreview: { previewAttachment = $0 },
                    onAttachmentAdded: { attachment in
                        draftAttachmentFileNames.insert(attachment.fileName)
                        saveDraftState()
                    },
                    onAttachmentRemoved: { attachment in
                        draftAttachmentFileNames.remove(attachment.fileName)
                        saveDraftState()
                    },
                    onDraftCleared: { removed in
                        draftAttachmentFileNames.subtract(removed.map(\.fileName))
                        hasRecoveredDraft = false
                        clearStoredDraft()
                    },
                    onDiscardDraftRequest: {
                        showClearComposerConfirm = true
                    }
                )
            }
            .navigationTitle("发布随手记")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showComposer = false }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if hasRecoveredDraft && canPublishDraft {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 7, height: 7)
                            Text("恢复草稿")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("存在未发布草稿")
                    }
                    Button("清空", role: .destructive) {
                        showClearComposerConfirm = true
                    }
                    .disabled(!canPublishDraft)
                    Button("发布") {
                        publishDraft()
                        if !canPublishDraft {
                            showComposer = false
                        }
                    }
                    .disabled(!canPublishDraft)
                }
            }
            .confirmationDialog("清空当前草稿？", isPresented: $showClearComposerConfirm, titleVisibility: .visible) {
                Button("清空草稿", role: .destructive) {
                    clearComposerDraft(deleteFiles: true)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清空文字、附件和关联工程。")
            }
        }
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
        store.quickNotes.insert(
            QuickNote(
                title: QuickNoteText.title(from: content, attachments: draftAttachments),
                content: content,
                projectId: draftProjectId,
                attachments: draftAttachments
            ),
            at: 0
        )
        draftContent = ""
        draftAttachments = []
        draftAttachmentFileNames.removeAll()
        hasRecoveredDraft = false
        clearStoredDraft()
        store.scheduleSave()
    }

    private func saveEditedNote(original: QuickNote, updated: QuickNote) {
        let updatedFileNames = Set(updated.attachments.map(\.fileName))
        let removedAttachments = original.attachments.filter { !updatedFileNames.contains($0.fileName) }
        QuickNoteAttachmentStorage.delete(attachments: removedAttachments)
        if let index = store.quickNotes.firstIndex(where: { $0.id == updated.id }) {
            store.quickNotes[index] = updated
            store.scheduleSave()
        }
    }

    private func deleteNotes(_ notes: [QuickNote]) {
        let ids = Set(notes.map(\.id))
        QuickNoteAttachmentStorage.delete(attachments: notes.flatMap(\.attachments))
        store.quickNotes.removeAll { ids.contains($0.id) }
        store.scheduleSave()
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
        if let data = storedDraftAttachments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([QuickNoteAttachment].self, from: data) {
            draftAttachments = decoded.filter { QuickNoteAttachmentStorage.exists(fileName: $0.fileName) }
            draftAttachmentFileNames = Set(draftAttachments.map(\.fileName))
        }
        hasRecoveredDraft = !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
        saveDraftState()
    }

    private func saveDraftState() {
        guard didRestoreDraft else { return }
        storedDraftContent = draftContent
        storedDraftProjectId = draftProjectId?.uuidString ?? ""
        if let data = try? JSONEncoder().encode(draftAttachments),
           let text = String(data: data, encoding: .utf8) {
            storedDraftAttachments = text
        }
    }

    private func clearStoredDraft() {
        storedDraftContent = ""
        storedDraftProjectId = ""
        storedDraftAttachments = ""
    }

    private func clearComposerDraft(deleteFiles: Bool) {
        if deleteFiles {
            QuickNoteAttachmentStorage.delete(attachments: draftAttachments)
        }
        draftContent = ""
        draftProjectId = nil
        draftAttachments = []
        draftAttachmentFileNames.removeAll()
        hasRecoveredDraft = false
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
