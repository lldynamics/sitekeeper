import SwiftUI

struct TaskProgressView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let initialProjectId: UUID?
    @State private var showAdd = false
    @State private var newProjectId: UUID?
    @State private var newTitle = ""
    @State private var newStartDate = Date()
    @State private var newDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var newCompletion = 0.0
    @State private var newNote = ""
    @State private var mode: ProgressDisplayMode = .timeline
    @State private var projectFilter: UUID?
    @State private var statusFilter: ProgressStatusFilter = .all
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(initialProjectId: UUID? = nil) {
        self.initialProjectId = initialProjectId
        _newProjectId = State(initialValue: initialProjectId)
        _projectFilter = State(initialValue: initialProjectId)
    }

    private var visibleProjects: [Project] {
        if let projectFilter {
            return store.projects.filter { $0.id == projectFilter }
        }
        return store.projects
    }

    private var visibleTasks: [ProgressTask] {
        var result = store.progressTasks
        if let projectFilter {
            result = result.filter { $0.projectId == projectFilter }
        }
        switch statusFilter {
        case .all:
            return result
        case .thisWeek:
            let calendar = Calendar.current
            let now = Date()
            return result.filter {
                guard let start = Formatters.date.date(from: $0.startDate),
                      let due = Formatters.date.date(from: $0.dueDate) else { return false }
                return calendar.isDate(start, equalTo: now, toGranularity: .weekOfYear) ||
                    calendar.isDate(due, equalTo: now, toGranularity: .weekOfYear)
            }
        case .overdue:
            return result.filter(isOverdue)
        case .done:
            return result.filter { $0.clampedCompletion >= 1 }
        }
    }

    private var usesSplitLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                splitProgressLayout
            } else {
                compactProgressLayout
            }
        }
        .navigationTitle(String(localized: "施工进度"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            addTaskForm
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private var compactProgressLayout: some View {
        List {
            Section {
                ProjectContextStrip(
                    title: String(localized: "当前工程"),
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: String(localized: "全部项目")
                )
                Picker(String(localized: "视图"), selection: $mode) {
                    ForEach(ProgressDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(String(localized: "项目"), selection: $projectFilter) {
                    Text(String(localized: "全部项目")).tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
                FilterChipBar(
                    options: ProgressStatusFilter.allCases,
                    selection: $statusFilter,
                    title: { $0.displayName }
                )
            }

            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    String(localized: "暂无进度任务"),
                    systemImage: "calendar.badge.plus",
                    description: Text(String(localized: "添加任务后可按项目跟踪节点、完成率和延期情况"))
                )
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "新建进度任务"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
            } else if mode == .timeline {
                timelineContent
            } else {
                listContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "新建进度任务"))
            }
        }
    }

    private var splitProgressLayout: some View {
        NavigationSplitView {
            List {
                Section(String(localized: "筛选")) {
                    ProjectContextStrip(
                        title: String(localized: "当前工程"),
                        projects: store.projects,
                        selectedProjectId: $projectFilter,
                        emptyText: String(localized: "全部项目")
                    )
                    Picker(String(localized: "视图"), selection: $mode) {
                        ForEach(ProgressDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    FilterChipBar(
                        options: ProgressStatusFilter.allCases,
                        selection: $statusFilter,
                        title: { $0.displayName }
                    )
                }
                Section(String(localized: "快捷操作")) {
                    Button {
                        showAdd = true
                    } label: {
                        Label(String(localized: "新建进度任务"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            }
            .navigationTitle(String(localized: "进度筛选"))
        } detail: {
            List {
                if visibleTasks.isEmpty {
                    ContentUnavailableView(
                        String(localized: "暂无进度任务"),
                        systemImage: "calendar.badge.plus",
                        description: Text(String(localized: "添加任务后可按项目跟踪节点、完成率和延期情况"))
                    )
                } else if mode == .timeline {
                    timelineContent
                } else {
                    listContent
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var timelineContent: some View {
        Group {
            if let range = timelineRange(for: visibleTasks) {
                Section {
                    TimelineScale(start: range.start, end: range.end)
                }
                ForEach(visibleProjects) { project in
                    let tasks = tasks(for: project.id)
                    if !tasks.isEmpty {
                        Section(project.name) {
                            ForEach(tasks) { task in
                                timelineRow(task, range: range)
                            }
                            .onDelete { offsets in
                                delete(tasks: tasks, offsets: offsets)
                            }
                        }
                    }
                }
            }
        }
    }

    private var listContent: some View {
        Group {
            ForEach(visibleProjects) { project in
                let tasks = tasks(for: project.id)
                if !tasks.isEmpty {
                    Section(project.name) {
                        ForEach(tasks) { task in
                            taskRow(task)
                        }
                        .onDelete { offsets in
                            delete(tasks: tasks, offsets: offsets)
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: ProgressTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.title).font(.body.weight(.medium))
                Spacer()
                statusLabel(task)
            }
            SwiftUI.ProgressView(value: task.clampedCompletion)
                .tint(taskColor(task))
            HStack {
                Text("\(task.startDate) → \(task.dueDate)")
                Spacer()
                Text("\(Int(task.clampedCompletion * 100))%")
                    .foregroundStyle(taskColor(task))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !task.note.isEmpty {
                Text(task.note).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: completionBinding(for: task), in: 0...1, step: 0.05)
        }
        .padding(.vertical, 4)
    }

    private func timelineRow(_ task: ProgressTask, range: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.callout.weight(.medium))
                    Text("\(task.startDate) → \(task.dueDate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusLabel(task)
            }
            GeometryReader { proxy in
                let span = timelineSpan(task, range: range, width: proxy.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.appMutedSurface)
                        .frame(height: 12)
                    Capsule()
                        .fill(taskColor(task).opacity(0.28))
                        .frame(width: span.width, height: 12)
                        .offset(x: span.offset)
                    Capsule()
                        .fill(taskColor(task))
                        .frame(width: span.width * task.clampedCompletion, height: 12)
                        .offset(x: span.offset)
                }
            }
            .frame(height: 16)
            Slider(value: completionBinding(for: task), in: 0...1, step: 0.05)
        }
        .padding(.vertical, 6)
    }

    private func statusLabel(_ task: ProgressTask) -> some View {
        let text = task.clampedCompletion >= 1 ? String(localized: "完成") : isOverdue(task) ? String(localized: "延期") : "\(Int(task.clampedCompletion * 100))%"
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(taskColor(task))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(taskColor(task).opacity(0.14)))
    }

    private var addTaskForm: some View {
        NavigationStack {
            Form {
                Section(String(localized: "任务")) {
                    TextField(String(localized: "任务名称"), text: $newTitle)
                    Picker(String(localized: "所属项目"), selection: $newProjectId) {
                        Text(String(localized: "选择项目")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section(String(localized: "日期")) {
                    DatePicker(String(localized: "开始"), selection: $newStartDate, displayedComponents: .date)
                    DatePicker(String(localized: "截止"), selection: $newDueDate, displayedComponents: .date)
                }
                Section(String(localized: "完成率")) {
                    Slider(value: $newCompletion, in: 0...1, step: 0.05)
                    LabeledContent(String(localized: "当前"), value: "\(Int(newCompletion * 100))%")
                }
                Section(String(localized: "备注")) {
                    TextField(String(localized: "备注"), text: $newNote, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(String(localized: "添加进度任务"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        addTask()
                        showAdd = false
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newProjectId == nil)
                }
            }
        }
    }

    private func tasks(for projectId: UUID) -> [ProgressTask] {
        visibleTasks
            .filter { $0.projectId == projectId }
            .sorted { $0.startDate < $1.startDate }
    }

    private func completionBinding(for task: ProgressTask) -> Binding<Double> {
        Binding(
            get: {
                store.progressTasks.first(where: { $0.id == task.id })?.clampedCompletion ?? task.clampedCompletion
            },
            set: { value in
                if let index = store.progressTasks.firstIndex(where: { $0.id == task.id }) {
                    store.progressTasks[index].completion = value
                    store.scheduleSave()
                }
            }
        )
    }

    private func addTask() {
        guard let projectId = newProjectId else { return }
        store.appendProgressTask(ProgressTask(
            projectId: projectId,
            title: newTitle,
            startDate: Formatters.date.string(from: newStartDate),
            dueDate: Formatters.date.string(from: newDueDate),
            completion: newCompletion,
            note: newNote
        ))
        store.scheduleSave()
        operationNotice = .info(String(localized: "已新增进度任务"))
        newTitle = ""
        newProjectId = nil
        newCompletion = 0
        newNote = ""
        newStartDate = Date()
        newDueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private func delete(tasks: [ProgressTask], offsets: IndexSet) {
        let ids = Set(offsets.compactMap { tasks.indices.contains($0) ? tasks[$0].id : nil })
        guard !ids.isEmpty else { return }

        undoableDeletion.flushPendingCommit()
        let snapshot = store.progressTasks
        let targets = snapshot.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        store.removeProgressTasks(ids: ids)
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条任务"), Int64(targets.count)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.progressTasks = UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.progressTasks,
                    deletedIDs: ids
                )
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(format: String(localized: "删除施工进度任务 %lld 条"), Int64(targets.count)),
                detail: targets.map(progressAuditDetail(_:)).joined(separator: "、"),
                source: "TaskProgressView"
            )
        )
    }

    private func progressAuditDetail(_ task: ProgressTask) -> String {
        let projectName = store.projects.first(where: { $0.id == task.projectId })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [projectName, task.title, task.dueDate]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func isOverdue(_ task: ProgressTask) -> Bool {
        guard task.clampedCompletion < 1, let due = Formatters.date.date(from: task.dueDate) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    private func taskColor(_ task: ProgressTask) -> Color {
        if task.clampedCompletion >= 1 { return .appSuccess }
        if isOverdue(task) { return .appRisk }
        return .appWarning
    }

    private func timelineRange(for tasks: [ProgressTask]) -> DateInterval? {
        let dates = tasks.flatMap { task -> [Date] in
            [Formatters.date.date(from: task.startDate), Formatters.date.date(from: task.dueDate)].compactMap { $0 }
        }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: minDate) ?? minDate
        let end = calendar.date(byAdding: .day, value: 1, to: maxDate) ?? maxDate
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(24 * 60 * 60)))
    }

    private func timelineSpan(_ task: ProgressTask, range: DateInterval, width: CGFloat) -> (offset: CGFloat, width: CGFloat) {
        guard let start = Formatters.date.date(from: task.startDate),
              let due = Formatters.date.date(from: task.dueDate) else {
            return (0, max(width * 0.1, 18))
        }
        let total = max(range.duration, 1)
        let offset = max(0, start.timeIntervalSince(range.start) / total) * width
        let taskWidth = max(18, due.timeIntervalSince(start) / total * width)
        return (offset, min(taskWidth, max(width - offset, 18)))
    }
}

private enum ProgressDisplayMode: String, CaseIterable {
    case timeline
    case list

    var displayName: String {
        switch self {
        case .timeline: String(localized: "时间轴")
        case .list: String(localized: "列表")
        }
    }
}

private enum ProgressStatusFilter: String, CaseIterable {
    case all
    case thisWeek
    case overdue
    case done

    var displayName: String {
        switch self {
        case .all: String(localized: "全部")
        case .thisWeek: String(localized: "本周")
        case .overdue: String(localized: "逾期")
        case .done: String(localized: "已完成")
        }
    }
}

private struct TimelineScale: View {
    let start: Date
    let end: Date

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(Formatters.date.string(from: start))
                Spacer()
                Text(Formatters.date.string(from: end))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            GeometryReader { proxy in
                Path { path in
                    let width = proxy.size.width
                    path.move(to: CGPoint(x: 0, y: 6))
                    path.addLine(to: CGPoint(x: width, y: 6))
                    for index in 0...4 {
                        let x = width * CGFloat(index) / 4
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: 12))
                    }
                }
                .stroke(Color.appStrokeNeutral, lineWidth: 1)
            }
            .frame(height: 12)
        }
        .padding(.vertical, 4)
    }
}
