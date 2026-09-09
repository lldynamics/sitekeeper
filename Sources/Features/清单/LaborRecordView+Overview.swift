import SwiftUI

extension LaborRecordView {
    var baseFiltered: [LaborRecord] {
        var records = store.laborRecords
        if let sf = settlementFilter {
            records = records.filter { $0.isSettled == sf }
        }
        records = records.filter { projectFilter == nil || $0.projectId == projectFilter }
        return SearchMatcher.filter(records, keyword: searchText)
    }

    var filtered: [LaborRecord] {
        baseFiltered.filter { unitFilter.matches($0) }
    }

    var savedTeams: [String] {
        savedTeamsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var savedWorkTypes: [String] {
        savedWorkTypesRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var totalWorkdays: QuantityValue {
        filtered
            .filter { $0.workloadUnit == .workday }
            .reduce(.zero) { $0 + $1.totalWorkloadValue }
    }

    var totalHours: QuantityValue {
        filtered
            .filter { $0.workloadUnit == .hour }
            .reduce(.zero) { $0 + $1.totalWorkloadValue }
    }

    var unconfirmedUnitCount: Int {
        baseFiltered.filter { $0.workloadUnit == .legacyUnspecified }.count
    }

    var totalCost: Double {
        filtered.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    var unsettledCost: Double {
        filtered.filter { !$0.isSettled }.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    var settlementChipBinding: Binding<LaborSettlementChip> {
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
                FilterChipBar(
                    options: LaborUnitFilterChip.allCases,
                    selection: $unitFilter,
                    title: { $0.title }
                )
                .accessibilityIdentifier("labor-unit-filter")
            }

            if unitFilter == .needsConfirmation, !filtered.isEmpty {
                Section(String(localized: "批量确认计量单位")) {
                    Text(String(localized: "仅更新当前筛选出的待确认记录；数值与金额保持不变。请选择这些历史记录原本使用的单位。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "批量确认为工时")) {
                        requestBulkUnitConfirmation(.hour)
                    }
                    .accessibilityIdentifier("labor-bulk-confirm-hour")
                    Button(String(localized: "批量确认为工天")) {
                        requestBulkUnitConfirmation(.workday)
                    }
                    .accessibilityIdentifier("labor-bulk-confirm-workday")
                }
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
                        if !totalWorkdays.isZero {
                            HStack {
                                Text(String(localized: "总工天"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(totalWorkdays.doubleValue.formatted(.number.precision(.fractionLength(0...2)))) \(String(localized: "工天"))")
                                    .monospacedDigit()
                            }
                        }
                        if !totalHours.isZero {
                            HStack {
                                Text(String(localized: "总工时"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(totalHours.doubleValue.formatted(.number.precision(.fractionLength(0...2)))) \(String(localized: "工时"))")
                                    .monospacedDigit()
                            }
                        }
                        if unconfirmedUnitCount > 0 {
                            Button {
                                unitFilter = .needsConfirmation
                            } label: {
                                HStack {
                                    Text(String(localized: "待确认单位"))
                                        .foregroundStyle(.appWarning)
                                    Spacer()
                                    Text(String(format: String(localized: "%d 条"), unconfirmedUnitCount))
                                        .foregroundStyle(.appWarning)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("labor-show-unconfirmed")
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
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                .accessibilityIdentifier("labor-add-record")
            }
        }
        .sheet(isPresented: $showAdd) {
            AppBusinessFormSheet(
                title: String(localized: "添加记录"),
                isPrimaryActionDisabled: !canSave,
                onCancel: { showAdd = false },
                onPrimaryAction: {
                    save()
                    showAdd = false
                }
            ) {
                Section {
                    DatePicker(String(localized: "日期"), selection: $newDate, displayedComponents: .date)

                    workTypePickerSection

                    teamPickerSection

                    LabeledContent(String(localized: "人数")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                TextField("0", text: $newWorkers.numericInput(.quantity))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("labor-workers-input")
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
                                    .accessibilityIdentifier("labor-duration-input")
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
                                    .accessibilityIdentifier("labor-rate-input")
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
            .toolbar {
                KeyboardNavigationToolbar(
                    focusedField: $laborFormFocusedField,
                    fields: [.workers, .hours, .unitRate]
                )
            }
        }
        .sheet(item: $editingRecord) { record in
            LaborRecordEditSheet(record: record, projects: store.projects) { updated in
                if store.updateLaborRecord(updated) {
                    store.scheduleSave()
                    operationNotice = .info(String(localized: "已更新人工记录"))
                }
            } onDelete: { target in
                deleteLaborRecordsWithUndo(ids: [target.id])
            }
        }
        .alert(String(localized: "确认批量设置人工单位？"), isPresented: $showBulkUnitConfirmation) {
            Button(String(localized: "取消"), role: .cancel) {
                clearPendingBulkUnitConfirmation()
            }
            Button(String(localized: "确认设置")) {
                applyBulkUnitConfirmation()
            }
            .accessibilityIdentifier("labor-bulk-confirm-apply")
        } message: {
            Text(bulkUnitConfirmationMessage)
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
        ) { result in
            switch result {
            case .success(let exportedURL):
                guard Self.isValidExportedFile(at: exportedURL) else {
                    AppHaptics.error()
                    operationNotice = .info(String(localized: "导出文件为空或写入不完整，请重试。"))
                    return
                }
                AppHaptics.success()
                exportPayload = nil
            case .failure(let error):
                guard (error as NSError).code != NSUserCancelledError else { return }
                AppHaptics.error()
                operationNotice = .info(String(format: String(localized: "导出失败：%@"), error.localizedDescription))
            }
        }
        .operationToast(notice: $operationNotice)
    }

    func openFocusedLaborIfNeeded() {
        guard let focusedLaborId, !didOpenFocusedLabor,
              let record = store.laborRecords.first(where: { $0.id == focusedLaborId }) else { return }
        didOpenFocusedLabor = true
        searchText = ""
        projectFilter = record.projectId
        Task { @MainActor in
            editingRecord = record
        }
    }

    func requestBulkUnitConfirmation(_ unit: LaborWorkloadUnit) {
        guard unit != .legacyUnspecified else { return }
        let visibleIDs = Set(filtered.map(\.id))
        let recordIDs = LaborUnitConfirmation.eligibleRecordIDs(in: filtered, limitedTo: visibleIDs)
        guard !recordIDs.isEmpty else { return }
        pendingBulkUnit = unit
        pendingBulkRecordIDs = recordIDs
        showBulkUnitConfirmation = true
    }

    var bulkUnitConfirmationMessage: String {
        guard let pendingBulkUnit else { return "" }
        return String(
            format: String(localized: "将当前筛选出的 %lld 条记录确认为“%@”？数值和金额不会换算。"),
            Int64(pendingBulkRecordIDs.count),
            pendingBulkUnit.displayName
        )
    }

    func applyBulkUnitConfirmation() {
        guard let pendingBulkUnit else { return }
        let ids = LaborUnitConfirmation.eligibleRecordIDs(
            in: store.laborRecords,
            limitedTo: pendingBulkRecordIDs
        )
        guard !ids.isEmpty else {
            clearPendingBulkUnitConfirmation()
            return
        }
        store.replaceLaborRecords(LaborUnitConfirmation.applying(
            pendingBulkUnit,
            to: store.laborRecords,
            recordIDs: ids
        ))
        store.scheduleSave()
        operationNotice = .info(String(
            format: String(localized: "已确认 %lld 条人工记录的计量单位"),
            Int64(ids.count)
        ))
        clearPendingBulkUnitConfirmation()
        unitFilter = .all
    }

    func clearPendingBulkUnitConfirmation() {
        pendingBulkUnit = nil
        pendingBulkRecordIDs = []
    }

    private static func isValidExportedFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return false
        }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}
