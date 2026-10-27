import SwiftUI
import UIKit

struct QuickNoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) var store
    let note: QuickNote
    let projects: [Project]
    let onSave: (QuickNote) -> Void
    let onDelete: (QuickNote) -> Void

    @State var content: String
    @State var projectId: UUID?
    @State var attachments: [QuickNoteAttachment]
    @State private var temporaryFileNames = Set<String>()
    @State private var showDeleteConfirm = false
    @State private var previewAttachment: QuickNoteAttachment?
    @State var alertMessage = ""
    @State var showAlert = false
    @State private var didCommit = false
    @State var showFinancialDraft = false
    @State var showDailyLogDraft = false
    @State var preparedDailyLogSeedPhotos: [DailyLogSeedPhoto] = []
    @State var isPreparingDailyLogDraft = false
    @State var isPreparingProjectDocument = false
    @State var dailyLogPreparationTask: Task<Void, Never>?
    @State var projectDocumentGenerationTask: Task<Void, Never>?
    @FocusState private var isContentFocused: Bool

    init(note: QuickNote, projects: [Project], onSave: @escaping (QuickNote) -> Void, onDelete: @escaping (QuickNote) -> Void) {
        self.note = note
        self.projects = projects
        self.onSave = onSave
        self.onDelete = onDelete
        _content = State(initialValue: note.content.isEmpty ? note.title : note.content)
        _projectId = State(initialValue: note.projectId)
        _attachments = State(initialValue: note.attachments)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("记录")) {
                    TextField(AppLocalization.string("随手记录"), text: $content, axis: .vertical)
                        .focused($isContentFocused)
                        .lineLimit(6...16)
                        .padding(10)
                        .frame(minHeight: 138, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.appStrokeSeparator, lineWidth: 0.5)
                        )
                }
                Section(AppLocalization.string("附件")) {
                    if attachments.isEmpty {
                        Text(AppLocalization.string("可追加媒体、拍照、手绘或 PDF/DWG/DXF/文档附件"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        QuickNoteAttachmentStrip(
                            attachments: attachments,
                            onPreview: { previewAttachment = $0 },
                            onRemove: removeAttachment(_:)
                        )
                    }
                    QuickNoteAttachmentPickerBar(projectName: projectName(projectId)) { attachment in
                        attachments.append(attachment)
                        temporaryFileNames.insert(attachment.fileName)
                    }
                }
                Section(AppLocalization.string("关联工程")) {
                    Picker(AppLocalization.string("工程"), selection: $projectId) {
                        Text(AppLocalization.string("不关联工程")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                conversionSection
                Section {
                    Button(AppLocalization.string("删除这条记录"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(AppLocalization.string("编辑随手记"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        didCommit = true
                        onSave(updatedNote)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                }
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar { isContentFocused = false }
            }
            .alert(AppLocalization.string("删除这条随手记？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
                Button(AppLocalization.string("删除"), role: .destructive) {
                    didCommit = true
                    onDelete(updatedNote)
                    dismiss()
                }
            }
            .alert(AppLocalization.string("随手记"), isPresented: $showAlert) {
                Button(AppLocalization.string("知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(item: $previewAttachment) { attachment in
                QuickNoteAttachmentPreview(attachment: attachment)
            }
            .sheet(isPresented: $showFinancialDraft) {
                if let projectId {
                    QuickNoteFinancialMemoSheet(
                        projectId: projectId,
                        initialNote: currentText.isEmpty ? updatedNote.title : currentText
                    ) { record in
                        store.appendProjectFinancialRecord(record)
                        store.scheduleSave()
                        showMessage(AppLocalization.string("已新增项目账目。"))
                    }
                }
            }
            .sheet(isPresented: $showDailyLogDraft) {
                if let projectId {
                    DailyLogView(
                        initialProjectId: projectId,
                        autoOpenComposer: true,
                        initialPhotoDrafts: preparedDailyLogSeedPhotos,
                        initialContent: currentText.isEmpty ? updatedNote.title : currentText
                    )
                }
            }
            .onDisappear {
                dailyLogPreparationTask?.cancel()
                dailyLogPreparationTask = nil
                projectDocumentGenerationTask?.cancel()
                projectDocumentGenerationTask = nil
                isPreparingDailyLogDraft = false
                isPreparingProjectDocument = false
                cleanupTemporaryAttachmentsIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var conversionSection: some View {
        Section(AppLocalization.string("转为")) {
            if projectId == nil {
                Text(AppLocalization.string("先关联工程后，可转为现场待办、施工日志、项目资料或记账备注。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { convertToTodo() } label: { Label(AppLocalization.string("转为现场待办"), systemImage: "checklist") }
                .disabled(projectId == nil)
            Button { convertToDailyLog() } label: {
                Label(
                    isPreparingDailyLogDraft ? AppLocalization.string("准备日志草稿…") : AppLocalization.string("转为施工日志"),
                    systemImage: isPreparingDailyLogDraft ? "hourglass" : "book.pages.fill"
                )
            }
                .disabled(projectId == nil || isPreparingDailyLogDraft)
            Button { convertToProjectDocument() } label: {
                Label(
                    isPreparingProjectDocument ? AppLocalization.string("生成项目资料中…") : AppLocalization.string("转为项目资料 PDF"),
                    systemImage: isPreparingProjectDocument ? "hourglass" : "doc.richtext"
                )
            }
                .disabled(projectId == nil || isPreparingProjectDocument)
            Button { convertToFinancialMemo() } label: { Label(AppLocalization.string("转为记账备注"), systemImage: "receipt") }
                .disabled(projectId == nil)
        }
    }

    var updatedNote: QuickNote {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = note
        value.title = QuickNoteText.title(from: trimmed, attachments: attachments)
        value.content = trimmed
        value.projectId = projectId
        value.attachments = attachments
        value.updatedAt = .now()
        return value
    }

    private func removeAttachment(_ attachment: QuickNoteAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        if temporaryFileNames.contains(attachment.fileName) {
            temporaryFileNames.remove(attachment.fileName)
            DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                [attachment.fileName],
                summary: "quickNoteEditor.removeTemporaryAttachment"
            )?.perform()
        }
    }

    private func cleanupTemporaryAttachmentsIfNeeded() {
        guard !didCommit else { return }
        DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
            Array(temporaryFileNames),
            summary: "quickNoteEditor.cleanupTemporaryAttachments"
        )?.perform()
        temporaryFileNames.removeAll()
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return projects.first(where: { $0.id == id })?.name ?? ""
    }
}
