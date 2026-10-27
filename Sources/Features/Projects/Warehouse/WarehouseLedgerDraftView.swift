import SwiftUI

struct WarehouseLedgerDraftView: View {
    let movement: ProjectWarehouseMovement
    @Environment(DataStore.self) private var store
    @State private var unitPrice = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var linkedRecord: ProjectFinancialRecord? {
        store.projectFinancialRecords.first { $0.origin?.warehouseMovementID == movement.id }
    }

    var body: some View {
        Form {
            Section(movement.materialName) {
                LabeledContent(AppLocalization.string("数量"), value: "\(movement.quantity) \(movement.unit)")
                LabeledContent(AppLocalization.string("供应商"), value: movement.counterparty)
                if let record = linkedRecord {
                    LabeledContent(AppLocalization.string("金额"), value: ReportBuilder.money(record.amount))
                    NavigationLink {
                        ProjectDetailView(projectId: record.projectId, focus: .financialRecord(record.id))
                    } label: { Label(AppLocalization.string("打开关联账目"), systemImage: "book.closed") }
                    Text(AppLocalization.string("已有关联账目，重复操作会打开原记录。草稿需核对并改为正式后才计入汇总。"))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    TextField(AppLocalization.string("单价"), text: $unitPrice).keyboardType(.decimalPad)
                        .accessibilityIdentifier("warehouse.ledger.unitPrice")
                    LabeledContent(AppLocalization.string("金额"), value: ReportBuilder.money(movement.quantity * MoneyValue(storage: DecimalFieldStorage(text: unitPrice))))
                    Text(AppLocalization.string("请核对实际结算单价。生成的账目为草稿，票据关联会一并保留。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(AppLocalization.string("生成记账草稿")) { Task { await createDraft() } }
                        .disabled(isSaving || !MoneyValue(storage: DecimalFieldStorage(text: unitPrice)).isPositive)
                        .accessibilityIdentifier("warehouse.ledger.create")
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appRisk) } }
        }
        .navigationTitle(AppLocalization.string("入库记账"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if unitPrice.isEmpty { unitPrice = movement.origin?.unitPrice?.wireText ?? "" } }
    }

    private func createDraft() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement),
                unitPrice: MoneyValue(storage: DecimalFieldStorage(text: unitPrice)), store: store)
        } catch { errorMessage = error.localizedDescription }
    }
}
