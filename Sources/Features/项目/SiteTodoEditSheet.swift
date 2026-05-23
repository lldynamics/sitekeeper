import SwiftUI
import PhotosUI
import UIKit

struct SiteTodoEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let todo: SiteTodo?
    let projects: [Project]
    let constructionMethods: [ConstructionMethod]
    let initialProjectId: UUID?
    let initialBeforePhotoData: Data?
    let initialAfterPhotoData: Data?
    let onSave: (SiteTodo) -> Void
    var onDelete: ((SiteTodo) -> Void)? = nil

    @State private var id: UUID
    @State private var title: String
    @State private var owner: String
    @State private var dueDate: Date
    @State private var priority: TodoPriority
    @State private var issueType: TodoIssueType
    @State private var drawingIssueLocation: String
    @State private var drawingIssueLayerOrPage: String
    @State private var drawingIssueMeasurement: String
    @State private var drawingIssueCloseEvidence: String
    @State private var beforePhotoFileName: String?
    @State private var afterPhotoFileName: String?
    @State private var isDone: Bool
    @State private var completedAt: String?
    @State private var note: String
    @State private var linkedMethodIDs: Set<UUID>
    @State private var projectId: UUID?
    @State private var beforePhotoItem: PhotosPickerItem?
    @State private var afterPhotoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var didCommit = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var didImportInitialPhotos = false
    @State private var beforePhotoImportTask: Task<Void, Never>?
    @State private var afterPhotoImportTask: Task<Void, Never>?
    @State private var initialPhotoImportTask: Task<Void, Never>?
    @State private var createdDraftPhotoFileNames: Set<String> = []

    init(
        todo: SiteTodo?,
        projects: [Project],
        constructionMethods: [ConstructionMethod],
        initialProjectId: UUID?,
        initialBeforePhotoData: Data? = nil,
        initialAfterPhotoData: Data? = nil,
        onSave: @escaping (SiteTodo) -> Void,
        onDelete: ((SiteTodo) -> Void)? = nil
    ) {
        self.todo = todo
        self.projects = projects
        self.constructionMethods = constructionMethods
        self.initialProjectId = initialProjectId
        self.initialBeforePhotoData = initialBeforePhotoData
        self.initialAfterPhotoData = initialAfterPhotoData
        self.onSave = onSave
        self.onDelete = onDelete
        let draftId = todo?.id ?? UUID()
        _id = State(initialValue: draftId)
        _title = State(initialValue: todo?.title ?? "")
        _owner = State(initialValue: todo?.owner ?? "")
        _dueDate = State(initialValue: todo.flatMap { Formatters.date.date(from: $0.dueDate) } ?? Date())
        _priority = State(initialValue: todo?.priority ?? .medium)
        _issueType = State(initialValue: todo?.issueType ?? .general)
        _drawingIssueLocation = State(initialValue: todo?.drawingIssueLocation ?? "")
        _drawingIssueLayerOrPage = State(initialValue: todo?.drawingIssueLayerOrPage ?? "")
        _drawingIssueMeasurement = State(initialValue: todo?.drawingIssueMeasurement ?? "")
        _drawingIssueCloseEvidence = State(initialValue: todo?.drawingIssueCloseEvidence ?? "")
        _beforePhotoFileName = State(initialValue: todo?.rectificationBeforePhotoFileName)
        _afterPhotoFileName = State(initialValue: todo?.rectificationAfterPhotoFileName)
        _isDone = State(initialValue: todo?.isDone ?? false)
        _completedAt = State(initialValue: todo?.completedAt)
        _note = State(initialValue: todo?.note ?? "")
        _linkedMethodIDs = State(initialValue: Set(todo?.linkedConstructionMethodIDs ?? []))
        _projectId = State(initialValue: todo?.projectId ?? initialProjectId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "事项")) {
                    TextField(String(localized: "待办事项"), text: $title, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(String(localized: "负责人"), text: $owner)
                    DatePicker(String(localized: "日期"), selection: $dueDate, displayedComponents: .date)
                    Picker(String(localized: "优先级"), selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Picker(String(localized: "问题类型"), selection: $issueType) {
                        ForEach(TodoIssueType.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if showsDrawingIssueClosureFields {
                    Section(String(localized: "图纸问题闭环")) {
                        TextField(String(localized: "问题位置"), text: $drawingIssueLocation, axis: .vertical)
                            .lineLimit(1...3)
                        TextField(String(localized: "图层/页码"), text: $drawingIssueLayerOrPage)
                        TextField(String(localized: "测量结果"), text: $drawingIssueMeasurement, axis: .vertical)
                            .lineLimit(1...4)
                        TextField(String(localized: "关闭证据（验收人/复测/照片说明）"), text: $drawingIssueCloseEvidence, axis: .vertical)
                            .lineLimit(1...4)
                        Text(String(localized: "整改后照片和关闭证据会进入交付包的图纸问题清单。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "关联施工工艺")) {
                    if constructionMethods.isEmpty {
                        Text(String(localized: "暂无工艺条目，可先在工具箱-施工工艺库新增"))
                            .font(.caption)
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
                                        Text(method.versionName.isEmpty ? String(localized: "V1") : method.versionName)
                                        Text(method.publishStatus.displayName)
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "项目"), selection: $projectId) {
                        Text(String(localized: "不关联项目")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section(String(localized: "整改照片")) {
                    photoPickerRow(title: String(localized: "整改前"), fileName: beforePhotoFileName, selection: $beforePhotoItem, clear: clearBeforePhoto)
                    photoPickerRow(title: String(localized: "整改后"), fileName: afterPhotoFileName, selection: $afterPhotoItem, clear: clearAfterPhoto)
                }
                Section(String(localized: "状态")) {
                    Toggle(String(localized: "已完成"), isOn: $isDone)
                    if let completedAt, isDone {
                        LabeledContent(String(localized: "完成时间"), value: completedAt)
                    }
                }
                if todo != nil {
                    Section {
                        Button(String(localized: "删除待办"), role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(todo == nil ? String(localized: "新增待办") : String(localized: "编辑待办"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        let value = updatedTodo
                        didCommit = true
                        onSave(value)
                        cleanupPhotoFilesAfterSave(savedTodo: value)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(String(localized: "删除这条待办？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    didCommit = true
                    cleanupCreatedDraftPhotoFiles()
                    if let todo { onDelete?(todo) }
                    dismiss()
                }
            }
            .alert(String(localized: "现场待办"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onChange(of: beforePhotoItem) { _, item in
                beforePhotoImportTask?.cancel()
                beforePhotoImportTask = Task { await importTodoPhoto(item, kind: .before) }
            }
            .onChange(of: afterPhotoItem) { _, item in
                afterPhotoImportTask?.cancel()
                afterPhotoImportTask = Task { await importTodoPhoto(item, kind: .after) }
            }
            .onDisappear {
                beforePhotoImportTask?.cancel()
                afterPhotoImportTask?.cancel()
                initialPhotoImportTask?.cancel()
                beforePhotoImportTask = nil
                afterPhotoImportTask = nil
                initialPhotoImportTask = nil
                cleanupNewDraftFilesIfNeeded()
            }
            .onAppear(perform: importInitialPhotosIfNeeded)
        }
    }

    private var showsDrawingIssueClosureFields: Bool {
        let haystack = "\(title)\n\(note)"
        return !drawingIssueLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !drawingIssueLayerOrPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !drawingIssueMeasurement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || haystack.localizedCaseInsensitiveContains(String(localized: "图纸问题"))
            || haystack.localizedCaseInsensitiveContains("Drawing Issue")
    }

    private func photoPickerRow(title: String, fileName: String?, selection: Binding<PhotosPickerItem?>, clear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhotosPicker(selection: selection, matching: .images) {
                    Label(
                        fileName == nil
                            ? String(format: String(localized: "添加%@照片"), title)
                            : String(format: String(localized: "替换%@照片"), title),
                        systemImage: "photo.on.rectangle"
                    )
                }
                Spacer()
                if fileName != nil {
                    Button(String(localized: "移除"), role: .destructive, action: clear)
                        .font(.caption)
                }
            }
            if fileName != nil {
                AsyncPhotoThumbnailImageView(fileName: fileName) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 150)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
            }
        }
    }

    private enum TodoPhotoKind { case before, after }

    private func importTodoPhoto(_ item: PhotosPickerItem?, kind: TodoPhotoKind) async {
        guard let item else { return }
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else { return }
            data = loaded
        } catch {
            StorageIssueLog.recordEvent(
                "site_todo.rectification_photo_import_failed",
                category: .fileStorage,
                details: [
                    "source": "SiteTodoView.importTodoPhoto"
                ],
                error: error
            )
            return
        }
        guard !Task.isCancelled else { return }
        let normalizedData = ImageDownsampleService.downsampledJPEGData(
            data,
            maxPixelSize: 1600,
            compressionQuality: 0.8
        ) ?? data
        guard !Task.isCancelled else { return }
        await saveTodoPhotoData(normalizedData, kind: kind)
    }

    @MainActor
    private func saveTodoPhotoData(_ data: Data, kind: TodoPhotoKind) async {
        let suffix = kind == .before ? "before" : "after"
        let fileName = "todo-\(id.uuidString)-\(suffix)-\(UUID().uuidString).jpg"
        let saved: String
        do {
            saved = try PhotoStorage.saveOrThrow(original: data, fileName: fileName)
        } catch {
            alertMessage = String(format: String(localized: "整改照片保存失败：%@"), error.localizedDescription)
            showAlert = true
            return
        }
        createdDraftPhotoFileNames.insert(saved)
        switch kind {
        case .before:
            deleteDraftPhotoIfNeeded(beforePhotoFileName)
            beforePhotoFileName = saved
            beforePhotoItem = nil
        case .after:
            deleteDraftPhotoIfNeeded(afterPhotoFileName)
            afterPhotoFileName = saved
            afterPhotoItem = nil
        }
    }

    private func importInitialPhotosIfNeeded() {
        guard todo == nil, !didImportInitialPhotos else { return }
        didImportInitialPhotos = true
        initialPhotoImportTask?.cancel()
        initialPhotoImportTask = Task {
            if let initialBeforePhotoData {
                guard !Task.isCancelled else { return }
                await saveTodoPhotoData(initialBeforePhotoData, kind: .before)
            }
            if let initialAfterPhotoData {
                guard !Task.isCancelled else { return }
                await saveTodoPhotoData(initialAfterPhotoData, kind: .after)
            }
            await MainActor.run {
                initialPhotoImportTask = nil
            }
        }
    }

    private func clearBeforePhoto() {
        deleteDraftPhotoIfNeeded(beforePhotoFileName)
        beforePhotoFileName = nil
    }

    private func clearAfterPhoto() {
        deleteDraftPhotoIfNeeded(afterPhotoFileName)
        afterPhotoFileName = nil
    }

    private func cleanupNewDraftFilesIfNeeded() {
        guard !didCommit else { return }
        cleanupCreatedDraftPhotoFiles()
    }

    private func deleteDraftPhotoIfNeeded(_ fileName: String?) {
        guard let fileName, createdDraftPhotoFileNames.remove(fileName) != nil else { return }
        DataStoreDeferredFileCleanup.photoFiles(
            [fileName],
            summary: "siteTodo.draftPhoto"
        )?.perform()
    }

    private func cleanupCreatedDraftPhotoFiles() {
        let fileNames = createdDraftPhotoFileNames
        createdDraftPhotoFileNames.removeAll()
        DataStoreDeferredFileCleanup.photoFiles(
            Array(fileNames),
            summary: "siteTodo.createdDraftPhotos"
        )?.perform()
    }

    private func cleanupPhotoFilesAfterSave(savedTodo: SiteTodo) {
        let savedFileNames = Set([
            savedTodo.rectificationBeforePhotoFileName,
            savedTodo.rectificationAfterPhotoFileName
        ].compactMap { $0 })
        let originalFileNames = Set([
            todo?.rectificationBeforePhotoFileName,
            todo?.rectificationAfterPhotoFileName
        ].compactMap { $0 })

        let removedOriginalFileNames = originalFileNames.subtracting(savedFileNames)
        let unusedDraftFileNames = createdDraftPhotoFileNames.subtracting(savedFileNames)
        DataStoreDeferredFileCleanup.photoFiles(
            Array(removedOriginalFileNames.union(unusedDraftFileNames)),
            summary: "siteTodo.saveCleanup"
        )?.perform()
        createdDraftPhotoFileNames.removeAll()
    }

    private var updatedTodo: SiteTodo {
        var value = todo ?? SiteTodo(id: id, title: "")
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        value.dueDate = Formatters.date.string(from: dueDate)
        value.priority = priority
        value.issueType = issueType
        value.drawingIssueLocation = drawingIssueLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueLayerOrPage = drawingIssueLayerOrPage.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueMeasurement = drawingIssueMeasurement.trimmingCharacters(in: .whitespacesAndNewlines)
        value.drawingIssueCloseEvidence = drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        value.rectificationBeforePhotoFileName = beforePhotoFileName
        value.rectificationAfterPhotoFileName = afterPhotoFileName
        value.isDone = isDone
        value.completedAt = isDone ? (completedAt ?? Formatters.now()) : nil
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.linkedConstructionMethodIDs = constructionMethods
            .map(\.id)
            .filter { linkedMethodIDs.contains($0) }
        value.projectId = projectId
        return value
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isLinked in
                if isLinked {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "未命名工艺") : title
    }
}
