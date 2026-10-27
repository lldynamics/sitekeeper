import SwiftUI

struct RepositoryLaborEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryLaborDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID?, id: UUID?) {
        self.session = session
        let record = LaborRecord(date: .today(), workers: .empty, hours: .empty, note: "", projectId: projectID)
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .laborRecords, id: id,
            initial: RepositoryLaborDraft(record: record)))
    }

    private var canSave: Bool { (try? editor.draft.command()) != nil }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("人工记录"), canSave: canSave, command: { try $0.command() }) {
            Section(AppLocalization.string("人工记录")) {
                TextField(AppLocalization.string("班组"), text: $editor.draft.record.teamName).accessibilityIdentifier("repository-labor-team")
                TextField(AppLocalization.string("工种"), text: $editor.draft.record.workType).accessibilityIdentifier("repository-labor-work-type")
                TextField(AppLocalization.string("人数"), text: $editor.draft.workersText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-labor-workers")
                TextField(AppLocalization.string("工作量"), text: $editor.draft.hoursText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-labor-hours")
                Picker(AppLocalization.string("计量单位"), selection: $editor.draft.record.workloadUnit) {
                    ForEach(LaborWorkloadUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("repository-labor-unit")
                TextField(AppLocalization.string("单价"), text: $editor.draft.unitRateText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-labor-rate")
                if !canSave {
                    Text(AppLocalization.string("请确认计量单位并填写有效的非负人数与工作量，单价可留空；金额须能精确计算。"))
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                TextField(AppLocalization.string("日期"), text: $editor.draft.record.date.dateInputText).accessibilityIdentifier("repository-labor-date")
                Toggle(AppLocalization.string("已结算"), isOn: $editor.draft.record.isSettled).accessibilityIdentifier("repository-labor-settled")
                TextField(AppLocalization.string("备注"), text: $editor.draft.record.note, axis: .vertical).accessibilityIdentifier("repository-labor-note")
                Text(AppLocalization.string("仅保存此副本中的人工记录，不自动生成报价或财务流水。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
