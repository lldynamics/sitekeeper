import SwiftUI

enum ProjectCreateNumericField: Hashable {
    case contractAmount
    case paidAmount
    case materialCost
    case laborCost
}

struct ProjectCreateSheet: View {
    @Binding var name: String
    @Binding var location: String
    @Binding var customerName: String
    @Binding var customerPhone: String
    @Binding var managerName: String
    @Binding var startDate: Date
    @Binding var expectedEndDate: Date
    @Binding var contractAmount: String
    @Binding var paidAmount: String
    @Binding var materialCost: String
    @Binding var laborCost: String
    @Binding var paymentStatus: PaymentStatus
    let focusedField: FocusState<ProjectCreateNumericField?>.Binding
    let canCreate: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("工程信息") {
                    TextField("工程名称", text: $name)
                    TextField("项目地址", text: $location, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("负责人", text: $managerName)
                }
                Section("客户") {
                    TextField("客户姓名/单位", text: $customerName)
                    TextField("客户电话", text: $customerPhone)
                        .keyboardType(.phonePad)
                }
                Section("工期") {
                    DatePicker("开工日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("预计完工", selection: $expectedEndDate, displayedComponents: .date)
                }
                Section("合同与收款") {
                    LabeledContent("合同金额") {
                        TextField("0", text: $contractAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused(focusedField, equals: .contractAmount)
                    }
                    LabeledContent("已收款") {
                        TextField("0", text: $paidAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused(focusedField, equals: .paidAmount)
                    }
                    LabeledContent("材料成本") {
                        TextField("0", text: $materialCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused(focusedField, equals: .materialCost)
                    }
                    LabeledContent("人工成本") {
                        TextField("0", text: $laborCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused(focusedField, equals: .laborCost)
                    }
                    Picker("收款状态", selection: $paymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }
            .navigationTitle("新建工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建", action: onCreate)
                        .disabled(!canCreate)
                }
                KeyboardNavigationToolbar(
                    focusedField: focusedField,
                    fields: [.contractAmount, .paidAmount, .materialCost, .laborCost]
                )
            }
        }
        .presentationDetents([.large])
    }
}
