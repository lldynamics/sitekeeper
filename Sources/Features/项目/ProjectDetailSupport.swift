import SwiftUI
import UIKit

enum ProjectDetailMode: String, CaseIterable {
    case overview
    case records
    case assets
    case finance
    case timeline

    var displayName: String {
        switch self {
        case .overview: "概览"
        case .records: "现场"
        case .assets: "资料"
        case .finance: "财务"
        case .timeline: "时间线"
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
        case .all: "全部"
        case .current: "当前版"
        case .withIssue: "有问题"
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
                        "暂无版本记录",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("同名图纸导入新版本后，可在这里查看版本时间线。")
                    )
                } else {
                    ForEach(drawings) { drawing in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(drawing.version).font(.callout.weight(.semibold))
                                if drawing.isCurrentVersion {
                                    Text("当前版")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.appSuccess)
                                }
                                Spacer()
                                Text(drawing.importedAt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !drawing.relatedLogDate.isEmpty {
                                Text("关联日志: \(drawing.relatedLogDate)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if drawing.issueStatus != .none {
                                Text("状态: \(drawing.issueStatus.displayName)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            if !drawing.issueNote.isEmpty {
                                Text("问题: \(drawing.issueNote)")
                                    .font(.caption2)
                                    .foregroundStyle(.appRisk)
                            }
                            HStack(spacing: 16) {
                                Button("预览") {
                                    onPreview(drawing)
                                }
                                .font(.caption)
                                Button("编辑") {
                                    onEdit(drawing)
                                    dismiss()
                                }
                                .font(.caption)
                                if !drawing.isCurrentVersion {
                                    Button("设为当前版") {
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
            .navigationTitle("\(drawingName) 时间线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
    @State private var linkedPreviewDrawingID: UUID?
    @State private var relatedLogDate: String
    @State private var issueStatus: DrawingIssueStatus
    @State private var issueNote: String
    @State private var textEncoding: CADDrawingTextEncoding
    @State private var textBigFont: CADDrawingTextBigFont
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
        _linkedPreviewDrawingID = State(initialValue: drawing.linkedPreviewDrawingID)
        _relatedLogDate = State(initialValue: drawing.relatedLogDate)
        _issueStatus = State(initialValue: drawing.issueStatus)
        _issueNote = State(initialValue: drawing.issueNote)
        _textEncoding = State(initialValue: drawing.textEncoding)
        _textBigFont = State(initialValue: drawing.textBigFont)
        _note = State(initialValue: drawing.note)
    }

    private var isCADSource: Bool {
        ProjectDetailDrawingHelper.isCADSource(drawing.fileType)
    }

    private var previewProxyCandidates: [ProjectDrawing] {
        relatedDrawings
            .filter { candidate in
                candidate.projectId == drawing.projectId &&
                candidate.id != drawing.id &&
                ["pdf", "dxf"].contains(candidate.fileType.lowercased())
            }
            .sorted { lhs, rhs in
                let leftSameName = ProjectDetailDrawingHelper.normalizedDrawingNameKey(lhs.name) ==
                    ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawing.name)
                let rightSameName = ProjectDetailDrawingHelper.normalizedDrawingNameKey(rhs.name) ==
                    ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawing.name)
                if leftSameName != rightSameName {
                    return leftSameName && !rightSameName
                }
                let leftSameVersion = ProjectDetailDrawingHelper.normalizedVersion(lhs.version) ==
                    ProjectDetailDrawingHelper.normalizedVersion(drawing.version)
                let rightSameVersion = ProjectDetailDrawingHelper.normalizedVersion(rhs.version) ==
                    ProjectDetailDrawingHelper.normalizedVersion(drawing.version)
                if leftSameVersion != rightSameVersion {
                    return leftSameVersion && !rightSameVersion
                }
                if lhs.fileType.lowercased() != rhs.fileType.lowercased() {
                    return lhs.fileType.lowercased() == "pdf"
                }
                let left = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
                let right = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
                return left > right
            }
    }

    private var selectedPreviewProxyText: String {
        guard let linkedPreviewDrawingID,
              let drawing = previewProxyCandidates.first(where: { $0.id == linkedPreviewDrawingID }) else {
            return String(localized: "未绑定")
        }
        return "\(drawing.name) · \(drawing.fileType.uppercased()) · \(drawing.version)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("图纸信息") {
                    TextField("图纸名称", text: $name)
                    TextField("版本号（如 V2）", text: $version)
                    LabeledContent("格式", value: drawing.fileType.uppercased())
                    LabeledContent("导入时间", value: drawing.importedAt)
                    Toggle("设为当前版本", isOn: $isCurrentVersion)
                    TextField("关联日志日期(yyyy-MM-dd)", text: $relatedLogDate)
                    Picker("问题状态", selection: $issueStatus) {
                        ForEach(DrawingIssueStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("问题标记", text: $issueNote, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                if isCADSource {
                    Section("预览代理") {
                        Picker("绑定文件", selection: $linkedPreviewDrawingID) {
                            Text("自动匹配 / 不绑定").tag(nil as UUID?)
                            ForEach(previewProxyCandidates) { candidate in
                                Text("\(candidate.name) · \(candidate.fileType.uppercased()) · \(candidate.version)")
                                    .tag(candidate.id as UUID?)
                            }
                        }
                        LabeledContent("当前", value: selectedPreviewProxyText)
                        if previewProxyCandidates.isEmpty {
                            Text("当前项目没有可绑定的 PDF 或 DXF。请先导入同图 PDF/DXF，再回到这里绑定。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("DWG 原件保留用于归档；应用内查看会优先打开这里绑定的 PDF/DXF。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("文字编码与字体") {
                        Picker("编码", selection: $textEncoding) {
                            ForEach(CADDrawingTextEncoding.allCases, id: \.self) { encoding in
                                Text(encoding.displayName).tag(encoding)
                            }
                        }
                        Picker("SHX/大字体", selection: $textBigFont) {
                            ForEach(CADDrawingTextBigFont.allCases, id: \.self) { profile in
                                Text(profile.displayName).tag(profile)
                            }
                        }
                        Text("遇到中文乱码可切换编码或 SHX/大字体映射后重试预览。设置会保存到这张图纸。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        onPreview(drawing)
                    } label: {
                        Label("预览图纸", systemImage: "eye.fill")
                    }
                }
                Section {
                    Button("删除图纸", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("图纸详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = drawing
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.name = trimmed.isEmpty ? drawing.name : trimmed
                        updated.version = version
                        updated.isCurrentVersion = isCurrentVersion
                        updated.linkedPreviewDrawingID = linkedPreviewDrawingID
                        updated.relatedLogDate = relatedLogDate.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.issueStatus = issueStatus
                        updated.issueNote = issueNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.textEncoding = textEncoding
                        updated.textBigFont = textBigFont
                        updated.note = note
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .alert("删除这份图纸？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    onDelete(drawing)
                    dismiss()
                }
            } message: {
                Text("删除后将无法在项目中预览该图纸。")
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
                TextField("材料名称", text: $name)
                TextField("数量", text: $quantity).keyboardType(.decimalPad)
                TextField("单位", text: $unit)
                TextField("单价", text: $unitPrice).keyboardType(.decimalPad)
                TextField("规格", text: $specification)
                TextField("品牌", text: $brand)
                TextField("供应商", text: $supplier)
                Picker("采购状态", selection: $purchaseStatus) {
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                TextField("进场日期(yyyy-MM-dd)", text: $arrivalDate)
                LabeledContent("金额") {
                    Text(ReportBuilder.money(ReportBuilder.number(quantity) * ReportBuilder.number(unitPrice)))
                }
                Section {
                    Button("删除材料", role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑材料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = item
                        updated.name = name
                        updated.quantity = quantity
                        updated.unit = unit
                        updated.unitPrice = unitPrice
                        updated.specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.supplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.purchaseStatus = purchaseStatus
                        updated.arrivalDate = arrivalDate.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.nonNegativeNumber(quantity) ||
                              !unitPrice.isEmpty && !InputValidator.nonNegativeNumber(unitPrice))
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
                TextField("项目名称", text: $name)
                TextField("单价", text: $unitPrice).keyboardType(.decimalPad)
                TextField("数量", text: $quantity).keyboardType(.decimalPad)
                TextField("单位", text: $unit)
                TextField("税率", text: $taxRate).keyboardType(.decimalPad)
                TextField("折扣", text: $discountRate).keyboardType(.decimalPad)
                TextField("版本", text: $versionName)
                Picker("状态", selection: $status) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                TextField("客户确认日期(yyyy-MM-dd)", text: $customerConfirmedDate)
                TextField("转合同金额", text: $contractAmount).keyboardType(.decimalPad)
                TextField("备注", text: $notes)
                LabeledContent("合计") {
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
                    Button("删除报价", role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑报价")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = item
                        updated.name = name
                        updated.unitPrice = unitPrice
                        updated.quantity = quantity
                        updated.unit = unit
                        updated.taxRate = taxRate
                        updated.discountRate = discountRate
                        updated.versionName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.status = status
                        updated.customerConfirmedDate = customerConfirmedDate.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.contractAmount = contractAmount
                        updated.notes = notes
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              !InputValidator.nonNegativeNumber(unitPrice) ||
                              !InputValidator.nonNegativeNumber(quantity) ||
                              !InputValidator.nonNegativeNumber(taxRate) ||
                              !InputValidator.nonNegativeNumber(discountRate) ||
                              (!contractAmount.isEmpty && !InputValidator.nonNegativeNumber(contractAmount)))
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
                TextField("任务", text: $title)
                TextField("开始日期(yyyy-MM-dd)", text: $startDate)
                TextField("截止日期(yyyy-MM-dd)", text: $dueDate)
                Slider(value: $completion, in: 0...1, step: 0.05)
                LabeledContent("完成率", value: "\(Int(completion * 100))%")
                TextField("备注", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                Section {
                    Button("删除任务", role: .destructive) {
                        onDelete(item.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑进度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = item
                        updated.title = title
                        updated.startDate = startDate
                        updated.dueDate = dueDate
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
                Section("照片预览") {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                    } else if !didAttemptLoadImage {
                        ProgressView("加载中…")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("图片已丢失或不可读取")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("备注") {
                    Picker("照片标签", selection: $tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("现场备注", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button("保存") {
                        onSave(note, tag)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    Button("删除照片", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("照片详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                note = selectedPhoto?.note ?? ""
                tag = selectedPhoto?.tag ?? .general
            }
            .task(id: selectedPhoto?.fileName) {
                await loadPreviewImage()
            }
            .alert("删除这张照片？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("该操作仅删除当前照片，不会删除整条日志。")
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
    @State private var content = ""; @State private var weather = "晴"
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
                    TextField("材料名称", text: $name)
                    LabeledContent("数量") {
                        TextField("0", text: $qty)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("单位") {
                        TextField("米 / 卷 / 个", text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("单价") {
                        TextField("0", text: $unitPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("规格型号", text: $materialSpecification)
                    TextField("品牌", text: $materialBrand)
                    TextField("供应商", text: $materialSupplier)
                    Picker("采购状态", selection: $materialPurchaseStatus) {
                        ForEach(MaterialPurchaseStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("进场日期（yyyy-MM-dd）", text: $materialArrivalDate)
                case .quote:
                    TextField("项目名称", text: $name)
                    LabeledContent("单价 ¥") {
                        TextField("0", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("数量") {
                        TextField("0", text: $qty)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("单位") {
                        TextField("项 / 米 / 台", text: $unit)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("版本", text: $quoteVersionName)
                    Picker("状态", selection: $quoteStatus) {
                        ForEach(QuoteStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    TextField("客户确认日期（yyyy-MM-dd）", text: $quoteConfirmedDate)
                    TextField("转合同金额", text: $quoteContractAmount)
                        .keyboardType(.decimalPad)
                case .log:
                    DatePicker("日期", selection: $logDate, displayedComponents: .date)
                    Picker("天气", selection: $weather) {
                        ForEach(["晴", "多云", "阴", "小雨", "大雨", "雪"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField("人数", text: $workers)
                    TextField("内容", text: $content, axis: .vertical).lineLimit(3...6)
                    TextField("安全事项", text: $safety, axis: .vertical).lineLimit(2...4)
                    TextField("材料进场", text: $materials, axis: .vertical).lineLimit(2...4)
                    TextField("明日计划", text: $tomorrowPlan, axis: .vertical).lineLimit(2...4)
                    TextField("质量问题", text: $qualityIssue, axis: .vertical).lineLimit(2...4)
                    TextField("整改记录", text: $rectification, axis: .vertical).lineLimit(2...4)
                    TextField("现场确认人", text: $confirmer)
                    Section("关联施工工艺") {
                        if constructionMethods.isEmpty {
                            Text("暂无可关联工艺，请先在施工工艺库新增条目。")
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
                    DatePicker("日期", selection: $laborDate, displayedComponents: .date)
                    TextField("班组（可选）", text: $laborTeamName)
                    Toggle("已结算", isOn: $laborIsSettled)
                    ForEach($laborLines) { $line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("工种 \(laborLineTitle(for: line.id))")
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
                            TextField("工种", text: $line.workType)
                            HStack(spacing: 10) {
                                TextField("人数", text: $line.workers)
                                    .keyboardType(.numberPad)
                                TextField("工时 (h)", text: $line.hours)
                                    .keyboardType(.decimalPad)
                            }
                            TextField("工价（每工时）", text: $line.unitRate)
                                .keyboardType(.decimalPad)
                            TextField("备注", text: $line.note)
                        }
                        .padding(.vertical, 2)
                    }
                    Button {
                        laborLines.append(.init())
                    } label: {
                        Label("添加工种", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(sheetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
        case .material: return "添加材料"
        case .quote: return "添加报价"
        case .log: return "写施工日志"
        case .labor: return "记人工"
        }
    }

    private func save() -> Bool {
        switch sheet {
        case .material:
            guard !name.isEmpty else { return false }
            store.appendMaterialItem(
                MaterialItem(
                    name: name,
                    quantity: qty,
                    unit: unit,
                    unitPrice: unitPrice,
                    specification: materialSpecification.trimmingCharacters(in: .whitespacesAndNewlines),
                    brand: materialBrand.trimmingCharacters(in: .whitespacesAndNewlines),
                    supplier: materialSupplier.trimmingCharacters(in: .whitespacesAndNewlines),
                    purchaseStatus: materialPurchaseStatus,
                    arrivalDate: materialArrivalDate.trimmingCharacters(in: .whitespacesAndNewlines),
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
                    unitPrice: price,
                    quantity: qty,
                    unit: unit,
                    notes: "",
                    taxRate: "0",
                    discountRate: "0",
                    versionName: quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : quoteVersionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: quoteStatus,
                    customerConfirmedDate: quoteConfirmedDate.trimmingCharacters(in: .whitespacesAndNewlines),
                    contractAmount: quoteContractAmount,
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
                        workers: workers,
                        hours: hours,
                        unitRate: unitRate,
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
            guard InputValidator.nonNegativeNumber(workers),
                  InputValidator.nonNegativeNumber(hours) else { return false }
            return unitRate.isEmpty || InputValidator.nonNegativeNumber(unitRate)
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
        return title.isEmpty ? "未命名工艺" : title
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
