import SwiftUI

extension MaterialListView {
    func materialRow(_ item: MaterialItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button {
                    toggleSelection(item.id)
                } label: {
                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(item.id) ? .appWarning : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("选择材料"))
                .accessibilityValue(selection.contains(item.id) ? AppLocalization.string("已选中") : AppLocalization.string("未选中"))
                .accessibilityHint(AppLocalization.string("双击切换选中状态"))
            }

            let quantityText = UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)
            let specText = [item.specification, item.brand, item.supplier].filter { !$0.isEmpty }.joined(separator: " · ")
            let projectText = item.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? AppLocalization.string("未归属")
            let meta = [quantityText, specText, projectText].filter { !$0.isEmpty }.joined(separator: " · ")
            let totalText = item.unitPrice.isPositive ? ReportBuilder.money(ReportBuilder.materialLineTotal(item)) : ""
            let noteText = item.arrivalDate.isEmpty
                ? item.purchaseStatus.displayName
                : String(format: AppLocalization.string("%@ · 进场 %@"), item.purchaseStatus.displayName, item.arrivalDate.storageText)
            BusinessRecordRow(
                icon: "shippingbox.fill",
                iconColor: purchaseStatusColor(item.purchaseStatus),
                title: item.name,
                meta: meta,
                note: noteText,
                trailing: totalText,
                trailingColor: Color.appPrimaryAction
            )
            Spacer()
            if !isSelecting {
                Button {
                    requestDeleteMaterials(
                        ids: [item.id],
                        message: String(format: AppLocalization.string("确认删除材料「%@」吗？"), item.name),
                        successMessage: AppLocalization.string("已删除材料")
                    )
                } label: {
                    Image(systemName: "trash").foregroundStyle(.appRisk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("删除材料"))
                .accessibilityValue(item.name)
                .accessibilityHint(AppLocalization.string("双击删除当前材料"))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelecting ? AppLocalization.string("双击选择或取消选择该材料") : AppLocalization.string("双击编辑材料"))
        .onTapGesture {
            if isSelecting {
                toggleSelection(item.id)
            } else {
                editingItem = item
            }
        }
        .contextMenu {
            if item.projectId != nil {
                Button(AppLocalization.string("到货入库"), systemImage: "shippingbox.and.arrow.backward") { receivingMaterial = item }
            }
        }
    }

    var bulkProjectForm: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("已选择")) {
                    LabeledContent(AppLocalization.string("材料项"), value: "\(selection.count)")
                }
                Section(AppLocalization.string("归属项目")) {
                    Picker(AppLocalization.string("归属项目"), selection: $bulkProjectId) {
                        Text(AppLocalization.string("无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section {
                    Button(AppLocalization.string("应用到已选材料")) {
                        applyBulkProject()
                        showBulkProjectSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
            .navigationTitle(AppLocalization.string("批量归属"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { showBulkProjectSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    func purchaseStatusColor(_ status: MaterialPurchaseStatus) -> Color {
        switch status {
        case .notPurchased: return .secondary
        case .purchased: return .appWarning
        case .arrived: return .appInventory
        case .used: return .appSuccess
        }
    }
}
