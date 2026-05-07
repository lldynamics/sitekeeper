import SwiftUI

struct LaborRecordView: View {
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

    init(focusedLaborId: UUID? = nil) {
        self.focusedLaborId = focusedLaborId
    }

    private var filtered: [LaborRecord] {
        if searchText.isEmpty { return store.laborRecords }
        return store.laborRecords.filter {
            $0.date.localizedStandardContains(searchText) ||
            $0.note.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List {
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
            }
        }
        .searchable(text: $searchText, prompt: "按日期或备注搜索")
        .navigationTitle("人工/辅材记录")
        .toolbar {
            Button { showAdd = true } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    DatePicker("日期", selection: $newDate, displayedComponents: .date)
                    TextField("人数", text: $newWorkers).keyboardType(.numberPad)
                    TextField("工时", text: $newHours).keyboardType(.numberPad)
                    TextField("工价（每工时）", text: $newUnitRate).keyboardType(.decimalPad)
                    TextField("工种", text: $newWorkType)
                    TextField("班组", text: $newTeamName)
                    Toggle("已结算", isOn: $newIsSettled)
                    TextField("备注", text: $newNote)
                    Picker("归属项目", selection: $newProjectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
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
                }
            }
        }
        .sheet(item: $editingRecord) { record in
            LaborRecordEditSheet(record: record, projects: store.projects) { updated in
                if let index = store.laborRecords.firstIndex(where: { $0.id == updated.id }) {
                    store.laborRecords[index] = updated
                    store.scheduleSave()
                }
            } onDelete: { target in
                store.laborRecords.removeAll { $0.id == target.id }
                store.scheduleSave()
            }
        }
        .onAppear(perform: openFocusedLaborIfNeeded)
    }

    private func laborRow(_ r: LaborRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.date).font(.body.weight(.medium))
            HStack {
                Text("\(r.workers) 人 × \(r.hours) \(UnitDisplay.translatedUnit("h", useMetric: useMetric))")
                    .font(.caption).foregroundStyle(.secondary)
                if !r.workType.isEmpty {
                    Text("· \(r.workType)").font(.caption2).foregroundStyle(.secondary)
                }
                if !r.teamName.isEmpty {
                    Text("· \(r.teamName)").font(.caption2).foregroundStyle(.secondary)
                }
                if ReportBuilder.number(r.unitRate) > 0 {
                    Text("· 单价 \(ReportBuilder.money(ReportBuilder.number(r.unitRate)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("· 金额 \(ReportBuilder.money(ReportBuilder.laborLineTotal(r)))")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
                Text(r.isSettled ? "· 已结算" : "· 未结算")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(r.isSettled ? .green : .orange)
                if let pid = r.projectId, let proj = store.projects.first(where: { $0.id == pid }) {
                    Text("· \(proj.name)").font(.caption2).foregroundStyle(.blue)
                }
                if !r.note.isEmpty {
                    Text("· \(r.note)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        store.laborRecords.append(LaborRecord(
            date: df.string(from: newDate),
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
        DispatchQueue.main.async {
            editingRecord = record
        }
    }
}

struct LaborRecordEditSheet: View {
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
                    TextField("工时", text: $hours).keyboardType(.numberPad)
                    TextField("工价（每工时）", text: $unitRate).keyboardType(.decimalPad)
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
