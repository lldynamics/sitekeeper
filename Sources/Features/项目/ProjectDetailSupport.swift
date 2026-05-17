import SwiftUI
import UIKit

enum ProjectDateInput {
    static func date(from text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Formatters.parseDateOrDateTime(normalized)
    }

    static func string(from date: Date) -> String {
        Formatters.date.string(from: date)
    }

    static func normalizedStorageText(_ text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return date(from: normalized).map(string(from:)) ?? normalized
    }
}

struct OptionalProjectDatePicker: View {
    private let title: String
    private let emptyToggleTitle: String
    @Binding private var text: String
    @State private var hasDate: Bool
    @State private var selectedDate: Date

    init(_ title: String, text: Binding<String>, defaultDate: Date = Date()) {
        self.title = title
        self.emptyToggleTitle = String(format: String(localized: "填写%@"), title)
        _text = text
        let parsed = ProjectDateInput.date(from: text.wrappedValue)
        _hasDate = State(initialValue: parsed != nil)
        _selectedDate = State(initialValue: parsed ?? defaultDate)
    }

    var body: some View {
        Toggle(emptyToggleTitle, isOn: Binding(
            get: { hasDate },
            set: { newValue in
                hasDate = newValue
                text = newValue ? ProjectDateInput.string(from: selectedDate) : ""
            }
        ))
        if hasDate {
            DatePicker(title, selection: Binding(
                get: { selectedDate },
                set: { newValue in
                    selectedDate = newValue
                    text = ProjectDateInput.string(from: newValue)
                }
            ), displayedComponents: .date)
            .onAppear {
                text = ProjectDateInput.string(from: selectedDate)
            }
        }
    }
}

enum ProjectDetailMode: String, CaseIterable {
    case overview
    case records
    case assets
    case finance
    case timeline

    static var allCases: [ProjectDetailMode] {
        [.overview, .records, .assets, .finance, .timeline]
    }

    var displayName: String {
        switch self {
        case .overview: String(localized: "概览")
        case .records: String(localized: "现场")
        case .assets: String(localized: "资料")
        case .finance: String(localized: "成本")
        case .timeline: String(localized: "时间线")
        }
    }
}

enum ProjectFinanceJumpFilter: Equatable {
    case none
    case unsettled
    case missingReceipt
}

enum DrawingListFilter: String, CaseIterable {
    case all
    case current
    case withIssue

    var displayName: String {
        switch self {
        case .all: String(localized: "全部")
        case .current: String(localized: "当前版")
        case .withIssue: String(localized: "有问题")
        }
    }
}

struct ProjectPhotoItem: Identifiable {
    var id: UUID { photo.id }
    let logId: UUID
    let date: String
    let photo: LogPhoto
}

struct ProjectPhotoContext: Identifiable {
    var id: String { "\(logId.uuidString)-\(photoId.uuidString)" }
    let logId: UUID
    let photoId: UUID
    let legacyFileName: String
}

struct DrawingTimelineContext: Identifiable {
    var id: String { name }
    let name: String
}

struct ProjectDrawingTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawingName: String
    let drawings: [ProjectDrawing]
    let onSetCurrent: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void
    let onEdit: (ProjectDrawing) -> Void

    var body: some View {
        NavigationStack {
            List {
                if drawings.isEmpty {
                    ContentUnavailableView(
                        String(localized: "暂无版本记录"),
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text(String(localized: "同名图纸导入新版本后，可在这里查看版本时间线。"))
                    )
                } else {
                    ForEach(drawings) { drawing in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(drawing.version).font(.callout.weight(.semibold))
                                if drawing.isCurrentVersion {
                                    Text(String(localized: "当前版"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.appSuccess)
                                }
                                Spacer()
                                Text(drawing.importedAt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !drawing.relatedLogDate.isEmpty {
                                Text(String(format: String(localized: "关联日志: %@"), drawing.relatedLogDate))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if drawing.issueStatus != .none {
                                Text(String(format: String(localized: "状态: %@"), drawing.issueStatus.displayName))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            if !drawing.issueNote.isEmpty {
                                Text(String(format: String(localized: "问题: %@"), drawing.issueNote))
                                    .font(.caption2)
                                    .foregroundStyle(.appRisk)
                            }
                            HStack(spacing: 16) {
                                Button(String(localized: "预览")) {
                                    onPreview(drawing)
                                }
                                .font(.caption)
                                Button(String(localized: "编辑")) {
                                    onEdit(drawing)
                                    dismiss()
                                }
                                .font(.caption)
                                if !drawing.isCurrentVersion {
                                    Button(String(localized: "设为当前版")) {
                                        onSetCurrent(drawing)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(String(format: String(localized: "%@ 时间线"), drawingName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
    }
}

struct ProjectDrawingEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let drawing: ProjectDrawing
    let relatedDrawings: [ProjectDrawing]
    let onSave: (ProjectDrawing) -> Void
    let onDelete: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void

    @State private var name: String
    @State private var version: String
    @State private var isCurrentVersion: Bool
    @State private var relatedLogDate: String
    @State private var issueStatus: DrawingIssueStatus
    @State private var issueNote: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(
        drawing: ProjectDrawing,
        relatedDrawings: [ProjectDrawing] = [],
        onSave: @escaping (ProjectDrawing) -> Void,
        onDelete: @escaping (ProjectDrawing) -> Void,
        onPreview: @escaping (ProjectDrawing) -> Void
    ) {
        self.drawing = drawing
        self.relatedDrawings = relatedDrawings
        self.onSave = onSave
        self.onDelete = onDelete
        self.onPreview = onPreview
        _name = State(initialValue: drawing.name)
        _version = State(initialValue: drawing.version)
        _isCurrentVersion = State(initialValue: drawing.isCurrentVersion)
        _relatedLogDate = State(initialValue: drawing.relatedLogDate)
        _issueStatus = State(initialValue: drawing.issueStatus)
        _issueNote = State(initialValue: drawing.issueNote)
        _note = State(initialValue: drawing.note)
    }

    private var isCADSource: Bool {
        ProjectDetailDrawingHelper.isCADSource(drawing.fileType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "图纸信息")) {
                    TextField(String(localized: "图纸名称"), text: $name)
                    TextField(String(localized: "版本号（如 V2）"), text: $version)
                    LabeledContent(String(localized: "格式"), value: drawing.fileType.uppercased())
                    LabeledContent(String(localized: "导入时间"), value: drawing.importedAt)
                    Toggle(String(localized: "设为当前版本"), isOn: $isCurrentVersion)
                    OptionalProjectDatePicker(String(localized: "关联日志日期"), text: $relatedLogDate)
                    Picker(String(localized: "问题状态"), selection: $issueStatus) {
                        ForEach(DrawingIssueStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField(String(localized: "问题标记"), text: $issueNote, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if isCADSource {
                    Section(String(localized: "独立文件预览")) {
                        Text(String(localized: "DWG、PDF、DXF 都按独立文件管理和打开，不用同名 PDF/DXF 作为预览代理。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        onPreview(drawing)
                    } label: {
                        Label(String(localized: "预览图纸"), systemImage: "eye.fill")
                    }
                }
                Section {
                    Button(String(localized: "删除图纸"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "图纸详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = drawing
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.name = trimmed.isEmpty ? drawing.name : trimmed
                        updated.version = version
                        updated.isCurrentVersion = isCurrentVersion
                        updated.relatedLogDate = ProjectDateInput.normalizedStorageText(relatedLogDate)
                        updated.issueStatus = issueStatus
                        updated.issueNote = issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = note
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "删除这份图纸？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete(drawing)
                    dismiss()
                }
            } message: {
                Text(String(localized: "删除后将无法在项目中预览该图纸。"))
            }
        }
    }
}

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
        NavigationStack {
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
                Section {
                    Button(String(localized: "删除材料"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑材料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(unitPrice, kind: .amount, requirement: .optionalNonNegative).isValid)
                }
            }
        }
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
        NavigationStack {
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
                Section {
                    Button(String(localized: "删除报价"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑报价"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.validate(unitPrice, kind: .amount, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(quantity, kind: .quantity, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(taxRate, kind: .taxRate, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(discountRate, kind: .discountRate, requirement: .requiredNonNegative).isValid ||
                              !InputValidator.validate(contractAmount, kind: .amount, requirement: .optionalNonNegative).isValid)
                }
            }
        }
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
        NavigationStack {
            Form {
                TextField(String(localized: "任务"), text: $title)
                OptionalProjectDatePicker(String(localized: "开始日期"), text: $startDate)
                OptionalProjectDatePicker(String(localized: "截止日期"), text: $dueDate)
                Slider(value: $completion, in: 0...1, step: 0.05)
                LabeledContent(String(localized: "完成率"), value: "\(Int(completion * 100))%")
                TextField(String(localized: "备注"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                Section {
                    Button(String(localized: "删除任务"), role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "编辑进度"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = item
                        updated.title = title
                        updated.startDate = ProjectDateInput.normalizedStorageText(startDate)
                        updated.dueDate = ProjectDateInput.normalizedStorageText(dueDate)
                        updated.completion = completion
                        updated.note = note
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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

struct QuickAddSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sheet: DetailSheet
    let projectId: UUID
    let constructionMethods: [ConstructionMethod]

    @State private var name = ""; @State private var qty = ""; @State private var unit = ""
    @State private var unitPrice = ""
    @State private var materialSpecification = ""
    @State private var materialBrand = ""
    @State private var materialSupplier = ""
    @State private var materialPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State private var materialArrivalDate = ""
    @State private var price = ""
    @State private var quoteVersionName = "V1"
    @State private var quoteStatus: QuoteStatus = .draft
    @State private var quoteConfirmedDate = ""
    @State private var quoteContractAmount = ""
    @State private var workers = ""
    @State private var laborTeamName = ""
    @State private var laborIsSettled = false
    @State private var laborLines: [QuickAddLaborLine] = [.init()]
    @State private var content = ""; @State private var weather = String(localized: "晴")
    @State private var safety = ""; @State private var materials = ""
    @State private var tomorrowPlan = ""; @State private var qualityIssue = ""
    @State private var rectification = ""; @State private var confirmer = ""
    @State private var logDate = Date()
    @State private var laborDate = Date()
    @State private var linkedMethodIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                switch sheet {
                case .material:
                    TextField(String(localized: "材料名称"), text: $name)
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "米 / 卷 / 个"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单价")) {
                        TextField("0", text: $unitPrice.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "规格型号"), text: $materialSpecification)
                    TextField(String(localized: "品牌"), text: $materialBrand)
                    TextField(String(localized: "供应商"), text: $materialSupplier)
                    Picker(String(localized: "采购状态"), selection: $materialPurchaseStatus) {
                        ForEach(MaterialPurchaseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "进场日期"), text: $materialArrivalDate)
                case .quote:
                    TextField(String(localized: "项目名称"), text: $name)
                    LabeledContent(String(localized: "单价 ¥")) {
                        TextField("0", text: $price.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "数量")) {
                        TextField("0", text: $qty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "单位")) {
                        TextField(String(localized: "项 / 米 / 台"), text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(String(localized: "版本"), text: $quoteVersionName)
                    Picker(String(localized: "状态"), selection: $quoteStatus) {
                        ForEach(QuoteStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $quoteConfirmedDate)
                    TextField(String(localized: "转合同金额"), text: $quoteContractAmount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                case .log:
                    DatePicker(String(localized: "日期"), selection: $logDate, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $weather) {
                        ForEach([String(localized: "晴"), String(localized: "多云"), String(localized: "阴"), String(localized: "小雨"), String(localized: "大雨"), String(localized: "雪")], id: \.self) { Text($0).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $workers)
                    TextField(String(localized: "内容"), text: $content, axis: .vertical).lineLimit(3...6)
                    TextField(String(localized: "安全事项"), text: $safety, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "材料进场"), text: $materials, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "明日计划"), text: $tomorrowPlan, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $qualityIssue, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $rectification, axis: .vertical).lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $confirmer)
                    Section(String(localized: "关联施工工艺")) {
                        if constructionMethods.isEmpty {
                            Text(String(localized: "暂无可关联工艺，请先在施工工艺库新增条目。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(constructionMethods) { method in
                                Toggle(isOn: methodBinding(for: method.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(methodTitle(method))
                                        HStack(spacing: 6) {
                                            if !method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                Text(method.trade)
                                            }
                                            Text(method.versionName.isEmpty ? "V1" : method.versionName)
                                            Text(method.publishStatus.displayName)
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case .labor:
                    DatePicker(String(localized: "日期"), selection: $laborDate, displayedComponents: .date)
                    TextField(String(localized: "班组（可选）"), text: $laborTeamName)
                    Toggle(String(localized: "已结算"), isOn: $laborIsSettled)
                    ForEach($laborLines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(format: String(localized: "工种 %@"), laborLineTitle(for: line.id)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if laborLines.count > 1 {
                                    Button(role: .destructive) {
                                        removeLaborLine(id: line.id)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            TextField(String(localized: "工种"), text: $line.workType)
                            HStack(spacing: 10) {
                                TextField(String(localized: "人数"), text: $line.workers.numericInput(.quantity))
                                    .keyboardType(.numberPad)
                                TextField(String(localized: "工时 (h)"), text: $line.hours.numericInput(.days))
                                    .keyboardType(.decimalPad)
                            }
                            TextField(String(localized: "工价（每工时）"), text: $line.unitRate.numericInput(.laborRate))
                                .keyboardType(.decimalPad)
                            TextField(String(localized: "备注"), text: $line.note)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        laborLines.append(.init())
                    } label: {
                        Label(String(localized: "添加工种"), systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(sheetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        if save() {
                            dismiss()
                        }
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var sheetTitle: String {
        switch sheet {
        case .material: return String(localized: "添加材料")
        case .quote: return String(localized: "添加报价")
        case .log: return String(localized: "写施工日志")
        case .labor: return String(localized: "记人工")
        }
    }

    private func save() -> Bool {
        switch sheet {
        case .material:
            guard !name.isEmpty else { return false }
            store.appendMaterialItem(
                MaterialItem(
                    name: name,
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    unitPrice: NumericInputSupport.normalizedStorageText(unitPrice, kind: .amount),
                    specification: materialSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: materialBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                    supplier: materialSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                    purchaseStatus: materialPurchaseStatus,
                    arrivalDate: ProjectDateInput.normalizedStorageText(materialArrivalDate),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .quote:
            guard !name.isEmpty else { return false }
            store.appendQuoteItem(
                QuoteItem(
                    name: name,
                    unitPrice: NumericInputSupport.normalizedStorageText(price, kind: .amount),
                    quantity: NumericInputSupport.normalizedStorageText(qty, kind: .quantity),
                    unit: unit,
                    notes: "",
                    taxRate: "0",
                    discountRate: "0",
                    versionName: quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: quoteStatus,
                    customerConfirmedDate: ProjectDateInput.normalizedStorageText(quoteConfirmedDate),
                    contractAmount: NumericInputSupport.normalizedStorageText(quoteContractAmount, kind: .amount),
                    projectId: projectId
                )
            )
            store.scheduleSave()
            return true
        case .log:
            store.insertDailyLogAtTop(DailyLog(
                date: Formatters.date.string(from: logDate),
                weather: weather,
                content: content,
                workers: workers,
                photoFileName: nil,
                safety: safety,
                materials: materials,
                tomorrowPlan: tomorrowPlan,
                qualityIssue: qualityIssue,
                rectification: rectification,
                confirmer: confirmer,
                linkedConstructionMethodIDs: sortedLinkedMethodIDs(),
                projectId: projectId
            ))
            store.scheduleSave()
            return true
        case .labor:
            guard canSaveLaborLines else { return false }
            let teamName = laborTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = Formatters.date.string(from: laborDate)
            var appendedCount = 0
            for line in laborLines where line.hasContent {
                let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
                let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
                let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
                let workType = line.workType.trimmingCharacters(in: .whitespacesAndNewlines)
                let note = line.note.trimmingCharacters(in: .whitespacesAndNewlines)
                store.appendLaborRecord(
                    LaborRecord(
                        date: date,
                        workers: NumericInputSupport.normalizedStorageText(workers, kind: .quantity),
                        hours: NumericInputSupport.normalizedStorageText(hours, kind: .days),
                        unitRate: NumericInputSupport.normalizedStorageText(unitRate, kind: .laborRate),
                        workType: workType,
                        teamName: teamName,
                        isSettled: laborIsSettled,
                        note: note,
                        projectId: projectId
                    )
                )
                appendedCount += 1
            }
            guard appendedCount > 0 else { return false }
            store.scheduleSave()
            return true
        }
    }

    private func laborLineTitle(for id: UUID) -> String {
        if let index = laborLines.firstIndex(where: { $0.id == id }) {
            return "#\(index + 1)"
        }
        return ""
    }

    private func removeLaborLine(id: UUID) {
        guard laborLines.count > 1 else { return }
        laborLines.removeAll { $0.id == id }
    }

    private var canSaveLaborLines: Bool {
        let filledLines = laborLines.filter(\.hasContent)
        guard !filledLines.isEmpty else { return false }
        return filledLines.allSatisfy { line in
            let workers = line.workers.trimmingCharacters(in: .whitespacesAndNewlines)
            let hours = line.hours.trimmingCharacters(in: .whitespacesAndNewlines)
            let unitRate = line.unitRate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard InputValidator.validate(workers, kind: .quantity, requirement: .requiredNonNegative).isValid,
                  InputValidator.validate(hours, kind: .days, requirement: .requiredNonNegative).isValid else { return false }
            return InputValidator.validate(unitRate, kind: .laborRate, requirement: .optionalNonNegative).isValid
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isOn in
                if isOn {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        linkedMethodIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "未命名工艺") : title
    }
}

private struct QuickAddLaborLine: Identifiable {
    var id = UUID()
    var workType = ""
    var workers = ""
    var hours = ""
    var unitRate = ""
    var note = ""

    var hasContent: Bool {
        !workType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !hours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !unitRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
