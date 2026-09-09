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

enum LaborUnitFilterChip: CaseIterable, Hashable {
    case all
    case needsConfirmation
    case hour
    case workday

    var title: String {
        switch self {
        case .all:
            String(localized: "全部单位")
        case .needsConfirmation:
            String(localized: "待确认单位")
        case .hour:
            String(localized: "工时")
        case .workday:
            String(localized: "工天")
        }
    }

    func matches(_ record: LaborRecord) -> Bool {
        switch self {
        case .all:
            true
        case .needsConfirmation:
            record.workloadUnit == .legacyUnspecified
        case .hour:
            record.workloadUnit == .hour
        case .workday:
            record.workloadUnit == .workday
        }
    }
}

enum LaborUnitConfirmation {
    static func eligibleRecordIDs(
        in records: [LaborRecord],
        limitedTo recordIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(records.lazy.filter {
            recordIDs.contains($0.id) && $0.workloadUnit == .legacyUnspecified
        }.map(\.id))
    }

    static func applying(
        _ unit: LaborWorkloadUnit,
        to records: [LaborRecord],
        recordIDs: Set<UUID>
    ) -> [LaborRecord] {
        guard unit != .legacyUnspecified else { return records }
        return records.map { record in
            guard recordIDs.contains(record.id), record.workloadUnit == .legacyUnspecified else { return record }
            var updated = record
            updated.workloadUnit = unit
            return updated
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
    @State private var workloadUnit: LaborWorkloadUnit
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
        _workloadUnit = State(initialValue: record.workloadUnit)
        _unitRate = State(initialValue: record.unitRate)
        _workType = State(initialValue: record.workType)
        _teamName = State(initialValue: record.teamName)
        _isSettled = State(initialValue: record.isSettled)
        _note = State(initialValue: record.note)
        _projectId = State(initialValue: record.projectId)
    }

    var body: some View {
        AppBusinessFormSheet(
            title: String(localized: "编辑人工记录"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: {
                onSave(updatedRecord)
                dismiss()
            }
        ) {
            Section(String(localized: "人工")) {
                DatePicker(String(localized: "日期"), selection: $date, displayedComponents: .date)
                Picker(String(localized: "单位"), selection: $workloadUnit) {
                    if workloadUnit == .legacyUnspecified {
                        Text(String(localized: "待确认单位")).tag(LaborWorkloadUnit.legacyUnspecified)
                    }
                    Text(String(localized: "工时")).tag(LaborWorkloadUnit.hour)
                    Text(String(localized: "工天")).tag(LaborWorkloadUnit.workday)
                }
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
                LabeledContent(workloadTitle) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            TextField("0", text: $hours.numericInput(.days))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($editLaborFormFocusedField, equals: .hours)
                                .frame(minWidth: 72, alignment: .trailing)
                            Text(workloadUnit.displayName)
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
                            Text(rateUnitTitle)
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
            AppBusinessFormDestructiveActionSection(title: String(localized: "删除人工记录")) {
                showDeleteConfirm = true
            }
        }
        .toolbar {
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

    private var updatedRecord: LaborRecord {
        var value = record
        value.date = Formatters.date.string(from: date)
        value.workers = NumericInputSupport.normalizedStorageText(workers, kind: .quantity)
        value.hours = NumericInputSupport.normalizedStorageText(hours, kind: .days)
        value.workloadUnit = workloadUnit
        value.unitRate = NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate)
        value.workType = workType.trimmingCharacters(in: .whitespacesAndNewlines)
        value.teamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        value.isSettled = isSettled
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.projectId = projectId
        return value
    }

    private var workloadTitle: String {
        switch workloadUnit {
        case .legacyUnspecified:
            String(localized: "工作量")
        case .hour:
            String(localized: "工时")
        case .workday:
            String(localized: "出工天数")
        }
    }

    private var rateUnitTitle: String {
        switch workloadUnit {
        case .legacyUnspecified:
            String(localized: "工价")
        case .hour:
            String(localized: "人工单价 ¥/工时")
        case .workday:
            String(localized: "元/天")
        }
    }

    private var canSave: Bool {
        workloadUnit != .legacyUnspecified &&
        InputValidator.validate(workers, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(hours, kind: .days, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(unitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
    }

    private var editLaborTotal: MoneyValue {
        var draft = record
        draft.workers = workers
        draft.hours = hours
        draft.workloadUnit = workloadUnit
        draft.unitRate = unitRate
        return MoneyValue(NSDecimalNumber(value: ReportBuilder.laborLineTotal(draft)).decimalValue)
    }
}
