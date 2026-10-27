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
    @State private var arrivalDate: BusinessDateValue

    init(item: MaterialItem, useMetric: Bool, onSave: @escaping (MaterialItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.useMetric = useMetric
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: item.quantity.wireText)
        _unit = State(initialValue: item.unit)
        _unitPrice = State(initialValue: item.unitPrice.wireText)
        _specification = State(initialValue: item.specification)
        _brand = State(initialValue: item.brand)
        _supplier = State(initialValue: item.supplier)
        _purchaseStatus = State(initialValue: item.purchaseStatus)
        _arrivalDate = State(initialValue: item.arrivalDate)
    }

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("编辑材料"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(AppLocalization.string("材料名称"), text: $name)
                TextField(AppLocalization.string("数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("单位"), text: $unit)
                TextField(AppLocalization.string("单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("规格"), text: $specification)
                TextField(AppLocalization.string("品牌"), text: $brand)
                TextField(AppLocalization.string("供应商"), text: $supplier)
                Picker(AppLocalization.string("采购状态"), selection: $purchaseStatus) {
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(AppLocalization.string("进场日期"), value: $arrivalDate)
                LabeledContent(AppLocalization.string("金额")) {
                    Text(ReportBuilder.money(NumericInputSupport.quantity(quantity) * NumericInputSupport.money(unitPrice)))
                }
                AppBusinessFormDestructiveActionSection(title: AppLocalization.string("删除材料")) {
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
        updated.quantity = NumericInputSupport.quantity(quantity)
        updated.unit = unit
        updated.unitPrice = NumericInputSupport.money(unitPrice)
        updated.specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.supplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.purchaseStatus = purchaseStatus
        updated.arrivalDate = arrivalDate
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
    @State private var customerConfirmedDate: BusinessDateValue
    @State private var contractAmount: String

    init(item: QuoteItem, onSave: @escaping (QuoteItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        self.item = item
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _unitPrice = State(initialValue: item.unitPrice.wireText)
        _quantity = State(initialValue: item.quantity.wireText)
        _unit = State(initialValue: item.unit)
        _taxRate = State(initialValue: item.taxRate.wireText)
        _discountRate = State(initialValue: item.discountRate.wireText)
        _notes = State(initialValue: item.notes)
        _versionName = State(initialValue: item.versionName)
        _status = State(initialValue: item.status)
        _customerConfirmedDate = State(initialValue: item.customerConfirmedDate)
        _contractAmount = State(initialValue: item.contractAmount.wireText)
    }

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("编辑报价"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(AppLocalization.string("项目名称"), text: $name)
                TextField(AppLocalization.string("单价"), text: $unitPrice.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("数量"), text: $quantity.numericInput(.quantity)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("单位"), text: $unit)
                TextField(AppLocalization.string("税率"), text: $taxRate.numericInput(.taxRate)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("折扣"), text: $discountRate.numericInput(.discountRate)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("版本"), text: $versionName)
                Picker(AppLocalization.string("状态"), selection: $status) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OptionalProjectDatePicker(AppLocalization.string("客户确认日期"), value: $customerConfirmedDate)
                TextField(AppLocalization.string("转合同金额"), text: $contractAmount.numericInput(.amount)).keyboardType(.decimalPad)
                TextField(AppLocalization.string("备注"), text: $notes)
                LabeledContent(AppLocalization.string("合计")) {
                    let preview = QuoteItem(
                        id: item.id,
                        name: name,
                        unitPrice: NumericInputSupport.money(unitPrice),
                        quantity: NumericInputSupport.quantity(quantity),
                        unit: unit,
                        notes: notes,
                        taxRate: NumericInputSupport.quantity(taxRate),
                        discountRate: NumericInputSupport.quantity(discountRate),
                        versionName: versionName,
                        status: status,
                        customerConfirmedDate: customerConfirmedDate,
                        contractAmount: NumericInputSupport.money(contractAmount),
                        projectId: item.projectId
                    )
                    Text(ReportBuilder.money(ReportBuilder.quoteGrandTotal(preview)))
                }
                AppBusinessFormDestructiveActionSection(title: AppLocalization.string("删除报价")) {
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
        updated.unitPrice = NumericInputSupport.money(unitPrice)
        updated.quantity = NumericInputSupport.quantity(quantity)
        updated.unit = unit
        updated.taxRate = NumericInputSupport.quantity(taxRate)
        updated.discountRate = NumericInputSupport.quantity(discountRate)
        updated.versionName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.status = status
        updated.customerConfirmedDate = customerConfirmedDate
        updated.contractAmount = NumericInputSupport.money(contractAmount)
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
    @State private var startDate: BusinessDateValue
    @State private var dueDate: BusinessDateValue
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
            title: AppLocalization.string("编辑进度"),
            isPrimaryActionDisabled: !canSave,
            onCancel: { dismiss() },
            onPrimaryAction: { saveAndDismiss() }
        ) {
            Form {
                TextField(AppLocalization.string("任务"), text: $title)
                OptionalProjectDatePicker(AppLocalization.string("开始日期"), value: $startDate)
                OptionalProjectDatePicker(AppLocalization.string("截止日期"), value: $dueDate)
                Slider(value: $completion, in: 0...1, step: 0.05)
                LabeledContent(AppLocalization.string("完成率"), value: "\(Int(completion * 100))%")
                TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                AppBusinessFormDestructiveActionSection(title: AppLocalization.string("删除任务")) {
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
        updated.startDate = startDate
        updated.dueDate = dueDate
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
                Section(AppLocalization.string("照片预览")) {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if !didAttemptLoadImage {
                        ProgressView(AppLocalization.string("加载中…"))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(AppLocalization.string("图片已丢失或不可读取"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section(AppLocalization.string("备注")) {
                    Picker(AppLocalization.string("照片标签"), selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(AppLocalization.string("现场备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button(AppLocalization.string("保存")) {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button(AppLocalization.string("删除照片"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(AppLocalization.string("照片详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("关闭")) { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .task(id: selectedPhoto?.fileName) {
                await loadPreviewImage()
            }
            .alert(AppLocalization.string("删除这张照片？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("删除"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(AppLocalization.string("取消"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("该操作仅删除当前照片，不会删除整条日志。"))
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
