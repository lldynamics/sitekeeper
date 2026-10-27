import SwiftUI

struct RepositoryFinancialEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryFinancialDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID, id: UUID?) {
        self.session = session
        let record = ProjectFinancialRecord(projectId: projectID, date: .day(CalendarDay(date: Date())))
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .projectFinancialRecords, id: id,
            initial: RepositoryFinancialDraft(record: record)))
    }

    private var canSave: Bool {
        RepositoryMoney.input(editor.draft.amountText) != nil && !editor.draft.record.date.isEmpty
    }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("财务记录"), canSave: canSave, command: { try $0.command() }) {
            Section(AppLocalization.string("收支信息")) {
                TextField(AppLocalization.string("日期"), text: $editor.draft.record.date.dateInputText)
                Picker(AppLocalization.string("收支方向"), selection: $editor.draft.record.direction) {
                    ForEach(ProjectFinancialDirection.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .accessibilityIdentifier("repository-finance-direction")
                Picker(AppLocalization.string("分类"), selection: $editor.draft.record.category) {
                    ForEach(editor.draft.record.direction.allowedCategories, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                TextField(AppLocalization.string("金额"), text: $editor.draft.amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("repository-finance-amount")
                if !editor.draft.amountText.isEmpty, RepositoryMoney.input(editor.draft.amountText) == nil {
                    Text(AppLocalization.string("请输入大于零的有效金额，使用小数点且最多保留 38 位有效数字。"))
                        .font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("repository-finance-amount-error")
                }
                Picker(AppLocalization.string("记录状态"), selection: $editor.draft.record.status) {
                    ForEach(ProjectFinancialStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .accessibilityIdentifier("repository-finance-status")
            }
            Section(AppLocalization.string("往来与票据")) {
                TextField(AppLocalization.string("往来单位"), text: $editor.draft.record.counterparty)
                    .accessibilityIdentifier("repository-finance-counterparty")
                TextField(AppLocalization.string("票据号码"), text: $editor.draft.record.invoiceNumber)
                TextField(AppLocalization.string("备注"), text: $editor.draft.record.note, axis: .vertical)
                Text(String(format: AppLocalization.string("保留 %lld 个资料关联"), Int64(editor.draft.record.linkedDocumentIds.count)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("提醒信息")) {
                TextField(AppLocalization.string("到期日期"), text: $editor.draft.record.dueDate.dateInputText)
                Picker(AppLocalization.string("提醒状态"), selection: $editor.draft.record.reminderStatus) {
                    ForEach(ProjectFinancialReminderStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                Text(AppLocalization.string("副本中的提醒信息仅保存，不安排系统通知。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: editor.draft.record.direction) { _, direction in
            editor.draft.record.category = ProjectFinancialCategory.normalized(editor.draft.record.category, for: direction)
        }
    }
}
