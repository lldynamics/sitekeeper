import SwiftUI

struct RepositoryMaterialEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryMaterialDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID?, id: UUID?) {
        self.session = session
        let record = MaterialItem(name: "", quantity: NumericInputSupport.quantity(""), unit: "", projectId: projectID)
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .materialItems, id: id,
            initial: RepositoryMaterialDraft(record: record)))
    }

    private var canSave: Bool { (try? editor.draft.command()) != nil }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("材料清单"), canSave: canSave, command: { try $0.command() }) {
            Section(AppLocalization.string("材料信息")) {
                TextField(AppLocalization.string("材料名称"), text: $editor.draft.record.name)
                    .accessibilityIdentifier("repository-material-name")
                TextField(AppLocalization.string("数量"), text: $editor.draft.quantityText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-material-quantity")
                TextField(AppLocalization.string("单位"), text: $editor.draft.record.unit)
                    .accessibilityIdentifier("repository-material-unit")
                TextField(AppLocalization.string("单价"), text: $editor.draft.unitPriceText)
                    .keyboardType(.decimalPad).accessibilityIdentifier("repository-material-price")
                Text(AppLocalization.string("单价可留空；零单价表示已确认无需费用。"))
                    .font(.caption).foregroundStyle(.secondary)
                if !canSave {
                    Text(AppLocalization.string("请填写材料名称、单位和非负数量。单价可留空或填写非负数，金额须能精确计算。"))
                        .font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("repository-material-value-error")
                }
                TextField(AppLocalization.string("规格"), text: $editor.draft.record.specification)
                TextField(AppLocalization.string("品牌"), text: $editor.draft.record.brand)
                TextField(AppLocalization.string("供应商"), text: $editor.draft.record.supplier)
            }
            Section(AppLocalization.string("采购信息")) {
                Picker(AppLocalization.string("采购状态"), selection: $editor.draft.record.purchaseStatus) {
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .accessibilityIdentifier("repository-material-status")
                TextField(AppLocalization.string("进场日期"), text: $editor.draft.record.arrivalDate.dateInputText)
                    .accessibilityIdentifier("repository-material-date")
                Text(AppLocalization.string("仅保存此副本中的材料，不同步报价、财务记录或仓储记录。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
