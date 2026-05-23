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
                .accessibilityLabel(String(localized: "选择材料"))
                .accessibilityValue(selection.contains(item.id) ? String(localized: "已选中") : String(localized: "未选中"))
                .accessibilityHint(String(localized: "双击切换选中状态"))
            }

            let quantityText = UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)
            let specText = [item.specification, item.brand, item.supplier].filter { !$0.isEmpty }.joined(separator: " · ")
            let projectText = item.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? String(localized: "未归属")
            let meta = [quantityText, specText, projectText].filter { !$0.isEmpty }.joined(separator: " · ")
            let totalText = item.unitPriceValue.isPositive ? ReportBuilder.money(ReportBuilder.materialLineTotal(item)) : ""
            let noteText = item.arrivalDate.isEmpty
                ? item.purchaseStatus.displayName
                : String(format: String(localized: "%@ · 进场 %@"), item.purchaseStatus.displayName, item.arrivalDate)
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
                        message: String(format: String(localized: "确认删除材料「%@」吗？"), item.name),
                        successMessage: String(localized: "已删除材料")
                    )
                } label: {
                    Image(systemName: "trash").foregroundStyle(.appRisk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "删除材料"))
                .accessibilityValue(item.name)
                .accessibilityHint(String(localized: "双击删除当前材料"))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelecting ? String(localized: "双击选择或取消选择该材料") : String(localized: "双击编辑材料"))
        .onTapGesture {
            if isSelecting {
                toggleSelection(item.id)
            } else {
                editingItem = item
            }
        }
    }

    var bulkProjectForm: some View {
        NavigationStack {
            Form {
                Section(String(localized: "已选择")) {
                    LabeledContent(String(localized: "材料项"), value: "\(selection.count)")
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "归属项目"), selection: $bulkProjectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section {
                    Button(String(localized: "应用到已选材料")) {
                        applyBulkProject()
                        showBulkProjectSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
            .navigationTitle(String(localized: "批量归属"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showBulkProjectSheet = false }
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
