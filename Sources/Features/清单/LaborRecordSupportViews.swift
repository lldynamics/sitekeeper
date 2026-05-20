import SwiftUI

enum LaborSettlementChip: CaseIterable, Hashable {
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

enum LaborExportFormat: String, CaseIterable {
    case html
    case csv

    var displayName: String {
        switch self {
        case .html:
            String(localized: "Excel 表格")
        case .csv:
            String(localized: "CSV")
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
