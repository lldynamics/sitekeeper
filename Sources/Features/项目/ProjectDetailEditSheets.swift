import SwiftUI
import UIKit

struct MaterialEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MaterialItem
    let useMetric: Bool
    let onSave: (MaterialItem) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var quantity: String
    @State private var unit: String
    @State private var unitPrice: String
    @State private var specification: String
    @State private var brand: String
    @State private var supplier: String
    @State private var purchaseStatus: MaterialPurchaseStatus
    @State private var arrivalDate: String

    init(item: MaterialItem, useMetric: Bool, onSave: @escaping (MaterialItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.useMetric = useMetric
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity)
        _unit = State(initialValue: item.unit)
        _unitPrice = State(initialValue: item.unitPrice)
        _specification = State(initialValue: item.specification)
        _brand = State(initialValue: item.brand)
        _supplier = State(initialValue: item.supplier)
        _purchaseStatus = State(initialValue: item.purchaseStatus)
        _arrivalDate = State(initialValue: item.arrivalDate)
    }

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "编辑材料"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(String(localized: "材料名称"), text: $name)
                TextField(String(localized: "数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(String(localized: "单位"), text: $unit)
                TextField(String(localized: "单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "规格"), text: $specification)
                TextField(String(localized: "品牌"), text: $brand)
                TextField(String(localized: "供应商"), text: $supplier)
                Picker(String(localized: "采购状态"), selection: $purchaseStatus) {
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(String(localized: "进场日期"), text: $arrivalDate)
                LabeledContent(String(localized: "金额")) {
                    Text(ReportBuilder.money(ReportBuilder.number(quantity) * ReportBuilder.number(unitPrice)))
                }
                AppBusinessFormDestructiveActionSection(title: String(localized: "删除材料")) {
                    onDelete(item.id)
                    dismiss()
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid
            && InputValidator.validate(unitPrice, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    private func saveAndDismiss() {
        var updated = item
        updated.name = name
        updated.quantity = NumericInputSupport.normalizedStorageText(quantity, kind: .quantity)
        updated.unit = unit
        updated.unitPrice = NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount)
        updated.specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.supplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.purchaseStatus = purchaseStatus
        updated.arrivalDate = ProjectDateInput.normalizedStorageText(arrivalDate)
        onSave(updated)
        dismiss()
    }
}

struct QuoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: QuoteItem
    let onSave: (QuoteItem) -> Void
    let onDelete: (UUID) -> Void

    @State private var name: String
    @State private var unitPrice: String
    @State private var quantity: String
    @State private var unit: String
    @State private var taxRate: String
    @State private var discountRate: String
    @State private var notes: String
    @State private var versionName: String
    @State private var status: QuoteStatus
    @State private var customerConfirmedDate: String
    @State private var contractAmount: String

    init(item: QuoteItem, onSave: @escaping (QuoteItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _unitPrice = State(initialValue: item.unitPrice)
        _quantity = State(initialValue: item.quantity)
        _unit = State(initialValue: item.unit)
        _taxRate = State(initialValue: item.taxRate)
        _discountRate = State(initialValue: item.discountRate)
        _notes = State(initialValue: item.notes)
        _versionName = State(initialValue: item.versionName)
        _status = State(initialValue: item.status)
        _customerConfirmedDate = State(initialValue: item.customerConfirmedDate)
        _contractAmount = State(initialValue: item.contractAmount)
    }

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "编辑报价"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(String(localized: "项目名称"), text: $name)
                TextField(String(localized: "单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(String(localized: "单位"), text: $unit)
                TextField(String(localized: "税率"), text: $taxRate.numericInput(.taxRate)).keyboardType(.decimalPad)
                TextField(String(localized: "折扣"), text: $discountRate.numericInput(.discountRate)).keyboardType(.decimalPad)
                TextField(String(localized: "版本"), text: $versionName)
                Picker(String(localized: "状态"), selection: $status) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $customerConfirmedDate)
                TextField(String(localized: "转合同金额"), text: $contractAmount.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(String(localized: "备注"), text: $notes)
                LabeledContent(String(localized: "合计")) {
                    let preview = QuoteItem(
                        id: item.id,
                        name: name,
                        unitPrice: unitPrice,
                        quantity: quantity,
                        unit: unit,
                        notes: notes,
                        taxRate: taxRate,
                        discountRate: discountRate,
                        versionName: versionName,
                        status: status,
                        customerConfirmedDate: customerConfirmedDate,
                        contractAmount: contractAmount,
                        projectId: item.projectId
                    )
                    Text(ReportBuilder.money(ReportBuilder.quoteGrandTotal(preview)))
                }
                AppBusinessFormDestructiveActionSection(title: String(localized: "删除报价")) {
                    onDelete(item.id)
                    dismiss()
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && InputValidator.validate(unitPrice, kind: .amount, requirement: .requiredNonNegative).isValid
            && InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid
            && InputValidator.validate(taxRate, kind: .taxRate, requirement: .requiredNonNegative).isValid
            && InputValidator.validate(discountRate, kind: .discountRate, requirement: .requiredNonNegative).isValid
            && InputValidator.validate(contractAmount, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    private func saveAndDismiss() {
        var updated = item
        updated.name = name
        updated.unitPrice = NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount)
        updated.quantity = NumericInputSupport.normalizedStorageText(quantity, kind: .quantity)
        updated.unit = unit
        updated.taxRate = NumericInputSupport.normalizedStorageText(taxRate, kind: .taxRate)
        updated.discountRate = NumericInputSupport.normalizedStorageText(discountRate, kind: .discountRate)
        updated.versionName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.status = status
        updated.customerConfirmedDate = ProjectDateInput.normalizedStorageText(customerConfirmedDate)
        updated.contractAmount = NumericInputSupport.normalizedStorageText(contractAmount, kind: .amount)
        updated.notes = notes
        onSave(updated)
        dismiss()
    }
}

struct ProgressEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ProgressTask
    let onSave: (ProgressTask) -> Void
    let onDelete: (UUID) -> Void

    @State private var title: String
    @State private var startDate: String
    @State private var dueDate: String
    @State private var completion: Double
    @State private var note: String

    init(item: ProgressTask, onSave: @escaping (ProgressTask) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: item.title)
        _startDate = State(initialValue: item.startDate)
        _dueDate = State(initialValue: item.dueDate)
        _completion = State(initialValue: item.clampedCompletion)
        _note = State(initialValue: item.note)
    }

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "编辑进度"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(String(localized: "任务"), text: $title)
                OptionalProjectDatePicker(String(localized: "开始日期"), text: $startDate)
                OptionalProjectDatePicker(String(localized: "截止日期"), text: $dueDate)
                Slider(value: $completion, in: 0...1, step: 0.05)
                LabeledContent(String(localized: "完成率"), value: "\(Int(completion * 100))%")
                TextField(String(localized: "备注"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                AppBusinessFormDestructiveActionSection(title: String(localized: "删除任务")) {
                    onDelete(item.id)
                    dismiss()
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAndDismiss() {
        var updated = item
        updated.title = title
        updated.startDate = ProjectDateInput.normalizedStorageText(startDate)
        updated.dueDate = ProjectDateInput.normalizedStorageText(dueDate)
        updated.completion = completion
        updated.note = note
        onSave(updated)
        dismiss()
    }
}

struct ProjectPhotoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let context: ProjectPhotoContext
    let allLogs: [DailyLog]
    let onSave: (String, PhotoTag) -> Void
    let onDelete: () -> Void

    @State private var note = ""
    @State private var tag: PhotoTag = .general
    @State private var showDeleteConfirm = false
    @State private var previewImage: UIImage?
    @State private var didAttemptLoadImage = false

    private var selectedPhoto: LogPhoto? {
        allLogs.first(where: { $0.id == context.logId })?
            .photoAttachments
            .first(where: { $0.id == context.photoId || $0.fileName == context.legacyFileName })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "照片预览")) {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if !didAttemptLoadImage {
                        ProgressView(String(localized: "加载中…"))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "图片已丢失或不可读取"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section(String(localized: "备注")) {
                    Picker(String(localized: "照片标签"), selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "现场备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(String(localized: "保存")) {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button(String(localized: "删除照片"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(String(localized: "照片详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .task(id: selectedPhoto?.fileName) {
                await loadPreviewImage()
            }
            .alert(String(localized: "删除这张照片？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "该操作仅删除当前照片，不会删除整条日志。"))
            }
        }
    }

    private func loadPreviewImage() async {
        didAttemptLoadImage = false
        previewImage = nil
        guard let fileName = selectedPhoto?.fileName else {
            didAttemptLoadImage = true
            return
        }
        if let data = await PhotoStorage.dataAsync(for: fileName),
           let image = UIImage(data: data) {
            previewImage = image
            didAttemptLoadImage = true
            return
        }
        if let thumbnail = await PhotoStorage.thumbnailAsync(for: fileName) {
            previewImage = thumbnail
        }
        didAttemptLoadImage = true
    }
}
