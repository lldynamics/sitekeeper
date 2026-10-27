import SwiftUI

struct MaterialReceiptSheet: View {
    let material: MaterialItem
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var receiptID = UUID()
    @State private var quantity = ""
    @State private var unitPrice = ""
    @State private var date = Date()
    @State private var handler = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(material.name) {
                    let progress = MaterialWarehouseWorkflow.progress(material: material, movements: store.projectWarehouseMovements)
                    LabeledContent(AppLocalization.string("计划数量"), value: "\(progress.planned) \(material.unit)")
                    LabeledContent(AppLocalization.string("累计到货"), value: "\(progress.received) \(material.unit)")
                    LabeledContent(AppLocalization.string("待到货"), value: "\(progress.remaining) \(material.unit)")
                    Text(AppLocalization.string("到货生成入库记录，计划数量保持不变。可在入库详情中生成记账草稿。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(AppLocalization.string("本次到货")) {
                    TextField(AppLocalization.string("到货数量"), text: $quantity).keyboardType(.decimalPad)
                        .accessibilityIdentifier("material.receipt.quantity")
                    TextField(AppLocalization.string("单价"), text: $unitPrice).keyboardType(.decimalPad)
                    DatePicker(AppLocalization.string("日期"), selection: $date, displayedComponents: .date)
                    TextField(AppLocalization.string("经手人"), text: $handler)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appRisk) } }
            }
            .navigationTitle(AppLocalization.string("到货入库"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) { Task { await save() } }
                        .disabled(isSaving || !QuantityValue(storage: DecimalFieldStorage(text: quantity)).isPositive)
                        .accessibilityIdentifier("material.receipt.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { if unitPrice.isEmpty { unitPrice = material.unitPrice.wireText } }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await MaterialWarehouseWorkflow.receive(MaterialReceiptRequest(id: receiptID, materialID: material.id,
                expectedMaterial: BusinessDraftStore.fingerprint(material), quantity: QuantityValue(storage: DecimalFieldStorage(text: quantity)), unitPrice: MoneyValue(storage: DecimalFieldStorage(text: unitPrice)),
                date: .instant(date), handler: handler, note: note), store: store)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
