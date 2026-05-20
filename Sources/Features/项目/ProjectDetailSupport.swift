import SwiftUI
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

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
                        Text(String(localized: "DWG / DXF 作为图纸原件管理，可交给外部专业看图软件打开；PDF 使用系统预览。"))
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
