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
        let dayContext = store.projectStore.dayContext
        let scopedTodos = store.siteTodos.filter { todo in
            if let projectFilter, todo.projectId != projectFilter { return false }
            if !statusFilter.matches(todo, dayContext: dayContext) { return false }
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
                let lhsOverdue = !lhs.isDone && dayContext.isOverdue(date: lhs.dueDate)
                let rhsOverdue = !rhs.isDone && dayContext.isOverdue(date: rhs.dueDate)
                if lhsOverdue != rhsOverdue { return lhsOverdue && !rhsOverdue }
                return lhs.dueDate < rhs.dueDate
            }
    }

    private var usesSidebarLayout: Bool {
        horizontalSizeClass == .regular
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
        .navigationTitle(AppLocalization.string("现场待办"))
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索事项、负责人、备注"))
        .toolbar {
            if !usesSidebarLayout {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .buttonStyle(.appIcon())
                    .accessibilityLabel(AppLocalization.string("新建待办"))
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
            ) { _ in
                showAdd = false
            }
        }
        .sheet(item: $editingTodo) { todo in
            SiteTodoEditSheet(
                todo: todo,
                projects: store.projects,
                constructionMethods: store.constructionMethods,
                initialProjectId: todo.projectId
            ) { _ in
                editingTodo = nil
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
            Section(AppLocalization.string("快捷操作")) {
                Button {
                    showAdd = true
                } label: {
                    Label(AppLocalization.string("新建待办"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
            }
        }
        .navigationTitle(AppLocalization.string("筛选"))
    }

    private var todoListContent: some View {
        List {
            todoListSection
        }
    }

    private var filterSection: some View {
        Section(AppLocalization.string("筛选")) {
            Picker(AppLocalization.string("项目"), selection: $projectFilter) {
                Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
                ForEach(store.projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            Picker(AppLocalization.string("状态"), selection: $statusFilter) {
                ForEach(TodoFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var todoListSection: some View {
        Section(String(format: AppLocalization.string("现场待办 (%lld)"), Int64(filteredTodos.count))) {
            if filteredTodos.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("暂无现场待办"),
                    systemImage: "checklist",
                    description: Text(AppLocalization.string("添加事项后可按项目、负责人、优先级和问题类型跟踪。"))
                )
            } else {
                ForEach(filteredTodos) { todo in
                    Button { editingTodo = todo } label: {
                        SiteTodoRow(
                            todo: todo,
                            isOverdue: !todo.isDone && store.projectStore.dayContext.isOverdue(date: todo.dueDate),
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
                                todo.isDone ? AppLocalization.string("重开") : AppLocalization.string("完成"),
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
}

private extension SiteTodoView {
    func autoOpenComposerIfNeeded() {
        guard autoOpenComposer, !didAutoOpenComposer else { return }
        didAutoOpenComposer = true
        Task { @MainActor in showAdd = true }
    }

    func openFocusedTodoIfNeeded() {
        guard let focusedTodoId, !didOpenFocusedTodo,
              let todo = store.siteTodos.first(where: { $0.id == focusedTodoId }) else { return }
        didOpenFocusedTodo = true
        projectFilter = todo.projectId
        Task { @MainActor in editingTodo = todo }
    }

    func save(_ updated: SiteTodo) {
        if store.updateSiteTodo(updated) {
            store.scheduleSave()
        }
    }

    func toggleDone(_ todo: SiteTodo) {
        var value = todo
        value.isDone.toggle()
        value.completedAt = value.isDone ? .now() : nil
        save(value)
    }

    func deleteTodos(_ offsets: IndexSet) {
        let ids = Set(offsets.compactMap { filteredTodos.indices.contains($0) ? filteredTodos[$0].id : nil })
        deleteTodoIds(ids)
    }

    func deleteTodo(_ todo: SiteTodo) {
        deleteTodoIds(Set([todo.id]))
        editingTodo = nil
    }

    func deleteTodoIds(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let targets = store.siteTodos.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let photoFileNames = targets.flatMap(todoPhotoFileNames(_:))
        let deletion = store.removeSiteTodos(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("删除现场待办 %lld 条"), Int64(targets.count)),
                detail: String(format: AppLocalization.string("关联照片文件 %lld 个"), Int64(photoFileNames.count)),
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
            message: String(format: AppLocalization.string("已删除 %lld 条现场待办"), Int64(deletion.deletedCount)),
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

    func todoPhotoFileNames(_ todo: SiteTodo) -> [String] {
        [todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName].compactMap { $0 }
    }

    func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return store.projects.first(where: { $0.id == id })?.name ?? ""
    }

    func methodTitles(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.constructionMethods.map { method in
            let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return (method.id, title.isEmpty ? AppLocalization.string("未命名工艺") : title)
        })
        return ids.compactMap { lookup[$0] }
    }
}
