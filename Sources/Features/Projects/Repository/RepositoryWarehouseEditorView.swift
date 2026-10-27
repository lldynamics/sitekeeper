import SwiftUI

struct RepositoryWarehouseEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryWarehouseDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID, id: UUID?) {
        self.session = session
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .projectWarehouseMovements, id: id,
            initial: RepositoryWarehouseDraft(record: ProjectWarehouseMovement(projectId: projectID))))
    }

    private var canSave: Bool {
        RepositoryMoney.input(editor.draft.quantityText) != nil && !MaterialIdentity.normalizedComponent(editor.draft.record.materialName).isEmpty && !editor.draft.record.date.isEmpty
    }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("出入库记录"), canSave: canSave, command: { try $0.command() }) {
            Section(AppLocalization.string("出入库")) {
                TextField(AppLocalization.string("日期"), text: $editor.draft.record.date.dateInputText)
                Picker(AppLocalization.string("类型"), selection: $editor.draft.record.movementType) {
                    ForEach(WarehouseMovementType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("repository-warehouse-type")
            }
            Section(AppLocalization.string("材料")) {
                TextField(AppLocalization.string("材料名称"), text: $editor.draft.record.materialName).accessibilityIdentifier("repository-warehouse-name")
                TextField(AppLocalization.string("规格/型号"), text: $editor.draft.record.specification).accessibilityIdentifier("repository-warehouse-specification")
                TextField(AppLocalization.string("单位"), text: $editor.draft.record.unit).accessibilityIdentifier("repository-warehouse-unit")
                TextField(AppLocalization.string("数量"), text: $editor.draft.quantityText).keyboardType(.decimalPad).accessibilityIdentifier("repository-warehouse-quantity")
                if !editor.draft.quantityText.isEmpty, RepositoryMoney.input(editor.draft.quantityText) == nil {
                    Text(AppLocalization.string("请输入大于零的有效数量，使用小数点且最多保留 38 位有效数字。"))
                        .font(.caption).foregroundStyle(.red).accessibilityIdentifier("repository-warehouse-quantity-error")
                }
            }
            Section(AppLocalization.string("往来与备注")) {
                TextField(AppLocalization.string("往来单位"), text: $editor.draft.record.counterparty)
                TextField(AppLocalization.string("经手人"), text: $editor.draft.record.handler)
                TextField(AppLocalization.string("备注"), text: $editor.draft.record.note, axis: .vertical)
                Text(String(format: AppLocalization.string("保留 %lld 个资料关联"), Int64(editor.draft.record.linkedDocumentIds.count)))
                    .font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.string("副本只保存仓储流水，不改写材料清单数量。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
