import SwiftUI
import UIKit

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
        AdaptiveListDetailLayout(
            forceSplit: usesSidebarLayout,
            compact: {
                compactTodoLayout
            },
            sidebar: {
                filterSidebar
            },
            detail: {
                todoListContent
            }
        )
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
            if !drawingIssueTags.isEmpty {
                FlowTagLine(tags: drawingIssueTags)
            }
            if !todo.drawingIssueCloseEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(format: String(localized: "关闭证据: %@"), todo.drawingIssueCloseEvidence))
                    .font(.caption2)
                    .foregroundStyle(Color.appSuccess)
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

    private var drawingIssueTags: [String] {
        [
            todo.drawingIssueLocation.isEmpty ? "" : String(format: String(localized: "位置: %@"), todo.drawingIssueLocation),
            todo.drawingIssueLayerOrPage.isEmpty ? "" : String(format: String(localized: "图层/页码: %@"), todo.drawingIssueLayerOrPage),
            todo.drawingIssueMeasurement.isEmpty ? "" : String(format: String(localized: "测量: %@"), todo.drawingIssueMeasurement)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
