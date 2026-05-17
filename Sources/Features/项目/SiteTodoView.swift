import SwiftUI
import PhotosUI
import UIKit
import ImageIO

struct SiteTodoView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let initialProjectId: UUID?
    let autoOpenComposer: Bool
    let focusedTodoId: UUID?
    let initialBeforePhotoData: Data?
    let initialAfterPhotoData: Data?

    @State private var searchText = ""
    @State private var projectFilter: UUID?
    @State private var statusFilter: TodoFilter = .open
    @State private var showAdd = false
    @State private var editingTodo: SiteTodo?
    @State private var didAutoOpenComposer = false
    @State private var didOpenFocusedTodo = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(
        initialProjectId: UUID? = nil,
        autoOpenComposer: Bool = false,
        focusedTodoId: UUID? = nil,
        initialBeforePhotoData: Data? = nil,
        initialAfterPhotoData: Data? = nil
    ) {
        self.initialProjectId = initialProjectId
        self.autoOpenComposer = autoOpenComposer
        self.focusedTodoId = focusedTodoId
        self.initialBeforePhotoData = initialBeforePhotoData
        self.initialAfterPhotoData = initialAfterPhotoData
        _projectFilter = State(initialValue: initialProjectId)
    }

    private var filteredTodos: [SiteTodo] {
        let scopedTodos = store.siteTodos.filter { todo in
            if let projectFilter, todo.projectId != projectFilter { return false }
            if !statusFilter.matches(todo) { return false }
            return true
        }
        return SearchMatcher.filter(
            scopedTodos,
            keyword: searchText,
            extraFields: { todo in
                [todo.priority.displayName, todo.issueType.displayName, projectName(todo.projectId)] + methodTitles(for: todo.linkedConstructionMethodIDs)
            }
        )
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone && rhs.isDone }
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue && !rhs.isOverdue }
                return lhs.dueDate < rhs.dueDate
            }
    }

    private var usesSidebarLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSidebarLayout {
                NavigationSplitView {
                    filterSidebar
                } detail: {
                    todoListContent
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                compactTodoLayout
            }
        }
        .navigationTitle(String(localized: "现场待办"))
        .searchable(text: $searchText, prompt: String(localized: "搜索事项、负责人、备注"))
        .toolbar {
            if !usesSidebarLayout {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .buttonStyle(.appIcon())
                    .accessibilityLabel(String(localized: "新建待办"))
            }
        }
        .sheet(isPresented: $showAdd) {
            SiteTodoEditSheet(
                todo: nil,
                projects: store.projects,
                constructionMethods: store.constructionMethods,
                initialProjectId: projectFilter ?? initialProjectId,
                initialBeforePhotoData: initialBeforePhotoData,
                initialAfterPhotoData: initialAfterPhotoData
            ) { todo in
                store.insertSiteTodoAtTop(todo)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingTodo) { todo in
            SiteTodoEditSheet(
                todo: todo,
                projects: store.projects,
                constructionMethods: store.constructionMethods,
                initialProjectId: todo.projectId
            ) { updated in
                save(updated)
            } onDelete: { target in
                deleteTodo(target)
            }
        }
        .onAppear {
            autoOpenComposerIfNeeded()
            openFocusedTodoIfNeeded()
        }
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .operationToast(notice: $operationNotice)
    }

    private var compactTodoLayout: some View {
        List {
            filterSection
            todoListSection
        }
    }

    private var filterSidebar: some View {
        List {
            filterSection
            Section(String(localized: "快捷操作")) {
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "新建待办"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
            }
        }
        .navigationTitle(String(localized: "筛选"))
    }

    private var todoListContent: some View {
        List {
            todoListSection
        }
    }

    private var filterSection: some View {
        Section(String(localized: "筛选")) {
            Picker(String(localized: "项目"), selection: $projectFilter) {
                Text(String(localized: "全部项目")).tag(nil as UUID?)
                ForEach(store.projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            Picker(String(localized: "状态"), selection: $statusFilter) {
                ForEach(TodoFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var todoListSection: some View {
        Section(String(format: String(localized: "现场待办 (%lld)"), Int64(filteredTodos.count))) {
            if filteredTodos.isEmpty {
                ContentUnavailableView(
                    String(localized: "暂无现场待办"),
                    systemImage: "checklist",
                    description: Text(String(localized: "添加事项后可按项目、负责人、优先级和问题类型跟踪。"))
                )
            } else {
                ForEach(filteredTodos) { todo in
                    Button { editingTodo = todo } label: {
                        SiteTodoRow(
                            todo: todo,
                            projectName: projectName(todo.projectId),
                            methodTitles: methodTitles(for: todo.linkedConstructionMethodIDs)
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleDone(todo)
                        } label: {
                            Label(
                                todo.isDone ? String(localized: "重开") : String(localized: "完成"),
                                systemImage: todo.isDone ? "arrow.uturn.backward" : "checkmark.circle.fill"
                            )
                        }
                        .tint(todo.isDone ? Color.appWarning : Color.appSuccess)
                    }
                }
                .onDelete(perform: deleteTodos)
            }
        }
    }

    private func autoOpenComposerIfNeeded() {
        guard autoOpenComposer, !didAutoOpenComposer else { return }
        didAutoOpenComposer = true
        Task { @MainActor in showAdd = true }
    }

    private func openFocusedTodoIfNeeded() {
        guard let focusedTodoId, !didOpenFocusedTodo,
              let todo = store.siteTodos.first(where: { $0.id == focusedTodoId }) else { return }
        didOpenFocusedTodo = true
        projectFilter = todo.projectId
        Task { @MainActor in editingTodo = todo }
    }

    private func save(_ updated: SiteTodo) {
        if store.updateSiteTodo(updated) {
            store.scheduleSave()
        }
    }

    private func toggleDone(_ todo: SiteTodo) {
        var value = todo
        value.isDone.toggle()
        value.completedAt = value.isDone ? Formatters.now() : nil
        save(value)
    }

    private func deleteTodos(_ offsets: IndexSet) {
        let ids = Set(offsets.compactMap { filteredTodos.indices.contains($0) ? filteredTodos[$0].id : nil })
        deleteTodoIds(ids)
    }

    private func deleteTodo(_ todo: SiteTodo) {
        deleteTodoIds(Set([todo.id]))
        editingTodo = nil
    }

    private func deleteTodoIds(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let targets = store.siteTodos.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let photoFileNames = targets.flatMap(todoPhotoFileNames(_:))
        let deletion = store.removeSiteTodos(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除现场待办 %lld 条"), Int64(targets.count)),
                detail: String(format: String(localized: "关联照片文件 %lld 个"), Int64(photoFileNames.count)),
                source: "SiteTodoView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.photoFiles(
                photoFileNames,
                summary: "siteTodo.photoFiles"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条现场待办"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreSiteTodos(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func todoPhotoFileNames(_ todo: SiteTodo) -> [String] {
        [todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName].compactMap { $0 }
    }

    private func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return store.projects.first(where: { $0.id == id })?.name ?? ""
    }

    private func methodTitles(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.constructionMethods.map { method in
            let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (method.id, title.isEmpty ? String(localized: "未命名工艺") : title)
        })
        return ids.compactMap { lookup[$0] }
    }
}

private struct SiteTodoRow: View {
    let todo: SiteTodo
    let projectName: String
    let methodTitles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : todo.isOverdue ? "exclamationmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.appSuccess : todo.isOverdue ? .appRisk : Color.appWarning)
                Text(todo.title.isEmpty ? String(localized: "未命名事项") : todo.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                Spacer()
                priorityBadge(todo.priority)
            }
            HStack(spacing: 8) {
                Text(todo.dueDate)
                Text(todo.issueType.displayName)
                if !todo.owner.isEmpty { Text(todo.owner) }
                if !projectName.isEmpty { Text(projectName).foregroundStyle(Color.appDoc) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !todo.note.isEmpty {
                Text(todo.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !methodTitles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(Color.appWarning)
                    Text(methodTitles.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if todo.rectificationBeforePhotoFileName != nil || todo.rectificationAfterPhotoFileName != nil {
                HStack(spacing: 8) {
                    thumbnail(title: String(localized: "前"), fileName: todo.rectificationBeforePhotoFileName)
                    thumbnail(title: String(localized: "后"), fileName: todo.rectificationAfterPhotoFileName)
                }
            }
            if let completedAt = todo.completedAt, todo.isDone {
                Text(String(format: String(localized: "完成时间: %@"), completedAt))
                    .font(.caption2)
                    .foregroundStyle(Color.appSuccess)
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityBadge(_ priority: TodoPriority) -> some View {
        let color: Color
        switch priority {
        case .high:
            color = .appRisk
        case .medium:
            color = .appWarning
        case .low:
            color = .appMuted
        }
        return Text(priority.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    @ViewBuilder
    private func thumbnail(title: String, fileName: String?) -> some View {
        if fileName != nil {
            ZStack(alignment: .topLeading) {
                AsyncPhotoThumbnailImageView(fileName: fileName) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 48)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(width: 64, height: 48)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
                Text(title)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
    }
}

private struct SiteTodoEditSheet: View {
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
            StorageIssueLog.record(String(format: String(localized: "待办整改照片导入失败：%@"), error.localizedDescription))
            return
        }
        guard !Task.isCancelled else { return }
        let normalizedData = normalizePhotoData(data, maxPixelSize: 1600, compressionQuality: 0.8) ?? data
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

    private func normalizePhotoData(_ data: Data, maxPixelSize: CGFloat, compressionQuality: CGFloat) -> Data? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality)
    }
}

private enum TodoFilter: CaseIterable {
    case open
    case overdue
    case done
    case all

    var displayName: String {
        switch self {
        case .open:
            return String(localized: "未完成")
        case .overdue:
            return String(localized: "延期")
        case .done:
            return String(localized: "已完成")
        case .all:
            return String(localized: "全部")
        }
    }

    func matches(_ todo: SiteTodo) -> Bool {
        switch self {
        case .open: return !todo.isDone
        case .overdue: return todo.isOverdue
        case .done: return todo.isDone
        case .all: return true
        }
    }
}
