import SwiftUI
import UIKit

struct QuickNoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    let note: QuickNote
    let projects: [Project]
    let onSave: (QuickNote) -> Void
    let onDelete: (QuickNote) -> Void

    @State private var content: String
    @State private var projectId: UUID?
    @State private var attachments: [QuickNoteAttachment]
    @State private var temporaryFileNames = Set<String>()
    @State private var showDeleteConfirm = false
    @State private var previewAttachment: QuickNoteAttachment?
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var didCommit = false
    @State private var showFinancialDraft = false
    @State private var showDailyLogDraft = false
    @State private var preparedDailyLogSeedPhotos: [DailyLogSeedPhoto] = []
    @State private var isPreparingDailyLogDraft = false
    @State private var isPreparingProjectDocument = false
    @State private var dailyLogPreparationTask: Task<Void, Never>?
    @State private var projectDocumentGenerationTask: Task<Void, Never>?
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
                Section("记录") {
                    TextField("随手记录", text: $content, axis: .vertical)
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
                Section("附件") {
                    if attachments.isEmpty {
                        Text("可追加媒体、拍照、手绘或 PDF/CAD/文档附件")
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
                Section("关联工程") {
                    Picker("工程", selection: $projectId) {
                        Text("不关联工程").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                conversionSection
                Section {
                    Button("删除这条记录", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("编辑随手记")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        didCommit = true
                        onSave(updatedNote)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isContentFocused = false }
                }
            }
            .alert("删除这条随手记？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    didCommit = true
                    onDelete(updatedNote)
                    dismiss()
                }
            }
            .alert("随手记", isPresented: $showAlert) {
                Button("知道了", role: .cancel) {}
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
                        store.projectFinancialRecords.append(record)
                        store.scheduleSave()
                        showMessage("已新增项目账目。")
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
        Section("转为") {
            if projectId == nil {
                Text("先关联工程后，可转为现场待办、施工日志、项目资料或记账备注。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { convertToTodo() } label: { Label("转为现场待办", systemImage: "checklist") }
                .disabled(projectId == nil)
            Button { convertToDailyLog() } label: {
                Label(isPreparingDailyLogDraft ? "准备日志草稿…" : "转为施工日志", systemImage: isPreparingDailyLogDraft ? "hourglass" : "book.pages.fill")
            }
                .disabled(projectId == nil || isPreparingDailyLogDraft)
            Button { convertToProjectDocument() } label: {
                Label(isPreparingProjectDocument ? "生成项目资料中…" : "转为项目资料 PDF", systemImage: isPreparingProjectDocument ? "hourglass" : "doc.richtext")
            }
                .disabled(projectId == nil || isPreparingProjectDocument)
            Button { convertToFinancialMemo() } label: { Label("转为记账备注", systemImage: "receipt") }
                .disabled(projectId == nil)
        }
    }

    private var updatedNote: QuickNote {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = note
        value.title = QuickNoteText.title(from: trimmed, attachments: attachments)
        value.content = trimmed
        value.projectId = projectId
        value.attachments = attachments
        value.updatedAt = Formatters.now()
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

    private func convertToTodo() {
        guard let projectId else { return showNeedProject() }
        let text = currentText
        store.siteTodos.append(SiteTodo(
            title: String((text.isEmpty ? updatedNote.title : text).prefix(40)),
            owner: "",
            dueDate: Formatters.date.string(from: Date()),
            note: text,
            projectId: projectId
        ))
        store.scheduleSave()
        showMessage("已新增现场待办。")
    }

    private func convertToDailyLog() {
        guard projectId != nil else { return showNeedProject() }
        dailyLogPreparationTask?.cancel()
        isPreparingDailyLogDraft = true
        dailyLogPreparationTask = Task {
            let seedPhotos = await buildDailyLogSeedPhotos()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                preparedDailyLogSeedPhotos = seedPhotos
                isPreparingDailyLogDraft = false
                showDailyLogDraft = true
                dailyLogPreparationTask = nil
            }
        }
    }

    private func buildDailyLogSeedPhotos() async -> [DailyLogSeedPhoto] {
        let candidates = Array(attachments.prefix(6))
        let seedNote = String(
            format: String(localized: "来源: 随手记\n记录时间: %@"),
            note.createdAt
        )
        let capturedAt = Formatters.dateTime.date(from: note.createdAt)
        var seedPhotos: [DailyLogSeedPhoto] = []
        for attachment in candidates where [.photo, .drawing].contains(attachment.attachmentKind) {
            guard !Task.isCancelled else { break }
            guard let data = await QuickNoteAttachmentStorage.dataAsync(for: attachment.fileName) else { continue }
            seedPhotos.append(
                DailyLogSeedPhoto(
                    data: data,
                    note: seedNote,
                    tag: .general,
                    capturedAt: capturedAt
                )
            )
        }
        return seedPhotos
    }

    private func convertToProjectDocument() {
        guard let projectId else { return showNeedProject() }
        projectDocumentGenerationTask?.cancel()
        isPreparingProjectDocument = true
        projectDocumentGenerationTask = Task {
            let imageDataByFileName = await buildProjectDocumentImageDataMap()
            guard !Task.isCancelled else { return }
            let pdfData = makeProjectDocumentPDF(imageDataByFileName: imageDataByFileName)
            let fileName: String
            do {
                fileName = try ProjectDocumentStorage.savePDFOrThrow(data: pdfData, projectId: projectId)
            } catch {
                await MainActor.run {
                    isPreparingProjectDocument = false
                    projectDocumentGenerationTask = nil
                    showMessage("项目资料生成失败：\(error.localizedDescription)")
                }
                return
            }
            await MainActor.run {
                store.projectDocuments.append(ProjectDocument(
                    projectId: projectId,
                    title: updatedNote.title.isEmpty ? "随手记资料" : updatedNote.title,
                    category: .constructionRecord,
                    fileName: fileName,
                    fileType: "pdf",
                    pageCount: 1,
                    note: "由随手记转入"
                ))
                store.scheduleSave()
                isPreparingProjectDocument = false
                projectDocumentGenerationTask = nil
                showMessage("已生成项目资料 PDF。")
            }
        }
    }

    private func convertToFinancialMemo() {
        guard projectId != nil else { return showNeedProject() }
        showFinancialDraft = true
    }

    private var currentText: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showNeedProject() {
        showMessage("请先关联工程。")
    }

    private func showMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func makeProjectDocumentPDF(imageDataByFileName: [String: Data]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 36
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            var y = margin
            y = drawText("随手记资料", atY: y, font: .boldSystemFont(ofSize: 22), page: page, margin: margin)
            y = drawText("生成时间: \(Formatters.now())", atY: y + 8, font: .systemFont(ofSize: 11), color: .secondaryLabel, page: page, margin: margin)
            if let projectId, let project = projects.first(where: { $0.id == projectId }) {
                y = drawText("关联工程: \(project.name)", atY: y + 4, font: .systemFont(ofSize: 11), color: .secondaryLabel, page: page, margin: margin)
            }
            y = drawText(currentText.isEmpty ? updatedNote.title : currentText, atY: y + 18, font: .systemFont(ofSize: 14), page: page, margin: margin)
            for attachment in attachments where [.photo, .drawing].contains(attachment.attachmentKind) {
                guard let data = imageDataByFileName[attachment.fileName], let image = UIImage(data: data) else { continue }
                if y > page.height - 260 {
                    context.beginPage()
                    y = margin
                }
                let maxWidth = page.width - margin * 2
                let ratio = min(maxWidth / image.size.width, 220 / image.size.height, 1)
                let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                image.draw(in: CGRect(x: margin, y: y + 12, width: size.width, height: size.height))
                y += size.height + 22
            }
        }
    }

    private func buildProjectDocumentImageDataMap() async -> [String: Data] {
        let imageAttachments = attachments.filter { [.photo, .drawing].contains($0.attachmentKind) }
        var dataByFileName: [String: Data] = [:]
        for attachment in imageAttachments {
            guard !Task.isCancelled else { break }
            guard let data = await QuickNoteAttachmentStorage.dataAsync(for: attachment.fileName) else { continue }
            dataByFileName[attachment.fileName] = data
        }
        return dataByFileName
    }

    private func drawText(_ text: String, atY y: CGFloat, font: UIFont, color: UIColor = .label, page: CGRect, margin: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: page.width - margin * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        (text as NSString).draw(in: CGRect(x: margin, y: y, width: page.width - margin * 2, height: ceil(rect.height)), withAttributes: attributes)
        return y + ceil(rect.height)
    }
}

private struct QuickNoteFinancialMemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let initialNote: String
    let onSave: (ProjectFinancialRecord) -> Void

    @State private var date = Date()
    @State private var direction: ProjectFinancialDirection = .expense
    @State private var category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var invoiceNumber = ""
    @State private var note: String

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    init(projectId: UUID, initialNote: String, onSave: @escaping (ProjectFinancialRecord) -> Void) {
        self.projectId = projectId
        self.initialNote = initialNote
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账目") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("类型", selection: $direction) {
                        ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("分类", selection: $category) {
                        ForEach(availableCategories, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("金额", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("对方单位/个人", text: $counterparty)
                    TextField("发票号/收据号", text: $invoiceNumber)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Text("随手记不会再直接生成空金额流水。补齐金额后才会写入项目财务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("转为项目记账")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(ProjectFinancialRecord(
                            projectId: projectId,
                            date: Formatters.date.string(from: date),
                            direction: direction,
                            category: category,
                            amount: amount,
                            counterparty: counterparty,
                            invoiceNumber: invoiceNumber,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(!InputValidator.nonNegativeNumber(amount) || ReportBuilder.number(amount) <= 0)
                }
            }
        }
    }
}
