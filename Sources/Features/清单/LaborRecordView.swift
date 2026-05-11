import SwiftUI

struct LaborRecordView: View {
    private enum LaborFormField: Hashable {
        case workers
        case hours
        case unitRate
    }

    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    let focusedLaborId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingRecord: LaborRecord?
    @State private var didOpenFocusedLabor = false
    @State private var newDate = Date()
    @State private var newWorkers = ""
    @State private var newHours = ""
    @State private var newUnitRate = ""
    @State private var newWorkType = ""
    @State private var newTeamName = ""
    @State private var newIsSettled = false
    @State private var newNote = ""
    @State private var newProjectId: UUID?
    @State private var projectFilter: UUID?
    @State private var operationMessage: String?
    @FocusState private var laborFormFocusedField: LaborFormField?

    init(focusedLaborId: UUID? = nil) {
        self.focusedLaborId = focusedLaborId
    }

    private var filtered: [LaborRecord] {
        let scopedRecords = store.laborRecords.filter { record in
            projectFilter == nil || record.projectId == projectFilter
        }
        return SearchMatcher.filter(scopedRecords, keyword: searchText)
    }

    var body: some View {
        List {
            Section {
                ProjectContextStrip(
                    title: "当前工程",
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: "全部项目"
                )
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView("暂无人工记录", systemImage: "person.2", description: Text("添加人工后可按工程统计工时与成本。"))
                    Button {
                        showAdd = true
                    } label: {
                        Label("添加人工记录", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appPrimaryAction)
                }
            } else {
                ForEach(filtered) { r in
                    Button {
                        editingRecord = r
                    } label: {
                        laborRow(r)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in
                    let ids = idx.map { filtered[$0].id }
                    store.laborRecords.removeAll { ids.contains($0.id) }
                    store.scheduleSave()
                    operationMessage = "已删除 \(ids.count) 条人工记录"
                }
            }
        }
        .searchable(text: $searchText, prompt: "按日期或备注搜索")
        .navigationTitle("人工/辅材记录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("必填信息") {
                        DatePicker("日期", selection: $newDate, displayedComponents: .date)
                        TextField("人数", text: $newWorkers).keyboardType(.numberPad)
                            .focused($laborFormFocusedField, equals: .workers)
                        TextField("工时", text: $newHours).keyboardType(.numberPad)
                            .focused($laborFormFocusedField, equals: .hours)
                        TextField("工价（每工时）", text: $newUnitRate).keyboardType(.decimalPad)
                            .focused($laborFormFocusedField, equals: .unitRate)
                    }
                    Section("作业信息") {
                        TextField("工种", text: $newWorkType)
                        TextField("班组", text: $newTeamName)
                        Toggle("已结算", isOn: $newIsSettled)
                    }
                    Section("归属项目") {
                        Picker("归属项目", selection: $newProjectId) {
                            Text("无归属").tag(nil as UUID?)
                            ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                        }
                    }
                    Section("备注") {
                        TextField("备注", text: $newNote, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .navigationTitle("添加记录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showAdd = false }
                    }
                ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save(); showAdd = false }
                            .disabled(!canSave)
                    }
                    KeyboardNavigationToolbar(
                        focusedField: $laborFormFocusedField,
                        fields: [.workers, .hours, .unitRate]
                    )
                }
            }
        }
        .sheet(item: $editingRecord) { record in
            LaborRecordEditSheet(record: record, projects: store.projects) { updated in
                if let index = store.laborRecords.firstIndex(where: { $0.id == updated.id }) {
                    store.laborRecords[index] = updated
                    store.scheduleSave()
                    operationMessage = "已更新人工记录"
                }
            } onDelete: { target in
                store.laborRecords.removeAll { $0.id == target.id }
                store.scheduleSave()
                operationMessage = "已删除人工记录"
            }
        }
        .onAppear(perform: openFocusedLaborIfNeeded)
        .operationToast(message: $operationMessage)
    }

    private func laborRow(_ r: LaborRecord) -> some View {
        let projectText = r.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? "未归属"
        let meta = "\(r.date) · \(r.workers)人 × \(r.hours)\(UnitDisplay.translatedUnit("h", useMetric: useMetric)) · \(projectText)"
        let note = [r.workType, r.teamName, r.note].filter { !$0.isEmpty }.joined(separator: " · ")
        return BusinessRecordRow(
            icon: "person.2.fill",
            iconColor: r.isSettled ? Color.appSuccess : Color.appPrimaryAction,
            title: r.workType.isEmpty ? "人工记录" : r.workType,
            meta: meta,
            note: note,
            trailing: ReportBuilder.money(ReportBuilder.laborLineTotal(r)),
            trailingColor: Color.appPrimaryAction
        )
    }

    private func save() {
        guard canSave else { return }
        store.laborRecords.append(LaborRecord(
            date: Formatters.date.string(from: newDate),
            workers: newWorkers,
            hours: newHours,
            unitRate: newUnitRate,
            workType: newWorkType,
            teamName: newTeamName,
            isSettled: newIsSettled,
            note: newNote,
            projectId: newProjectId
        ))
        store.scheduleSave()
        operationMessage = "已新增人工记录"
        newWorkers = ""
        newHours = ""
        newUnitRate = ""
        newWorkType = ""
        newTeamName = ""
        newIsSettled = false
        newNote = ""
        newProjectId = nil
    }

    private var canSave: Bool {
        InputValidator.nonNegativeNumber(newWorkers) &&
        InputValidator.nonNegativeNumber(newHours) &&
        (newUnitRate.isEmpty || InputValidator.nonNegativeNumber(newUnitRate))
    }

    private func openFocusedLaborIfNeeded() {
        guard let focusedLaborId, !didOpenFocusedLabor,
              let record = store.laborRecords.first(where: { $0.id == focusedLaborId }) else { return }
        didOpenFocusedLabor = true
        searchText = ""
        projectFilter = record.projectId
        Task { @MainActor in
            editingRecord = record
        }
    }
}

struct LaborRecordEditSheet: View {
    private enum EditLaborFormField: Hashable {
        case workers
        case hours
        case unitRate
    }

    @Environment(\.dismiss) private var dismiss
    let record: LaborRecord
    let projects: [Project]
    let onSave: (LaborRecord) -> Void
    let onDelete: (LaborRecord) -> Void

    @State private var date: Date
    @State private var workers: String
    @State private var hours: String
    @State private var unitRate: String
    @State private var workType: String
    @State private var teamName: String
    @State private var isSettled: Bool
    @State private var note: String
    @State private var projectId: UUID?
    @State private var showDeleteConfirm = false
    @FocusState private var editLaborFormFocusedField: EditLaborFormField?

    init(record: LaborRecord, projects: [Project], onSave: @escaping (LaborRecord) -> Void, onDelete: @escaping (LaborRecord) -> Void) {
        self.record = record
        self.projects = projects
        self.onSave = onSave
        self.onDelete = onDelete
        _date = State(initialValue: Formatters.date.date(from: record.date) ?? Date())
        _workers = State(initialValue: record.workers)
        _hours = State(initialValue: record.hours)
        _unitRate = State(initialValue: record.unitRate)
        _workType = State(initialValue: record.workType)
        _teamName = State(initialValue: record.teamName)
        _isSettled = State(initialValue: record.isSettled)
        _note = State(initialValue: record.note)
        _projectId = State(initialValue: record.projectId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("人工") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("人数", text: $workers).keyboardType(.numberPad)
                        .focused($editLaborFormFocusedField, equals: .workers)
                    TextField("工时", text: $hours).keyboardType(.numberPad)
                        .focused($editLaborFormFocusedField, equals: .hours)
                    TextField("工价（每工时）", text: $unitRate).keyboardType(.decimalPad)
                        .focused($editLaborFormFocusedField, equals: .unitRate)
                    TextField("工种", text: $workType)
                    TextField("班组", text: $teamName)
                    Toggle("已结算", isOn: $isSettled)
                }
                Section("归属项目") {
                    Picker("归属项目", selection: $projectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section("备注") {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("删除人工记录", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("编辑人工记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedRecord)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                KeyboardNavigationToolbar(
                    focusedField: $editLaborFormFocusedField,
                    fields: [.workers, .hours, .unitRate]
                )
            }
            .alert("删除这条人工记录？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    onDelete(record)
                    dismiss()
                }
            }
        }
    }

    private var updatedRecord: LaborRecord {
        var value = record
        value.date = Formatters.date.string(from: date)
        value.workers = workers
        value.hours = hours
        value.unitRate = unitRate
        value.workType = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        value.teamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.isSettled = isSettled
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.projectId = projectId
        return value
    }

    private var canSave: Bool {
        InputValidator.nonNegativeNumber(workers) &&
        InputValidator.nonNegativeNumber(hours) &&
        (unitRate.isEmpty || InputValidator.nonNegativeNumber(unitRate))
    }
}
