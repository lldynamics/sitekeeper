import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ProjectDateInput {
    static func date(from text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Formatters.parseDateOrDateTime(normalized)
    }

    static func string(from date: Date) -> String {
        Formatters.date.string(from: date)
    }

    static func normalizedStorageText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return date(from: normalized).map(string(from:)) ?? normalized
    }
}

struct OptionalProjectDatePicker: View {
    private let title: String
    private let emptyToggleTitle: String
    @Binding private var text: String
    @State private var hasDate: Bool
    @State private var selectedDate: Date

    init(_ title: String, text: Binding<String>, defaultDate: Date = Date()) {
        self.title = title
        self.emptyToggleTitle = String(format: String(localized: "填写%@"), title)
        _text = text
        let parsed = ProjectDateInput.date(from: text.wrappedValue)
        _hasDate = State(initialValue: parsed != nil)
        _selectedDate = State(initialValue: parsed ?? defaultDate)
    }

    var body: some View {
        Toggle(emptyToggleTitle, isOn: Binding(
            get: { hasDate },
            set: { newValue in
                hasDate = newValue
                text = newValue ? ProjectDateInput.string(from: selectedDate) : ""
            }
        ))
        if hasDate {
            DatePicker(title, selection: Binding(
                get: { selectedDate },
                set: { newValue in
                    selectedDate = newValue
                    text = ProjectDateInput.string(from: newValue)
                }
            ), displayedComponents: .date)
            .onAppear {
                text = ProjectDateInput.string(from: selectedDate)
            }
        }
    }
}

enum ProjectDetailMode: String, CaseIterable {
    case overview
    case records
    case assets
    case finance
    case timeline

    static var allCases: [ProjectDetailMode] {
        [.overview, .records, .assets, .finance, .timeline]
    }

    var displayName: String {
        switch self {
        case .overview: String(localized: "概览")
        case .records: String(localized: "现场")
        case .assets: String(localized: "资料")
        case .finance: String(localized: "成本")
        case .timeline: String(localized: "时间线")
        }
    }
}

enum ProjectFinanceJumpFilter: Equatable {
    case none
    case unsettled
    case missingReceipt
}

enum DrawingListFilter: String, CaseIterable {
    case all
    case current
    case withIssue

    var displayName: String {
        switch self {
        case .all: String(localized: "台账")
        case .current: String(localized: "当前版")
        case .withIssue: String(localized: "有问题")
        }
    }
}

struct ProjectPhotoItem: Identifiable {
    var id: UUID { photo.id }
    let logId: UUID
    let date: String
    let photo: LogPhoto
}

struct ProjectPhotoContext: Identifiable {
    var id: String { "\(logId.uuidString)-\(photoId.uuidString)" }
    let logId: UUID
    let photoId: UUID
    let legacyFileName: String
}

struct DrawingTimelineContext: Identifiable {
    var id: String { name }
    let name: String
}

struct ProjectDrawingTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawingName: String
    let drawings: [ProjectDrawing]
    let onSetCurrent: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void
    let onEdit: (ProjectDrawing) -> Void

    var body: some View {
        NavigationStack {
            List {
                if drawings.isEmpty {
                    ContentUnavailableView(
                        String(localized: "暂无版本记录"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text(String(localized: "同名图纸导入新版本后，可在这里查看版本时间线。"))
                    )
                } else {
                    ForEach(drawings) { drawing in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(drawing.version).font(.callout.weight(.semibold))
                        if drawing.isCurrentVersion {
                            Text(String(localized: "当前版"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appSuccess)
                        }
                        Spacer()
                        Text(drawing.importedAt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    FlowTagLine(tags: drawingTimelineTags(for: drawing))
                    if !drawing.relatedLogDate.isEmpty {
                        Text(String(format: String(localized: "关联日志: %@"), drawing.relatedLogDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                            if drawing.issueStatus != .none {
                                Text(String(format: String(localized: "状态: %@"), drawing.issueStatus.displayName))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            if !drawing.issueNote.isEmpty {
                                Text(String(format: String(localized: "问题: %@"), drawing.issueNote))
                                    .font(.caption2)
                                    .foregroundStyle(.appRisk)
                            }
                            HStack(spacing: 16) {
                                Button(String(localized: "打开")) {
                                    onPreview(drawing)
                                }
                                .font(.caption)
                                Button(String(localized: "编辑")) {
                                    onEdit(drawing)
                                    dismiss()
                                }
                                .font(.caption)
                                if !drawing.isCurrentVersion {
                                    Button(String(localized: "设为当前版")) {
                                        onSetCurrent(drawing)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(String(format: String(localized: "%@ 时间线"), drawingName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
    }

    private func drawingTimelineTags(for drawing: ProjectDrawing) -> [String] {
        [
            drawing.drawingNumber.isEmpty ? "" : String(format: String(localized: "图号: %@"), drawing.drawingNumber),
            drawing.discipline,
            drawing.floorArea,
            drawing.issuedAt.isEmpty ? "" : String(format: String(localized: "出图: %@"), drawing.issuedAt),
            drawing.receiver.isEmpty ? "" : String(format: String(localized: "接收: %@"), drawing.receiver)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

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

    private var isCADSource: Bool {
        ProjectDetailDrawingHelper.isCADSource(drawing.fileType)
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
                if isCADSource {
                    Section(String(localized: "图纸原件")) {
                        Text(String(localized: "DWG / DXF 作为原件资料管理，可交给专业看图软件打开；PDF 使用系统预览。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        onPreview(drawing)
                    } label: {
                        Label(
                            isCADSource ? String(localized: "用专业看图软件打开") : String(localized: "打开原件"),
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

private struct DrawingLinkedTodoLabel: View {
    let todo: SiteTodo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(todo.title.isEmpty ? String(localized: "未命名待办") : todo.title)
            Text(todoSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var todoSummary: String {
        [
            todo.isDone ? String(localized: "已完成") : String(localized: "未完成"),
            todo.priority.displayName,
            todo.issueType.displayName,
            todo.dueDate
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " · ")
    }
}

private struct DrawingLinkedLogLabel: View {
    let log: DailyLog

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(log.date)
            Text(log.content.isEmpty ? String(localized: "未填写日志内容") : log.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct DrawingLinkedDocumentLabel: View {
    let document: ProjectDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title.isEmpty ? document.fileName : document.title)
            Text(documentSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var documentSummary: String {
        [
            document.category.displayName,
            document.versionLabel,
            document.submissionStatus.displayName,
            document.formedAt
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: " · ")
    }
}

private struct DrawingIssueTodoLabel: View {
    let todo: SiteTodo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : todo.isOverdue ? "exclamationmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.appSuccess : todo.isOverdue ? Color.appRisk : Color.appWarning)
                Text(todo.title.isEmpty ? String(localized: "未命名待办") : todo.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer()
                Text(todo.priority.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appWarning)
            }
            FlowTagLine(tags: issueTags)
            if !todo.note.isEmpty {
                Text(todo.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if todo.rectificationBeforePhotoFileName != nil || todo.rectificationAfterPhotoFileName != nil {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text(String(localized: "已附照片/截图"))
                }
                .font(.caption2)
                .foregroundStyle(Color.appDoc)
            }
        }
        .padding(.vertical, 2)
    }

    private var issueTags: [String] {
        [
            todo.isDone ? String(localized: "已完成") : String(localized: "未完成"),
            todo.owner.isEmpty ? "" : String(format: String(localized: "责任人 %@"), todo.owner),
            todo.dueDate.isEmpty ? "" : String(format: String(localized: "截止 %@"), todo.dueDate),
            todo.issueType.displayName
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private struct ProjectDrawingIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawing: ProjectDrawing
    let onCreate: (SiteTodo) -> Void

    @State private var descriptionText = ""
    @State private var owner = ""
    @State private var dueDate = Date()
    @State private var priority: TodoPriority = .high
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoFileName: String?
    @State private var showImagePicker = false
    @State private var didCommit = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var photoImportTask: Task<Void, Never>?
    @State private var createdDraftPhotoFileNames: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "图纸问题单")) {
                    LabeledContent(String(localized: "图纸"), value: drawingTitle)
                    TextField(String(localized: "问题说明"), text: $descriptionText, axis: .vertical)
                        .lineLimit(3...8)
                    TextField(String(localized: "责任人"), text: $owner)
                    DatePicker(String(localized: "截止日期"), selection: $dueDate, displayedComponents: .date)
                    Picker(String(localized: "优先级"), selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
                Section(String(localized: "照片/截图")) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            photoFileName == nil ? String(localized: "添加照片/截图") : String(localized: "替换照片/截图"),
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showImagePicker = true
                        } label: {
                            Label(String(localized: "拍照"), systemImage: "camera.fill")
                        }
                    }
                    if let photoFileName {
                        VStack(alignment: .leading, spacing: 8) {
                            AsyncPhotoThumbnailImageView(fileName: photoFileName) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(uiColor: .secondarySystemFill))
                                    .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 180)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            Button(String(localized: "移除"), role: .destructive) {
                                clearPhoto()
                            }
                            .font(.caption)
                        }
                    }
                }
                Section {
                    Text(String(localized: "问题单会进入现场待办，可用完成状态做闭环，不写入 DWG 红线。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "新建问题"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        didCommit = true
                        onCreate(makeTodo())
                        createdDraftPhotoFileNames.removeAll()
                        dismiss()
                    }
                    .disabled(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(sourceType: .camera) { image in
                    saveCameraImage(image)
                }
            }
            .alert(String(localized: "图纸问题单"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedPhotoItem) { _, item in
                photoImportTask?.cancel()
                photoImportTask = Task { await importSelectedPhoto(item) }
            }
            .onDisappear {
                photoImportTask?.cancel()
                photoImportTask = nil
                if !didCommit {
                    cleanupCreatedDraftPhotoFiles()
                }
            }
        }
    }

    private var drawingTitle: String {
        let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? drawing.fileName : name
    }

    private func makeTodo() -> SiteTodo {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SiteTodo(
            title: String(format: String(localized: "图纸问题: %@"), drawingTitle),
            owner: owner.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: Formatters.date.string(from: dueDate),
            priority: priority,
            issueType: .quality,
            rectificationBeforePhotoFileName: photoFileName,
            note: issueNoteText(description: text),
            projectId: drawing.projectId
        )
    }

    private func issueNoteText(description: String) -> String {
        [
            String(localized: "来源: 图纸问题单"),
            String(format: String(localized: "图纸: %@"), drawingTitle),
            String(format: String(localized: "版本: %@"), drawing.version),
            drawing.drawingNumber.isEmpty ? "" : String(format: String(localized: "图号: %@"), drawing.drawingNumber),
            drawing.floorArea.isEmpty ? "" : String(format: String(localized: "楼层/区域: %@"), drawing.floorArea),
            description
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func saveCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.82) ?? image.pngData() else {
            alertMessage = String(localized: "图纸问题照片保存失败：图片数据不可用")
            showAlert = true
            return
        }
        Task { await savePhotoData(data) }
    }

    private func importSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else { return }
            data = loaded
        } catch {
            await MainActor.run {
                alertMessage = String(format: String(localized: "图纸问题照片导入失败：%@"), error.localizedDescription)
                showAlert = true
            }
            return
        }
        guard !Task.isCancelled else { return }
        await savePhotoData(data)
    }

    @MainActor
    private func savePhotoData(_ data: Data) async {
        let normalizedData = normalizePhotoData(data, maxPixelSize: 1600, compressionQuality: 0.82) ?? data
        let fileName = "drawing-issue-\(drawing.id.uuidString)-\(UUID().uuidString).jpg"
        let saved: String
        do {
            saved = try PhotoStorage.saveOrThrow(original: normalizedData, fileName: fileName)
        } catch {
            alertMessage = String(format: String(localized: "图纸问题照片保存失败：%@"), error.localizedDescription)
            showAlert = true
            return
        }
        deleteDraftPhotoIfNeeded(photoFileName)
        createdDraftPhotoFileNames.insert(saved)
        photoFileName = saved
        selectedPhotoItem = nil
    }

    private func clearPhoto() {
        deleteDraftPhotoIfNeeded(photoFileName)
        photoFileName = nil
    }

    private func deleteDraftPhotoIfNeeded(_ fileName: String?) {
        guard let fileName, createdDraftPhotoFileNames.remove(fileName) != nil else { return }
        DataStoreDeferredFileCleanup.photoFiles(
            [fileName],
            summary: "drawingIssue.draftPhoto"
        )?.perform()
    }

    private func cleanupCreatedDraftPhotoFiles() {
        let fileNames = createdDraftPhotoFileNames
        createdDraftPhotoFileNames.removeAll()
        DataStoreDeferredFileCleanup.photoFiles(
            Array(fileNames),
            summary: "drawingIssue.createdDraftPhotos"
        )?.perform()
    }

    private func normalizePhotoData(_ data: Data, maxPixelSize: CGFloat, compressionQuality: CGFloat) -> Data? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: CFDictionary = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}

struct MaterialEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MaterialItem
    let useMetric: Bool
    let onSave: (MaterialItem) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var unitPrice: String
    @State private var specification: String
    @State private var brand: String
    @State private var supplier: String
    @State private var purchaseStatus: MaterialPurchaseStatus
    @State private var arrivalDate: String

    init(item: MaterialItem, useMetric: Bool, onSave: @escaping (MaterialItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.useMetric = useMetric
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity)
        _unit = State(initialValue: item.unit)
        _unitPrice = State(initialValue: item.unitPrice)
        _specification = State(initialValue: item.specification)
        _brand = State(initialValue: item.brand)
        _supplier = State(initialValue: item.supplier)
        _purchaseStatus = State(initialValue: item.purchaseStatus)
        _arrivalDate = State(initialValue: item.arrivalDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "材料名称"), text: $name)
                TextField(String(localized: "数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(String(localized: "单位"), text: $unit)
                TextField(String(localized: "单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "规格"), text: $specification)
                TextField(String(localized: "品牌"), text: $brand)
                TextField(String(localized: "供应商"), text: $supplier)
                Picker(String(localized: "采购状态"), selection: $purchaseStatus) {
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(String(localized: "进场日期"), text: $arrivalDate)
                LabeledContent(String(localized: "金额")) {
                    Text(ReportBuilder.money(ReportBuilder.number(quantity) * ReportBuilder.number(unitPrice)))
                }
                Section {
                    Button(String(localized: "删除材料"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑材料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = item
                        updated.name = name
                        updated.quantity = NumericInputSupport.normalizedStorageText(quantity, kind: .quantity)
                        updated.unit = unit
                        updated.unitPrice = NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount)
                        updated.specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.supplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.purchaseStatus = purchaseStatus
                        updated.arrivalDate = ProjectDateInput.normalizedStorageText(arrivalDate)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(unitPrice, kind: .amount, requirement: .optionalNonNegative).isValid)
                }
            }
        }
    }
}

struct QuoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: QuoteItem
    let onSave: (QuoteItem) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var unitPrice: String
    @State private var quantity: String
    @State private var unit: String
    @State private var taxRate: String
    @State private var discountRate: String
    @State private var notes: String
    @State private var versionName: String
    @State private var status: QuoteStatus
    @State private var customerConfirmedDate: String
    @State private var contractAmount: String

    init(item: QuoteItem, onSave: @escaping (QuoteItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _unitPrice = State(initialValue: item.unitPrice)
        _quantity = State(initialValue: item.quantity)
        _unit = State(initialValue: item.unit)
        _taxRate = State(initialValue: item.taxRate)
        _discountRate = State(initialValue: item.discountRate)
        _notes = State(initialValue: item.notes)
        _versionName = State(initialValue: item.versionName)
        _status = State(initialValue: item.status)
        _customerConfirmedDate = State(initialValue: item.customerConfirmedDate)
        _contractAmount = State(initialValue: item.contractAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "项目名称"), text: $name)
                TextField(String(localized: "单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(String(localized: "单位"), text: $unit)
                TextField(String(localized: "税率"), text: $taxRate.numericInput(.taxRate)).keyboardType(.decimalPad)
                TextField(String(localized: "折扣"), text: $discountRate.numericInput(.discountRate)).keyboardType(.decimalPad)
                TextField(String(localized: "版本"), text: $versionName)
                Picker(String(localized: "状态"), selection: $status) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $customerConfirmedDate)
                TextField(String(localized: "转合同金额"), text: $contractAmount.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "备注"), text: $notes)
                LabeledContent(String(localized: "合计")) {
                    let preview = QuoteItem(
                        id: item.id,
                        name: name,
                        unitPrice: unitPrice,
                        quantity: quantity,
                        unit: unit,
                        notes: notes,
                        taxRate: taxRate,
                        discountRate: discountRate,
                        versionName: versionName,
                        status: status,
                        customerConfirmedDate: customerConfirmedDate,
                        contractAmount: contractAmount,
                        projectId: item.projectId
                    )
                    Text(ReportBuilder.money(ReportBuilder.quoteGrandTotal(preview)))
                }
                Section {
                    Button(String(localized: "删除报价"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑报价"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = item
                        updated.name = name
                        updated.unitPrice = NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount)
                        updated.quantity = NumericInputSupport.normalizedStorageText(quantity, kind: .quantity)
                        updated.unit = unit
                        updated.taxRate = NumericInputSupport.normalizedStorageText(taxRate, kind: .taxRate)
                        updated.discountRate = NumericInputSupport.normalizedStorageText(discountRate, kind: .discountRate)
                        updated.versionName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.status = status
                        updated.customerConfirmedDate = ProjectDateInput.normalizedStorageText(customerConfirmedDate)
                        updated.contractAmount = NumericInputSupport.normalizedStorageText(contractAmount, kind: .amount)
                        updated.notes = notes
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.validate(unitPrice, kind: .amount, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(taxRate, kind: .taxRate, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(discountRate, kind: .discountRate, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(contractAmount, kind: .amount, requirement: .optionalNonNegative).isValid)
                }
            }
        }
    }
}

struct ProgressEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ProgressTask
    let onSave: (ProgressTask) -> Void
    let onDelete: (UUID) -> Void

    @State private var title: String
    @State private var startDate: String
    @State private var dueDate: String
    @State private var completion: Double
    @State private var note: String

    init(item: ProgressTask, onSave: @escaping (ProgressTask) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _startDate = State(initialValue: item.startDate)
        _dueDate = State(initialValue: item.dueDate)
        _completion = State(initialValue: item.clampedCompletion)
        _note = State(initialValue: item.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "任务"), text: $title)
                OptionalProjectDatePicker(String(localized: "开始日期"), text: $startDate)
                OptionalProjectDatePicker(String(localized: "截止日期"), text: $dueDate)
                Slider(value: $completion, in: 0...1, step: 0.05)
                LabeledContent(String(localized: "完成率"), value: "\(Int(completion * 100))%")
                TextField(String(localized: "备注"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                Section {
                    Button(String(localized: "删除任务"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑进度"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = item
                        updated.title = title
                        updated.startDate = ProjectDateInput.normalizedStorageText(startDate)
                        updated.dueDate = ProjectDateInput.normalizedStorageText(dueDate)
                        updated.completion = completion
                        updated.note = note
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ProjectPhotoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let context: ProjectPhotoContext
    let allLogs: [DailyLog]
    let onSave: (String, PhotoTag) -> Void
    let onDelete: () -> Void

    @State private var note = ""
    @State private var tag: PhotoTag = .general
    @State private var showDeleteConfirm = false
    @State private var previewImage: UIImage?
    @State private var didAttemptLoadImage = false

    private var selectedPhoto: LogPhoto? {
        allLogs.first(where: { $0.id == context.logId })?
            .photoAttachments
            .first(where: { $0.id == context.photoId || $0.fileName == context.legacyFileName })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "照片预览")) {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if !didAttemptLoadImage {
                        ProgressView(String(localized: "加载中…"))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "图片已丢失或不可读取"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "备注")) {
                    Picker(String(localized: "照片标签"), selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "现场备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(String(localized: "保存")) {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button(String(localized: "删除照片"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(String(localized: "照片详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .task(id: selectedPhoto?.fileName) {
                await loadPreviewImage()
            }
            .alert(String(localized: "删除这张照片？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "该操作仅删除当前照片，不会删除整条日志。"))
            }
        }
    }

    private func loadPreviewImage() async {
        didAttemptLoadImage = false
        previewImage = nil
        guard let fileName = selectedPhoto?.fileName else {
            didAttemptLoadImage = true
            return
        }
        if let data = await PhotoStorage.dataAsync(for: fileName),
           let image = UIImage(data: data) {
            previewImage = image
            didAttemptLoadImage = true
            return
        }
        if let thumbnail = await PhotoStorage.thumbnailAsync(for: fileName) {
            previewImage = thumbnail
        }
        didAttemptLoadImage = true
    }
}

struct QuickAddSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sheet: DetailSheet
    let projectId: UUID
    let constructionMethods: [ConstructionMethod]

    @State private var name = ""; @State private var qty = ""; @State private var unit = ""
    @State private var unitPrice = ""
    @State private var materialSpecification = ""
    @State private var materialBrand = ""
    @State private var materialSupplier = ""
    @State private var materialPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State private var materialArrivalDate = ""
    @State private var price = ""
    @State private var quoteVersionName = "V1"
    @State private var quoteStatus: QuoteStatus = .draft
    @State private var quoteConfirmedDate = ""
    @State private var quoteContractAmount = ""
    @State private var workers = ""
    @State private var laborTeamName = ""
    @State private var laborIsSettled = false
    @State private var laborLines: [QuickAddLaborLine] = [.init()]
    @State private var content = ""; @State private var weather = String(localized: "晴")
    @State private var safety = ""; @State private var materials = ""
    @State private var tomorrowPlan = ""; @State private var qualityIssue = ""
    @State private var rectification = ""; @State private var confirmer = ""
    @State private var logDate = Date()
    @State private var laborDate = Date()
    @State private var linkedMethodIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                switch sheet {
                case .material:
                    TextField(String(localized: "材料名称"), text: $name)
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "米 / 卷 / 个"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单价")) {
                        TextField("0", text: $unitPrice.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "规格型号"), text: $materialSpecification)
                    TextField(String(localized: "品牌"), text: $materialBrand)
                    TextField(String(localized: "供应商"), text: $materialSupplier)
                    Picker(String(localized: "采购状态"), selection: $materialPurchaseStatus) {
                        ForEach(MaterialPurchaseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "进场日期"), text: $materialArrivalDate)
                case .quote:
                    TextField(String(localized: "项目名称"), text: $name)
                    LabeledContent(String(localized: "单价 ¥")) {
                        TextField("0", text: $price.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "项 / 米 / 台"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "版本"), text: $quoteVersionName)
                    Picker(String(localized: "状态"), selection: $quoteStatus) {
                        ForEach(QuoteStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $quoteConfirmedDate)
                    TextField(String(localized: "转合同金额"), text: $quoteContractAmount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                case .log:
                    DatePicker(String(localized: "日期"), selection: $logDate, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $weather) {
                        ForEach([String(localized: "晴"), String(localized: "多云"), String(localized: "阴"), String(localized: "小雨"), String(localized: "大雨"), String(localized: "雪")], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $workers)
                    TextField(String(localized: "内容"), text: $content, axis: .vertical).lineLimit(3...6)
                    TextField(String(localized: "安全事项"), text: $safety, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "材料进场"), text: $materials, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "明日计划"), text: $tomorrowPlan, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $qualityIssue, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $rectification, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $confirmer)
                    Section(String(localized: "关联施工工艺")) {
                        if constructionMethods.isEmpty {
                            Text(String(localized: "暂无可关联工艺，请先在施工工艺库新增条目。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(constructionMethods) { method in
                                Toggle(isOn: methodBinding(for: method.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(methodTitle(method))
                                        HStack(spacing: 6) {
                                            if !method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(method.trade)
                                            }
                                            Text(method.versionName.isEmpty ? "V1" : method.versionName)
                                            Text(method.publishStatus.displayName)
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case .labor:
                    DatePicker(String(localized: "日期"), selection: $laborDate, displayedComponents: .date)
                    TextField(String(localized: "班组（可选）"), text: $laborTeamName)
                    Toggle(String(localized: "已结算"), isOn: $laborIsSettled)
                    ForEach($laborLines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(format: String(localized: "工种 %@"), laborLineTitle(for: line.id)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if laborLines.count > 1 {
                                    Button(role: .destructive) {
                                        removeLaborLine(id: line.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            TextField(String(localized: "工种"), text: $line.workType)
                            HStack(spacing: 10) {
                                TextField(String(localized: "人数"), text: $line.workers.numericInput(.quantity))
                                    .keyboardType(.numberPad)
                                TextField(String(localized: "工时 (h)"), text: $line.hours.numericInput(.days))
                                    .keyboardType(.decimalPad)
                            }
                            TextField(String(localized: "工价（每工时）"), text: $line.unitRate.numericInput(.laborRate))
                                .keyboardType(.decimalPad)
                            TextField(String(localized: "备注"), text: $line.note)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        laborLines.append(.init())
                    } label: {
                        Label(String(localized: "添加工种"), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(sheetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        if save() {
                            dismiss()
                        }
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var sheetTitle: String {
        switch sheet {
        case .material: return String(localized: "添加材料")
        case .quote: return String(localized: "添加报价")
        case .log: return String(localized: "写施工日志")
        case .labor: return String(localized: "记人工")
        }
    }

    private func save() -> Bool {
        switch sheet {
        case .material:
            guard !name.isEmpty else { return false }
            store.appendMaterialItem(
                MaterialItem(
                    name: name,
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    unitPrice: NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount),
                    specification: materialSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: materialBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                    supplier: materialSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                    purchaseStatus: materialPurchaseStatus,
                    arrivalDate: ProjectDateInput.normalizedStorageText(materialArrivalDate),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .quote:
            guard !name.isEmpty else { return false }
            store.appendQuoteItem(
                QuoteItem(
                    name: name,
                    unitPrice: NumericInputSupport.normalizedStorageText(price, kind: .amount),
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    notes: "",
                    taxRate: "0",
                    discountRate: "0",
                    versionName: quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: quoteStatus,
                    customerConfirmedDate: ProjectDateInput.normalizedStorageText(quoteConfirmedDate),
                    contractAmount: NumericInputSupport.normalizedStorageText(quoteContractAmount, kind: .amount),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .log:
            store.insertDailyLogAtTop(DailyLog(
                date: Formatters.date.string(from: logDate),
                weather: weather,
                content: content,
                workers: workers,
                photoFileName: nil,
                safety: safety,
                materials: materials,
                tomorrowPlan: tomorrowPlan,
                qualityIssue: qualityIssue,
                rectification: rectification,
                confirmer: confirmer,
                linkedConstructionMethodIDs: sortedLinkedMethodIDs(),
                projectId: projectId
            ))
            store.scheduleSave()
            return true
        case .labor:
            guard canSaveLaborLines else { return false }
            let teamName = laborTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = Formatters.date.string(from: laborDate)
            var appendedCount = 0
            for line in laborLines where line.hasContent {
                let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
                let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
                let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
                let workType = line.workType.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = line.note.trimmingCharacters(in: .whitespacesAndNewlines)
                store.appendLaborRecord(
                    LaborRecord(
                        date: date,
                        workers: NumericInputSupport.normalizedStorageText(workers, kind: .quantity),
                        hours: NumericInputSupport.normalizedStorageText(hours, kind: .days),
                        unitRate: NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate),
                        workType: workType,
                        teamName: teamName,
                        isSettled: laborIsSettled,
                        note: note,
                        projectId: projectId
                    )
                )
                appendedCount += 1
            }
            guard appendedCount > 0 else { return false }
            store.scheduleSave()
            return true
        }
    }

    private func laborLineTitle(for id: UUID) -> String {
        if let index = laborLines.firstIndex(where: { $0.id == id }) {
            return "#\(index + 1)"
        }
        return ""
    }

    private func removeLaborLine(id: UUID) {
        guard laborLines.count > 1 else { return }
        laborLines.removeAll { $0.id == id }
    }

    private var canSaveLaborLines: Bool {
        let filledLines = laborLines.filter(\.hasContent)
        guard !filledLines.isEmpty else { return false }
        return filledLines.allSatisfy { line in
            let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
            let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard InputValidator.validate(workers, kind: .quantity, requirement: .requiredNonNegative).isValid,
                  InputValidator.validate(hours, kind: .days, requirement: .requiredNonNegative).isValid else { return false }
            return InputValidator.validate(unitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isOn in
                if isOn {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        linkedMethodIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "未命名工艺") : title
    }
}

private struct QuickAddLaborLine: Identifiable {
    var id = UUID()
    var workType = ""
    var workers = ""
    var hours = ""
    var unitRate = ""
    var note = ""

    var hasContent: Bool {
        !workType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !hours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !unitRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
