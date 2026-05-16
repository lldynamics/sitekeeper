import SwiftUI

struct LaborRecordView: View {
    private enum LaborFormField: Hashable {
        case workers
        case hours
        case unitRate
    }

    @Environment(DataStore.self) private var store
    @AppStorage("labor.savedTeams") private var savedTeamsRaw = ""
    @AppStorage("labor.savedWorkTypes") private var savedWorkTypesRaw = ""
    let focusedLaborId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingRecord: LaborRecord?
    @State private var didOpenFocusedLabor = false
    @State private var newDate = Date()
    @State private var newWorkers = ""
    @State private var newDays = ""
    @State private var newUnitRate = ""
    @State private var newWorkType = ""
    @State private var newTeamName = ""
    @State private var newIsSettled = false
    @State private var newNote = ""
    @State private var newProjectId: UUID?
    @State private var projectFilter: UUID?
    @State private var settlementFilter: Bool? = nil
    @State private var operationNotice: OperationToastNotice?
    @State private var pendingDeleteCommitTask: Task<Void, Never>?
    @State private var pendingDeleteCommit: (() -> Void)?
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var exportProjectFilter: UUID?
    @State private var exportTeamFilter = ""
    @State private var exportWorkTypeFilter = ""
    @State private var exportStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var exportEndDate = Date()
    @State private var showExportConfig = false
    @State private var exportFormat: LaborExportFormat = .html
    @FocusState private var laborFormFocusedField: LaborFormField?

    init(focusedLaborId: UUID? = nil) {
        self.focusedLaborId = focusedLaborId
    }

    private var filtered: [LaborRecord] {
        var records = store.laborRecords
        if let sf = settlementFilter {
            records = records.filter { $0.isSettled == sf }
        }
        records = records.filter { projectFilter == nil || $0.projectId == projectFilter }
        return SearchMatcher.filter(records, keyword: searchText)
    }

    private var savedTeams: [String] {
        savedTeamsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var savedWorkTypes: [String] {
        savedWorkTypesRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var totalDays: Double {
        filtered.reduce(QuantityValue.zero) { partial, record in
            partial + QuantityValue(text: record.days)
        }.doubleValue
    }

    private var totalCost: Double {
        filtered.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    private var unsettledCost: Double {
        filtered.filter { !$0.isSettled }.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    private var settlementChipBinding: Binding<LaborSettlementChip> {
        Binding(
            get: { LaborSettlementChip(settlementFilter: settlementFilter) },
            set: { settlementFilter = $0.filterValue }
        )
    }

    var body: some View {
        List {
            Section(String(localized: "范围")) {
                ProjectContextStrip(
                    title: String(localized: "当前工程"),
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: String(localized: "全部项目")
                )
                FilterChipBar(
                    options: LaborSettlementChip.allCases,
                    selection: settlementChipBinding,
                    title: { $0.title }
                )
            }

            if filtered.isEmpty {
                Section(String(localized: "人工记录")) {
                    ContentUnavailableView(String(localized: "暂无人工记录"), systemImage: "person.2", description: Text(String(localized: "添加人工后可按工程统计工时与成本。")))
                    Button {
                        showAdd = true
                    } label: {
                        Label(String(localized: "添加人工记录"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            } else {
                Section(String(format: String(localized: "人工记录 (%d)"), filtered.count)) {
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
                        deleteLaborRecordsWithUndo(ids: ids)
                    }
                }
            }

            if !filtered.isEmpty {
                Section {
                    VStack(spacing: 4) {
                        HStack {
                            Text(String(localized: "记录数"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: String(localized: "%d 条"), filtered.count))
                                .monospacedDigit()
                        }
                        HStack {
                            Text(String(localized: "出工总天数"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: String(localized: "%@ 天"), totalDays.formatted(.number.precision(.fractionLength(0...1)))))
                                .monospacedDigit()
                        }
                        HStack {
                            Text(String(localized: "合计人工费"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ReportBuilder.money(totalCost))
                                .foregroundStyle(Color.appFinance)
                                .monospacedDigit()
                        }
                        if unsettledCost > 0 {
                            HStack {
                                Text(String(localized: "待结算金额"))
                                    .foregroundStyle(.appWarning)
                                Spacer()
                                Text(ReportBuilder.money(unsettledCost))
                                    .foregroundStyle(.appWarning)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "按工种、班组或备注搜索"))
        .navigationTitle(String(localized: "人工记录"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showExportConfig = true } label: {
                        Label(String(localized: "导出人工记录"), systemImage: "square.and.arrow.up")
                    }
                    Button { showAdd = true } label: {
                        Label(String(localized: "新增记录"), systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "更多操作"))
                Button { showAdd = true } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "新增人工记录"))
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker(String(localized: "日期"), selection: $newDate, displayedComponents: .date)

                        workTypePickerSection

                        teamPickerSection

                        LabeledContent(String(localized: "人数")) {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    TextField("0", text: $newWorkers.numericInput(.quantity))
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                        .focused($laborFormFocusedField, equals: .workers)
                                        .frame(minWidth: 72, alignment: .trailing)
                                    Text(String(localized: "人")).font(.subheadline).foregroundStyle(.secondary)
                                }
                                NumericInputValidationHint(
                                    validation: InputValidator.validate(
                                        newWorkers,
                                        kind: .quantity,
                                        requirement: .requiredNonNegative
                                    )
                                )
                            }
                        }
                        LabeledContent(String(localized: "出工天数")) {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    TextField("0", text: $newDays.numericInput(.days))
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                        .focused($laborFormFocusedField, equals: .hours)
                                        .frame(minWidth: 72, alignment: .trailing)
                                    Text(String(localized: "天")).font(.subheadline).foregroundStyle(.secondary)
                                }
                                NumericInputValidationHint(
                                    validation: InputValidator.validate(
                                        newDays,
                                        kind: .days,
                                        requirement: .requiredNonNegative
                                    )
                                )
                            }
                        }
                        LabeledContent(String(localized: "工价")) {
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 4) {
                                    TextField("0", text: $newUnitRate.numericInput(.laborRate))
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                        .focused($laborFormFocusedField, equals: .unitRate)
                                        .frame(minWidth: 88, alignment: .trailing)
                                    Text(String(localized: "元/天")).font(.subheadline).foregroundStyle(.secondary)
                                }
                                NumericInputValidationHint(
                                    validation: InputValidator.validate(
                                        newUnitRate,
                                        kind: .laborRate,
                                        requirement: .optionalNonNegative
                                    )
                                )
                            }
                        }
                        LabeledContent(String(localized: "合计人工费")) {
                            Text(ReportBuilder.money(newLaborTotal.doubleValue))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appFinance)
                                .monospacedDigit()
                        }
                    } header: { Text(String(localized: "人工明细")).font(.headline) }

                    Section {
                        Toggle(String(localized: "已结算"), isOn: $newIsSettled)
                        Picker(String(localized: "归属项目"), selection: $newProjectId) {
                            Text(String(localized: "无归属")).tag(nil as UUID?)
                            ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                        }
                        TextField(String(localized: "备注"), text: $newNote, axis: .vertical).lineLimit(2...4)
                    }
                }
                .navigationTitle(String(localized: "添加记录"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "取消")) { showAdd = false }
                    }
                ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "保存")) { save(); showAdd = false }
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
                    operationNotice = .info(String(localized: "已更新人工记录"))
                }
            } onDelete: { target in
                deleteLaborRecordsWithUndo(ids: [target.id])
            }
        }
        .onAppear(perform: openFocusedLaborIfNeeded)
        .onDisappear {
            flushPendingLaborDeletionIfNeeded()
        }
        .sheet(isPresented: $showExportConfig) {
            laborExportSheet
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .commaSeparatedText,
            defaultFilename: exportPayload?.defaultFilename ?? String(localized: "人工记录.csv")
        ) { _ in }
        .operationToast(notice: $operationNotice)
    }

    // MARK: - 工种选择（带工价记忆）

    @ViewBuilder
    private var workTypePickerSection: some View {
        if !savedWorkTypes.isEmpty {
            LabeledContent(String(localized: "工种")) {
                Menu {
                    ForEach(savedWorkTypes, id: \.self) { type in
                        Button(type) {
                            selectWorkType(type)
                        }
                    }
                    Divider()
                    Button(String(localized: "自定义")) {
                        newWorkType = ""
                    }
                } label: {
                    Text(newWorkType.isEmpty ? String(localized: "选择工种") : newWorkType)
                        .foregroundStyle(newWorkType.isEmpty ? .secondary : .primary)
                }
            }
        } else {
            TextField(String(localized: "工种（例如电工）"), text: $newWorkType)
                .onChange(of: newWorkType) { _, newVal in
                    autoFillRate(for: newVal)
                }
        }
    }

    // MARK: - 班组选择

    @ViewBuilder
    private var teamPickerSection: some View {
        if !savedTeams.isEmpty {
            LabeledContent(String(localized: "班组")) {
                Menu {
                    ForEach(savedTeams, id: \.self) { team in
                        Button(team) { newTeamName = team }
                    }
                    Divider()
                    Button(String(localized: "自定义")) { newTeamName = "" }
                } label: {
                    Text(newTeamName.isEmpty ? String(localized: "选择班组") : newTeamName)
                        .foregroundStyle(newTeamName.isEmpty ? .secondary : .primary)
                }
            }
        } else {
            TextField(String(localized: "班组（例如A组）"), text: $newTeamName)
        }
    }

    private func selectWorkType(_ type: String) {
        newWorkType = type
        autoFillRate(for: type)
    }

    private func autoFillRate(for workType: String) {
        let cleaned = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // 从保存的工价映射中查找
        let pairs = savedRatePairs()
        if let rate = pairs[cleaned], newUnitRate.isEmpty {
            newUnitRate = rate
        }
    }

    /// 存储 "工种:工价" 的映射，格式: "电工:130,木工:120"
    private var rateStorageKey: String {
        if let pid = newProjectId { return "labor.rates.\(pid.uuidString)" }
        return "labor.rates._global"
    }

    private func savedRatePairs() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: rateStorageKey) ?? ""
        var result = [String: String]()
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !val.isEmpty { result[key] = val }
            }
        }
        return result
    }

    private func saveRatePair(workType: String, rate: String) {
        let cleanedType = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRate = rate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedType.isEmpty, !cleanedRate.isEmpty else { return }
        var pairs = savedRatePairs()
        pairs[cleanedType] = cleanedRate
        let raw = pairs.map { "\($0):\($1)" }.joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: rateStorageKey)
    }

    private func saveTeamName(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !savedTeams.contains(cleaned) else { return }
        var teams = savedTeams
        teams.append(cleaned)
        savedTeamsRaw = teams.joined(separator: ",")
    }

    private func saveWorkType(_ type: String) {
        let cleaned = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !savedWorkTypes.contains(cleaned) else { return }
        var types = savedWorkTypes
        types.append(cleaned)
        savedWorkTypesRaw = types.joined(separator: ",")
    }

    private func laborRow(_ r: LaborRecord) -> some View {
        let projectText = r.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? String(localized: "未归属")
        let meta = [r.workType, r.teamName, "\(r.workers)人", "\(r.days)天", r.date].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 2)
                .fill(r.isSettled ? Color.appSuccess : Color.appFinance)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
                HStack {
                    Text(projectText)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.tight)
                    Text(ReportBuilder.money(ReportBuilder.laborLineTotal(r)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appFinance)
                        .monospacedDigit()
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !r.note.isEmpty {
                    Text(r.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func save() {
        guard canSave else { return }
        store.laborRecords.append(LaborRecord(
            date: Formatters.date.string(from: newDate),
            workers: NumericInputSupport.normalizedStorageText(newWorkers, kind: .quantity),
            hours: NumericInputSupport.normalizedStorageText(newDays, kind: .days),
            unitRate: NumericInputSupport.normalizedStorageText(newUnitRate, kind: .laborRate),
            workType: newWorkType,
            teamName: newTeamName,
            isSettled: newIsSettled,
            note: newNote,
            projectId: newProjectId
        ))
        saveTeamName(newTeamName)
        saveWorkType(newWorkType)
        if !newWorkType.isEmpty && !newUnitRate.isEmpty {
            saveRatePair(workType: newWorkType, rate: newUnitRate)
        }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已新增人工记录"))
        newWorkers = ""
        newDays = ""
        newUnitRate = ""
        newWorkType = ""
        newTeamName = ""
        newIsSettled = false
        newNote = ""
        newProjectId = nil
    }

    private var canSave: Bool {
        InputValidator.validate(newWorkers, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newDays, kind: .days, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newUnitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
    }

    private var newLaborTotal: MoneyValue {
        let totalDays = QuantityValue(text: newDays)
        let workers = QuantityValue(text: newWorkers)
        return workers * totalDays * MoneyValue(text: newUnitRate)
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

    private func deleteLaborRecordsWithUndo(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        flushPendingLaborDeletionIfNeeded()

        let snapshot = store.laborRecords
        let idSet = Set(ids)
        store.laborRecords.removeAll { idSet.contains($0.id) }

        pendingDeleteCommit = {
            store.scheduleSave()
        }
        pendingDeleteCommitTask = Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(4)) else { return }
            pendingDeleteCommit?()
            pendingDeleteCommit = nil
            pendingDeleteCommitTask = nil
        }

        operationNotice = OperationToastNotice(
            message: String(format: String(localized: "已删除 %d 条人工记录"), ids.count),
            actionTitle: String(localized: "撤销"),
            action: {
                pendingDeleteCommitTask?.cancel()
                pendingDeleteCommitTask = nil
                pendingDeleteCommit = nil
                store.laborRecords = snapshot
                store.scheduleSave()
                operationNotice = .info(String(localized: "已撤销删除"))
            },
            autoDismissDuration: .seconds(4)
        )
    }

    private func flushPendingLaborDeletionIfNeeded() {
        pendingDeleteCommitTask?.cancel()
        pendingDeleteCommitTask = nil
        pendingDeleteCommit?()
        pendingDeleteCommit = nil
    }

    // MARK: - 导出配置

    private var laborExportSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "筛选范围")) {
                    Picker(String(localized: "项目"), selection: $exportProjectFilter) {
                        Text(String(localized: "全部项目")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                    Picker(String(localized: "班组"), selection: $exportTeamFilter) {
                        Text(String(localized: "全部班组")).tag("")
                        ForEach(savedTeams, id: \.self) { t in Text(t).tag(t) }
                    }
                    Picker(String(localized: "工种"), selection: $exportWorkTypeFilter) {
                        Text(String(localized: "全部工种")).tag("")
                        ForEach(savedWorkTypes, id: \.self) { t in Text(t).tag(t) }
                    }
                    DatePicker(String(localized: "从"), selection: $exportStartDate, displayedComponents: .date)
                    DatePicker(String(localized: "至"), selection: $exportEndDate, displayedComponents: .date)
                }
                Section {
                    Picker(String(localized: "格式"), selection: $exportFormat) {
                        ForEach(LaborExportFormat.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    Button {
                        switch exportFormat {
                        case .csv: performCSVExport()
                        case .html: performHTMLExport()
                        }
                        showExportConfig = false
                    } label: {
                        Label(String(format: String(localized: "导出 %@"), exportFormat.displayName), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle(String(localized: "导出人工记录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showExportConfig = false }
                }
            }
        }
    }

    private func recordsForExport() -> [LaborRecord] {
        var records = store.laborRecords
        if let pid = exportProjectFilter { records = records.filter { $0.projectId == pid } }
        if !exportTeamFilter.isEmpty { records = records.filter { $0.teamName == exportTeamFilter } }
        if !exportWorkTypeFilter.isEmpty { records = records.filter { $0.workType == exportWorkTypeFilter } }
        let start = Formatters.date.string(from: exportStartDate)
        let end = Formatters.date.string(from: exportEndDate)
        records = records.filter { $0.date >= start && $0.date <= end }
        return records
    }

    private func performCSVExport() {
        let records = recordsForExport()
        var rows = ["日期,项目,工种,班组,人数,天数（天）,工价（元/天）,合计（元）,已结算,备注"]
        rows += records.map { r in
            let project = store.projects.first { $0.id == r.projectId }?.name ?? ""
            return [r.date, project, r.workType, r.teamName, r.workers, r.days, r.unitRate,
                    String(format: "%.2f", ReportBuilder.laborLineTotal(r)),
                    r.isSettled ? "是" : "否", r.note]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }
        let data = rows.joined(separator: "\n").data(using: .utf8) ?? Data()
        exportPayload = ExportPayload(data: data, contentType: .commaSeparatedText, defaultFilename: String(localized: "人工记录.csv"))
        showExporter = true
    }

    private func performHTMLExport() {
        let records = recordsForExport()
        let totalDays = records.reduce(QuantityValue.zero) { partial, record in
            partial + QuantityValue(text: record.days)
        }.doubleValue
        let totalCost = records.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
        let unsettledCost = records.filter { !$0.isSettled }.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }

        var html = """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <style>body{font-family:-apple-system,Helvetica;padding:20px;}
        h3{color:#333;}table{border-collapse:collapse;width:100%;margin:10px 0;}
        th{background:#f5f5f5;border:1px solid #ddd;padding:8px;text-align:left;font-size:13px;}
        td{border:1px solid #ddd;padding:7px;font-size:12px;}
        .settled{color:#2E8B3E;}.unsettled{color:#E5661A;}
        .summary{color:#666;font-size:13px;margin:8px 0;}
        .total{font-weight:bold;color:#E5661A;}</style></head><body>
        <h3>人工记录报表</h3>
        <p class="summary">\(records.count)条 · \(totalDays)天 · 合计 ¥\(String(format: "%.2f", totalCost)) · 待结 ¥\(String(format: "%.2f", unsettledCost))</p>
        <table><tr><th>日期</th><th>项目</th><th>工种</th><th>班组</th><th>人数</th><th>天数</th><th>工价</th><th>合计</th><th>状态</th></tr>
        """
        for r in records {
            let project = store.projects.first { $0.id == r.projectId }?.name ?? ""
            let statusClass = r.isSettled ? "settled" : "unsettled"
            let status = r.isSettled ? "已结算" : "待结算"
            html += "<tr><td>\(r.date)</td><td>\(project)</td><td>\(r.workType)</td><td>\(r.teamName)</td><td>\(r.workers)</td><td>\(r.days)</td><td>\(r.unitRate)</td><td class=\"total\">\(ReportBuilder.money(ReportBuilder.laborLineTotal(r)))</td><td class=\"\(statusClass)\">\(status)</td></tr>"
        }
        html += "<tr><td colspan=\"8\" style=\"text-align:right;font-weight:bold;\">合计</td><td class=\"total\">\(ReportBuilder.money(totalCost))</td><td></td></tr>"
        html += "</table><p class=\"summary\">导出时间: \(Formatters.now())</p></body></html>"

        let data = html.data(using: .utf8) ?? Data()
        exportPayload = ExportPayload(data: data, contentType: .excelHTML, defaultFilename: String(localized: "人工记录表.xls"))
        showExporter = true
    }
}

private enum LaborSettlementChip: CaseIterable, Hashable {
    case all
    case unsettled
    case settled

    init(settlementFilter: Bool?) {
        switch settlementFilter {
        case .some(true):
            self = .settled
        case .some(false):
            self = .unsettled
        case .none:
            self = .all
        }
    }

    var filterValue: Bool? {
        switch self {
        case .all:
            nil
        case .unsettled:
            false
        case .settled:
            true
        }
    }

    var title: String {
        switch self {
        case .all:
            String(localized: "全部")
        case .unsettled:
            String(localized: "待结算")
        case .settled:
            String(localized: "已结算")
        }
    }
}

private enum LaborExportFormat: String, CaseIterable {
    case html
    case csv

    var displayName: String {
        switch self {
        case .html: return String(localized: "Excel 表格")
        case .csv: return String(localized: "CSV")
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
                Section(String(localized: "人工")) {
                    DatePicker(String(localized: "日期"), selection: $date, displayedComponents: .date)
                    LabeledContent(String(localized: "人数")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                TextField("0", text: $workers.numericInput(.quantity))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($editLaborFormFocusedField, equals: .workers)
                                    .frame(minWidth: 72, alignment: .trailing)
                                Text(String(localized: "人"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    workers,
                                    kind: .quantity,
                                    requirement: .requiredNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "出工天数")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                TextField("0", text: $hours.numericInput(.days))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($editLaborFormFocusedField, equals: .hours)
                                    .frame(minWidth: 72, alignment: .trailing)
                                Text(String(localized: "天"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    hours,
                                    kind: .days,
                                    requirement: .requiredNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "工价")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 6) {
                                TextField("0", text: $unitRate.numericInput(.laborRate))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused($editLaborFormFocusedField, equals: .unitRate)
                                    .frame(minWidth: 88, alignment: .trailing)
                                Text(String(localized: "元/天"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    unitRate,
                                    kind: .laborRate,
                                    requirement: .optionalNonNegative
                                )
                            )
                        }
                    }
                    LabeledContent(String(localized: "合计人工费")) {
                        Text(ReportBuilder.money(editLaborTotal.doubleValue))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appFinance)
                            .monospacedDigit()
                    }
                    TextField(String(localized: "工种"), text: $workType)
                    TextField(String(localized: "班组"), text: $teamName)
                    Toggle(String(localized: "已结算"), isOn: $isSettled)
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "归属项目"), selection: $projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section(String(localized: "备注")) {
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(String(localized: "删除人工记录"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "编辑人工记录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
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
            .alert(String(localized: "删除这条人工记录？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete(record)
                    dismiss()
                }
            }
        }
    }

    private var updatedRecord: LaborRecord {
        var value = record
        value.date = Formatters.date.string(from: date)
        value.workers = NumericInputSupport.normalizedStorageText(workers, kind: .quantity)
        value.hours = NumericInputSupport.normalizedStorageText(hours, kind: .days)
        value.unitRate = NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate)
        value.workType = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        value.teamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.isSettled = isSettled
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.projectId = projectId
        return value
    }

    private var canSave: Bool {
        InputValidator.validate(workers, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(hours, kind: .days, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(unitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
    }

    private var editLaborTotal: MoneyValue {
        let totalWorkHours = QuantityValue(text: workers) * QuantityValue(text: hours)
        return totalWorkHours * MoneyValue(text: unitRate)
    }
}
