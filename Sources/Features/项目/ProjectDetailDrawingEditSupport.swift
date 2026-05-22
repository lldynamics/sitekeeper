import SwiftUI

struct ProjectDrawingEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataStore.self) private var store
    let drawing: ProjectDrawing
    let relatedDrawings: [ProjectDrawing]
    let relatedLogs: [DailyLog]
    let relatedTodos: [SiteTodo]
    let relatedDocuments: [ProjectDocument]
    let onSave: (ProjectDrawing) -> Void
    let onDelete: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void

    @State private var name: String
    @State private var drawingNumber: String
    @State private var discipline: String
    @State private var floorArea: String
    @State private var version: String
    @State private var isCurrentVersion: Bool
    @State private var issuedAt: String
    @State private var receiver: String
    @State private var relatedLogDate: String
    @State private var linkedTodoIDs: Set<UUID>
    @State private var linkedLogIDs: Set<UUID>
    @State private var linkedDocumentIDs: Set<UUID>
    @State private var issueStatus: DrawingIssueStatus
    @State private var issueNote: String
    @State private var note: String
    @State private var showIssueSheet = false
    @State private var showDeleteConfirm = false

    init(
        drawing: ProjectDrawing,
        relatedDrawings: [ProjectDrawing] = [],
        relatedLogs: [DailyLog] = [],
        relatedTodos: [SiteTodo] = [],
        relatedDocuments: [ProjectDocument] = [],
        onSave: @escaping (ProjectDrawing) -> Void,
        onDelete: @escaping (ProjectDrawing) -> Void,
        onPreview: @escaping (ProjectDrawing) -> Void
    ) {
        self.drawing = drawing
        self.relatedDrawings = relatedDrawings
        self.relatedLogs = relatedLogs
        self.relatedTodos = relatedTodos
        self.relatedDocuments = relatedDocuments
        self.onSave = onSave
        self.onDelete = onDelete
        self.onPreview = onPreview
        _name = State(initialValue: drawing.name)
        _drawingNumber = State(initialValue: drawing.drawingNumber)
        _discipline = State(initialValue: drawing.discipline)
        _floorArea = State(initialValue: drawing.floorArea)
        _version = State(initialValue: drawing.version)
        _isCurrentVersion = State(initialValue: drawing.isCurrentVersion)
        _issuedAt = State(initialValue: drawing.issuedAt)
        _receiver = State(initialValue: drawing.receiver)
        _relatedLogDate = State(initialValue: drawing.relatedLogDate)
        _linkedTodoIDs = State(initialValue: Set(drawing.linkedTodoIDs))
        _linkedLogIDs = State(initialValue: Set(drawing.linkedLogIDs))
        _linkedDocumentIDs = State(initialValue: Set(drawing.linkedDocumentIDs))
        _issueStatus = State(initialValue: drawing.issueStatus)
        _issueNote = State(initialValue: drawing.issueNote)
        _note = State(initialValue: drawing.note)
    }

    private var requiresExternalViewer: Bool {
        ProjectDetailDrawingHelper.requiresExternalViewer(drawing.fileType)
    }

    private var hasLinkTargets: Bool {
        !relatedTodos.isEmpty || !relatedLogs.isEmpty || !relatedDocuments.isEmpty
    }

    private var availableTodoIDs: [UUID] {
        var seen = Set<UUID>()
        return (relatedTodos.map(\.id) + store.siteTodos.filter { $0.projectId == drawing.projectId }.map(\.id))
            .filter { seen.insert($0).inserted }
    }

    private var linkedIssueTodos: [SiteTodo] {
        let ids = linkedTodoIDs.union(drawing.linkedTodoIDs)
        return store.siteTodos
            .filter { ids.contains($0.id) && $0.projectId == drawing.projectId }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue && !rhs.isOverdue }
                return lhs.dueDate < rhs.dueDate
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "图纸台账")) {
                    TextField(String(localized: "图纸名称"), text: $name)
                    TextField(String(localized: "图号"), text: $drawingNumber)
                    TextField(String(localized: "专业"), text: $discipline)
                    TextField(String(localized: "楼层/区域"), text: $floorArea)
                    TextField(String(localized: "版本号（如 V2）"), text: $version)
                    Toggle(String(localized: "设为当前版本"), isOn: $isCurrentVersion)
                    OptionalProjectDatePicker(String(localized: "出图日期"), text: $issuedAt)
                    TextField(String(localized: "接收人"), text: $receiver)
                    LabeledContent(String(localized: "格式"), value: drawing.fileType.uppercased())
                    LabeledContent(String(localized: "导入时间"), value: drawing.importedAt)
                }
                Section(String(localized: "原件状态")) {
                    LabeledContent(String(localized: "文件状态"), value: drawing.fileAvailabilityStatus.displayName)
                    if !drawing.fileAvailabilityCheckedAt.isEmpty {
                        LabeledContent(String(localized: "检查时间"), value: drawing.fileAvailabilityCheckedAt)
                    }
                    let externalFailureReason = drawing.externalOpenFailureReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !externalFailureReason.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "外部打开失败原因"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(externalFailureReason)
                                .font(.callout)
                                .foregroundStyle(Color.appWarning)
                        }
                    }
                    if !drawing.externalOpenFailedAt.isEmpty {
                        LabeledContent(String(localized: "外部失败时间"), value: drawing.externalOpenFailedAt)
                    }
                }
                Section(String(localized: "状态与备注")) {
                    OptionalProjectDatePicker(String(localized: "关联日志日期"), text: $relatedLogDate)
                    Picker(String(localized: "问题状态"), selection: $issueStatus) {
                        ForEach(DrawingIssueStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField(String(localized: "问题标记"), text: $issueNote, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section(String(localized: "图纸问题单")) {
                    Button {
                        showIssueSheet = true
                    } label: {
                        Label(String(localized: "新建问题"), systemImage: "exclamationmark.bubble.fill")
                    }
                    .buttonStyle(.appProminent())
                    if linkedIssueTodos.isEmpty {
                        Text(String(localized: "新增后会生成现场待办，并自动关联当前图纸。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedIssueTodos) { todo in
                            DrawingIssueTodoLabel(todo: todo)
                        }
                    }
                    Text(String(localized: "问题单会进入现场待办，可用完成状态做闭环，不写入 DWG 红线。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !hasLinkTargets {
                    Section(String(localized: "关联记录")) {
                        Text(String(localized: "当前项目暂无可关联的待办、日志或资料。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !relatedTodos.isEmpty {
                    Section(String(localized: "关联待办")) {
                        ForEach(relatedTodos) { todo in
                            Toggle(isOn: selectionBinding(for: todo.id, selection: $linkedTodoIDs)) {
                                DrawingLinkedTodoLabel(todo: todo)
                            }
                        }
                    }
                }
                if !relatedLogs.isEmpty {
                    Section(String(localized: "关联日志")) {
                        ForEach(relatedLogs) { log in
                            Toggle(isOn: selectionBinding(for: log.id, selection: $linkedLogIDs)) {
                                DrawingLinkedLogLabel(log: log)
                            }
                        }
                    }
                }
                if !relatedDocuments.isEmpty {
                    Section(String(localized: "关联资料")) {
                        ForEach(relatedDocuments) { document in
                            Toggle(isOn: selectionBinding(for: document.id, selection: $linkedDocumentIDs)) {
                                DrawingLinkedDocumentLabel(document: document)
                            }
                        }
                    }
                }
                if requiresExternalViewer {
                    Section(String(localized: "图纸原件")) {
                        Text(String(localized: "DWG / DXF 作为图纸原件管理，需通过外部专业看图软件打开；App 保留台账、版本、当前版和交付导出。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        onPreview(drawing)
                    } label: {
                        Label(
                            requiresExternalViewer ? String(localized: "用外部专业看图软件打开") : String(localized: "打开原件"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }
                Section {
                    Button(String(localized: "删除图纸"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "图纸详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = drawing
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.name = trimmed.isEmpty ? drawing.name : trimmed
                        updated.drawingNumber = drawingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.discipline = discipline.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.floorArea = floorArea.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.version = version
                        updated.isCurrentVersion = isCurrentVersion
                        updated.issuedAt = ProjectDateInput.normalizedStorageText(issuedAt)
                        updated.receiver = receiver.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.relatedLogDate = ProjectDateInput.normalizedStorageText(relatedLogDate)
                        updated.linkedTodoIDs = orderedLinkedIDs(from: availableTodoIDs, selection: linkedTodoIDs)
                        updated.linkedLogIDs = orderedLinkedIDs(from: relatedLogs.map(\.id), selection: linkedLogIDs)
                        updated.linkedDocumentIDs = orderedLinkedIDs(from: relatedDocuments.map(\.id), selection: linkedDocumentIDs)
                        if updated.relatedLogDate.isEmpty,
                           let firstLinkedLog = relatedLogs.first(where: { updated.linkedLogIDs.contains($0.id) }) {
                            updated.relatedLogDate = firstLinkedLog.date
                        }
                        updated.issueStatus = issueStatus
                        updated.issueNote = issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = note
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "删除这份图纸？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete(drawing)
                    dismiss()
                }
            } message: {
                Text(String(localized: "删除后将无法在项目中打开或导出该图纸原件。"))
            }
            .sheet(isPresented: $showIssueSheet) {
                ProjectDrawingIssueSheet(drawing: draftDrawingForIssue) { todo in
                    createDrawingIssue(todo)
                }
            }
        }
    }

    private func selectionBinding(for id: UUID, selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(id)
                } else {
                    selection.wrappedValue.remove(id)
                }
            }
        )
    }

    private func orderedLinkedIDs(from ids: [UUID], selection: Set<UUID>) -> [UUID] {
        ids.filter { selection.contains($0) }
    }

    private var draftDrawingForIssue: ProjectDrawing {
        var value = drawing
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? drawing.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingNumber = drawingNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        value.discipline = discipline.trimmingCharacters(in: .whitespacesAndNewlines)
        value.floorArea = floorArea.trimmingCharacters(in: .whitespacesAndNewlines)
        value.version = ProjectDetailDrawingHelper.normalizedVersion(version)
        value.isCurrentVersion = isCurrentVersion
        value.issuedAt = ProjectDateInput.normalizedStorageText(issuedAt)
        value.receiver = receiver.trimmingCharacters(in: .whitespacesAndNewlines)
        value.relatedLogDate = ProjectDateInput.normalizedStorageText(relatedLogDate)
        value.linkedTodoIDs = orderedLinkedIDs(from: availableTodoIDs, selection: linkedTodoIDs)
        value.linkedLogIDs = orderedLinkedIDs(from: relatedLogs.map(\.id), selection: linkedLogIDs)
        value.linkedDocumentIDs = orderedLinkedIDs(from: relatedDocuments.map(\.id), selection: linkedDocumentIDs)
        value.issueStatus = issueStatus
        value.issueNote = issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note
        return value
    }

    private func createDrawingIssue(_ todo: SiteTodo) {
        store.insertSiteTodoAtTop(todo)
        linkedTodoIDs.insert(todo.id)
        if issueStatus == .none {
            issueStatus = .open
        }
        if issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issueNote = todo.title
        }
        var updated = draftDrawingForIssue
        updated.linkedTodoIDs = orderedLinkedIDs(from: availableTodoIDs + [todo.id], selection: linkedTodoIDs)
        if updated.issueStatus == .none {
            updated.issueStatus = .open
        }
        onSave(updated)
        store.scheduleSave()
    }
}
