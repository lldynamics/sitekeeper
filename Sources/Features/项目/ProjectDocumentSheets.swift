import SwiftUI

struct ProjectDocumentScanSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let onScan: (ProjectScanTarget) -> Void

    @State private var title = ""
    @State private var category: ProjectDocumentCategory = .construction
    @State private var amount = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("扫描资料") {
                    Text("扫描后会自动压缩（长边约 1800px，JPEG 质量约 0.7）以控制备份体积。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("资料名称", text: $title)
                    Picker("资料类型", selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("关联金额（可选）", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
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
                        onScan(ProjectScanTarget(
                            title: title,
                            category: category,
                            amount: amount,
                            linkedFinancialRecordId: nil,
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(!amount.isEmpty && !InputValidator.nonNegativeNumber(amount))
                }
            }
        }
    }
}

struct ProjectDocumentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
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
                    LabeledContent("类型", value: document.category)
                    LabeledContent("页数", value: "\(document.pageCount)")
                    if ReportBuilder.number(document.amount) > 0 {
                        LabeledContent("金额", value: ReportBuilder.money(ReportBuilder.number(document.amount)))
                    }
                    LabeledContent("创建时间", value: document.createdAt)
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
                ProjectDocumentEditSheet(document: document, financialRecords: financialRecords) { updated in
                    onSave(updated)
                }
            }
        }
    }
}

struct ProjectDocumentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
    let onSave: (ProjectDocument) -> Void

    @State private var title: String
    @State private var category: ProjectDocumentCategory
    @State private var amount: String
    @State private var note: String
    @State private var linkedFinancialRecordId: UUID?

    init(
        document: ProjectDocument,
        financialRecords: [ProjectFinancialRecord],
        onSave: @escaping (ProjectDocument) -> Void
    ) {
        self.document = document
        self.financialRecords = financialRecords
        self.onSave = onSave
        _title = State(initialValue: document.title)
        _category = State(initialValue: ProjectDocumentCategory(rawValue: document.category) ?? .other)
        _amount = State(initialValue: document.amount)
        _note = State(initialValue: document.note)
        _linkedFinancialRecordId = State(initialValue: document.linkedFinancialRecordId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资料信息") {
                    TextField("资料名称", text: $title)
                    Picker("资料类型", selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("关联金额（可选）", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("关联账目") {
                    Picker("账目", selection: $linkedFinancialRecordId) {
                        Text("不关联").tag(nil as UUID?)
                        ForEach(financialRecords) { item in
                            Text(recordLabel(item)).tag(item.id as UUID?)
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
                        onSave(updatedDocument)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!amount.isEmpty && !InputValidator.nonNegativeNumber(amount)))
                }
            }
        }
    }

    private func recordLabel(_ record: ProjectFinancialRecord) -> String {
        let money = ReportBuilder.money(ReportBuilder.number(record.amount))
        return "\(record.date) · \(record.direction) \(money)"
    }

    private var updatedDocument: ProjectDocument {
        var value = document
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category.rawValue
        value.amount = amount
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.linkedFinancialRecordId = linkedFinancialRecordId
        return value
    }
}
