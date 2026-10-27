import SwiftUI

struct RepositoryQuoteEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryQuoteDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID?, id: UUID?) {
        self.session = session
        let record = QuoteItem(name: "", unitPrice: NumericInputSupport.money(""), quantity: NumericInputSupport.quantity(""), unit: "", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"), projectId: projectID)
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .quoteItems, id: id,
            initial: RepositoryQuoteDraft(record: record)))
    }

    private var canSave: Bool { (try? editor.draft.command()) != nil }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("报价单"), canSave: canSave, command: { try $0.command() }) {
            Section(AppLocalization.string("报价信息")) {
                TextField(AppLocalization.string("报价名称"), text: $editor.draft.record.name)
                    .accessibilityIdentifier("repository-quote-name")
                TextField(AppLocalization.string("单位"), text: $editor.draft.record.unit)
                    .accessibilityIdentifier("repository-quote-unit")
                TextField(AppLocalization.string("数量"), text: $editor.draft.quantityText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-quote-quantity")
                TextField(AppLocalization.string("单价"), text: $editor.draft.unitPriceText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-quote-price")
                TextField(AppLocalization.string("税率（%）"), text: $editor.draft.taxRateText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-quote-tax")
                TextField(AppLocalization.string("折扣率（%）"), text: $editor.draft.discountRateText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-quote-discount")
                if !canSave {
                    Text(AppLocalization.string("请填写报价名称、单位及非负的单价、数量和税率；折扣率须在 0–100 之间，合同金额可留空，金额须能精确计算。"))
                        .font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("repository-quote-value-error")
                }
            }
            Section(AppLocalization.string("报价版本与确认")) {
                TextField(AppLocalization.string("版本名称"), text: $editor.draft.record.versionName)
                    .accessibilityIdentifier("repository-quote-version")
                Picker(AppLocalization.string("报价状态"), selection: $editor.draft.record.status) {
                    ForEach(QuoteStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .accessibilityIdentifier("repository-quote-status")
                TextField(AppLocalization.string("客户确认日期"), text: $editor.draft.record.customerConfirmedDate.dateInputText)
                    .accessibilityIdentifier("repository-quote-date")
                TextField(AppLocalization.string("合同金额"), text: $editor.draft.contractAmountText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-quote-contract")
                TextField(AppLocalization.string("备注"), text: $editor.draft.record.notes, axis: .vertical)
                Text(AppLocalization.string("仅保存此副本中的报价。合同金额单独保留，不自动写回项目或财务记录。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
