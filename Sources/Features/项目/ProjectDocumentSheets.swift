import SwiftUI

struct ProjectDocumentScanSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let constructionMethods: [ConstructionMethod]
    let onScan: (ProjectScanTarget) -> Void

    @State private var title = ""
    @State private var category: ProjectDocumentCategory = .construction
    @State private var amount = ""
    @State private var note = ""
    @State private var linkedMethodIDs: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("扫描资料") {
                    Text("扫描后会自动压缩（长边约 1800px，JPEG 质量约 0.7）以控制备份体积。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("资料名称", text: $title)
                        .focused($isInputFocused)
                    Picker("资料类型", selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("关联金额（元，可选）", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }
                Section("关联施工工艺") {
                    if constructionMethods.isEmpty {
                        Text("暂无可关联的施工工艺，请先到工具箱维护工艺库。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constructionMethods) { method in
                            Toggle(methodTitle(method), isOn: methodBinding(for: method.id))
                        }
                    }
                }
            }
            .navigationTitle("扫描项目资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始扫描") {
                        isInputFocused = false
                        onScan(ProjectScanTarget(
                            title: title,
                            category: category,
                            amount: amount,
                            linkedFinancialRecordId: nil,
                            linkedConstructionMethodIDs: sortedLinkedMethodIDs(),
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(!amount.isEmpty && !InputValidator.nonNegativeNumber(amount))
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isLinked in
                if isLinked {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "未命名工艺" : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }
}

struct ProjectDocumentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
    let constructionMethods: [ConstructionMethod]
    let onPreview: (ProjectDocument) -> Void
    let onSave: (ProjectDocument) -> Void
    let onDelete: (ProjectDocument) -> Void

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("资料") {
                    LabeledContent("名称", value: document.title)
                    LabeledContent("类型", value: document.category.displayName)
                    LabeledContent("页数", value: "\(document.pageCount)")
                    if document.amountValue.isPositive {
                        LabeledContent("金额", value: ReportBuilder.money(document.amountValue.doubleValue))
                    }
                    LabeledContent("创建时间", value: document.createdAt)
                    if !linkedMethodTitles.isEmpty {
                        LabeledContent("关联工艺", value: linkedMethodTitles.joined(separator: "、"))
                    }
                    if !document.note.isEmpty {
                        Text(document.note)
                    }
                }
                Section {
                    Button {
                        onPreview(document)
                    } label: {
                        Label("预览扫描件", systemImage: "eye.fill")
                    }
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("编辑资料", systemImage: "square.and.pencil")
                    }
                    Button("删除扫描件", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("扫描件详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("删除这份扫描件？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    onDelete(document)
                    dismiss()
                }
            } message: {
                Text("删除后，关联账目的附件标记会同步清除。")
            }
            .sheet(isPresented: $showEditSheet) {
                ProjectDocumentEditSheet(
                    document: document,
                    financialRecords: financialRecords,
                    constructionMethods: constructionMethods
                ) { updated in
                    onSave(updated)
                }
            }
        }
    }

    private var linkedMethodTitles: [String] {
        guard !document.linkedConstructionMethodIDs.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: constructionMethods.map { method in
            (method.id, methodTitle(method))
        })
        return document.linkedConstructionMethodIDs.compactMap { lookup[$0] }
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "未命名工艺" : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }
}

struct ProjectDocumentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
    let constructionMethods: [ConstructionMethod]
    let onSave: (ProjectDocument) -> Void

    @State private var title: String
    @State private var category: ProjectDocumentCategory
    @State private var amount: String
    @State private var note: String
    @State private var linkedFinancialRecordId: UUID?
    @State private var linkedMethodIDs: Set<UUID>
    @FocusState private var isInputFocused: Bool

    init(
        document: ProjectDocument,
        financialRecords: [ProjectFinancialRecord],
        constructionMethods: [ConstructionMethod],
        onSave: @escaping (ProjectDocument) -> Void
    ) {
        self.document = document
        self.financialRecords = financialRecords
        self.constructionMethods = constructionMethods
        self.onSave = onSave
        _title = State(initialValue: document.title)
        _category = State(initialValue: document.category)
        _amount = State(initialValue: document.amount)
        _note = State(initialValue: document.note)
        _linkedFinancialRecordId = State(initialValue: document.linkedFinancialRecordId)
        _linkedMethodIDs = State(initialValue: Set(document.linkedConstructionMethodIDs))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资料信息") {
                    TextField("资料名称", text: $title)
                        .focused($isInputFocused)
                    Picker("资料类型", selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("关联金额（元，可选）", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }

                Section("关联账目") {
                    Picker("账目", selection: $linkedFinancialRecordId) {
                        Text("不关联").tag(nil as UUID?)
                        ForEach(financialRecords) { item in
                            Text(recordLabel(item)).tag(item.id as UUID?)
                        }
                    }
                }

                Section("关联施工工艺") {
                    if constructionMethods.isEmpty {
                        Text("暂无可关联的施工工艺，请先到工具箱维护工艺库。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constructionMethods) { method in
                            Toggle(methodTitle(method), isOn: methodBinding(for: method.id))
                        }
                    }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        isInputFocused = false
                        onSave(updatedDocument)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!amount.isEmpty && !InputValidator.nonNegativeNumber(amount)))
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }

    private func recordLabel(_ record: ProjectFinancialRecord) -> String {
        let money = ReportBuilder.money(record.amountValue.doubleValue)
        return "\(record.date) · \(record.direction.displayName) \(money)"
    }

    private var updatedDocument: ProjectDocument {
        var value = document
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category
        value.amount = amount
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.linkedFinancialRecordId = linkedFinancialRecordId
        value.linkedConstructionMethodIDs = sortedLinkedMethodIDs()
        return value
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isLinked in
                if isLinked {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "未命名工艺" : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }
}
