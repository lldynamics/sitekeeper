import SwiftUI

extension LaborRecordView {
    var filtered: [LaborRecord] {
        var records = store.laborRecords
        if let sf = settlementFilter {
            records = records.filter { $0.isSettled == sf }
        }
        records = records.filter { projectFilter == nil || $0.projectId == projectFilter }
        return SearchMatcher.filter(records, keyword: searchText)
    }

    var savedTeams: [String] {
        savedTeamsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var savedWorkTypes: [String] {
        savedWorkTypesRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var totalDays: Double {
        filtered.reduce(QuantityValue.zero) { partial, record in
            partial + QuantityValue(text: record.days)
        }.doubleValue
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
}
