import SwiftUI

struct TemplateView: View {
    @Environment(DataStore.self) private var store
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newCategory: TemplateCategory = .quotation
    @State private var newContent = ""
    @State private var applyTarget: ProjectTemplate?

    var body: some View {
        List {
            ForEach(TemplateCategory.allCases, id: \.self) { cat in
                Section(cat.displayName) {
                    let items = store.templates.filter { $0.category == cat }
                    if items.isEmpty {
                        ContentUnavailableView(
                            "还没有\(cat.displayName)",
                            systemImage: cat.emptyStateIcon,
                            description: Text("点击右上角 + 创建第一个模板")
                        )
                    }
                    ForEach(items) { tpl in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(cat.tintColor)
                                .frame(width: 4, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tpl.name)
                                    .font(.body.weight(.medium))
                                Text(tpl.content)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .leading) {
                            Button { applyTarget = tpl } label: { Label("应用", systemImage: "arrow.turn.down.right") }
                                .tint(.appPrimaryAction)
                        }
                    }
                    .onDelete { idx in
                        let ids = idx.compactMap { i in items.indices.contains(i) ? items[i].id : nil }
                        store.templates.removeAll { ids.contains($0.id) }
                        store.scheduleSave()
                        AppHaptics.success()
                    }
                }
            }
        }
        .navigationTitle("模板管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel("新建模板")
            }
        }
        .sheet(item: $applyTarget) { tpl in
            ApplyTemplateSheet(template: tpl)
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField("模板名称", text: $newName)
                    Picker("类型", selection: $newCategory) {
                        ForEach(TemplateCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextEditor(text: $newContent).frame(minHeight: 150)
                }
                .navigationTitle("新建模板").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard !newName.isEmpty else { return }
                            store.templates.append(ProjectTemplate(name: newName, category: newCategory, content: newContent))
                            store.scheduleSave()
                            AppHaptics.success()
                            newName = ""; newContent = ""; showAdd = false
                        }
                    }
                }
            }
        }
    }
}

private extension TemplateCategory {
    var tintColor: Color {
        switch self {
        case .quotation:
            return Color.appPrimaryAction
        case .dailyLog:
            return Color.appDoc
        case .material:
            return Color.appPrimaryAction
        }
    }

    var emptyStateIcon: String {
        switch self {
        case .quotation:
            return "doc.text.fill"
        case .dailyLog:
            return "book.pages.fill"
        case .material:
            return "shippingbox.fill"
        }
    }
}

struct ApplyTemplateSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let template: ProjectTemplate
    @State private var selectedProjectId: UUID?
    @State private var showApplyConfirm = false

    private var materialParseResult: MaterialTemplateParseResult {
        parseMaterialTemplate()
    }

    private var quotationParseResult: QuotationTemplateParseResult {
        parseQuotationTemplate()
    }

    private var canApplyTemplate: Bool {
        switch template.category {
        case .material:
            return !materialParseResult.items.isEmpty
        case .quotation:
            return !quotationParseResult.items.isEmpty
        case .dailyLog:
            return !template.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var applyConfirmMessage: String {
        switch template.category {
        case .material:
            return String(localized: "将新增 \(materialParseResult.items.count) 条材料记录。未识别行不会导入。")
        case .quotation:
            return String(localized: "将新增 \(quotationParseResult.items.count) 条报价记录。未识别行不会导入。")
        case .dailyLog:
            return "将新增 1 条日志记录。"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板内容") {
                    Text(template.content).font(.callout)
                }
                Section("归属项目") {
                    Picker("选择工程", selection: $selectedProjectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                previewSection
                Section {
                    Button("预览无误，确认应用") {
                        showApplyConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(!canApplyTemplate)
                }
            }
            .navigationTitle("应用: \(template.name)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .alert("确认应用模板？", isPresented: $showApplyConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认应用") {
                apply()
            }
        } message: {
            Text(applyConfirmMessage)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        switch template.category {
        case .material:
            Section("解析预览") {
                LabeledContent("可导入材料", value: "\(materialParseResult.items.count) 条")
                if materialParseResult.items.isEmpty {
                    Text("未识别到可导入材料，请按“名称 × 数量单位”格式填写。")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                } else {
                    ForEach(Array(materialParseResult.items.prefix(6))) { item in
                        Text("\(item.name) · \(item.quantity) \(item.unit)")
                            .font(.caption)
                    }
                    if materialParseResult.items.count > 6 {
                        Text("仅预览前 6 条")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !materialParseResult.rejectedLines.isEmpty {
                    Text("以下行未识别，不会导入：")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                    ForEach(Array(materialParseResult.rejectedLines.prefix(3)), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .quotation:
            Section("解析预览") {
                LabeledContent("可导入报价", value: "\(quotationParseResult.items.count) 条")
                if quotationParseResult.items.isEmpty {
                    Text("未识别到可导入报价，请按“名称 ¥ 单价”格式填写。")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                } else {
                    ForEach(Array(quotationParseResult.items.prefix(6))) { item in
                        Text("\(item.name) · ¥\(item.unitPrice)")
                            .font(.caption)
                    }
                    if quotationParseResult.items.count > 6 {
                        Text("仅预览前 6 条")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !quotationParseResult.rejectedLines.isEmpty {
                    Text("以下行未识别，不会导入：")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                    ForEach(Array(quotationParseResult.rejectedLines.prefix(3)), id: \.self) { line in
                        Text(line)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .dailyLog:
            Section("解析预览") {
                Text("将以当前日期新增 1 条日志，内容为模板全文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func apply() {
        switch template.category {
        case .material:
            for item in materialParseResult.items {
                store.materialItems.append(
                    MaterialItem(
                        name: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        projectId: selectedProjectId
                    )
                )
            }
        case .quotation:
            for item in quotationParseResult.items {
                store.quoteItems.append(
                    QuoteItem(
                        name: item.name,
                        unitPrice: item.unitPrice,
                        quantity: "1",
                        unit: "项",
                        notes: "模板导入",
                        taxRate: "0",
                        discountRate: "0",
                        projectId: selectedProjectId
                    )
                )
            }
        case .dailyLog:
            store.dailyLogs.insert(DailyLog(date: Formatters.date.string(from: Date()), weather: "晴", content: template.content, workers: "", photoFileName: nil, projectId: selectedProjectId), at: 0)
        }
        store.scheduleSave()
        AppHaptics.success()
        dismiss()
    }

    private func parseMaterialTemplate() -> MaterialTemplateParseResult {
        var result = MaterialTemplateParseResult()
        let separators: Set<Character> = ["×", "x", "X", "*", "＊"]

        for rawLine in template.content.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            guard let splitIndex = line.firstIndex(where: { separators.contains($0) }) else {
                result.rejectedLines.append(line)
                continue
            }

            let name = String(line[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valuePart = String(line[line.index(after: splitIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let quantity = valuePart.filter { "0123456789.".contains($0) }
            let unit = valuePart.filter { !"0123456789.".contains($0) && !$0.isWhitespace }

            guard !name.isEmpty else {
                result.rejectedLines.append(line)
                continue
            }

            result.items.append(
                ParsedMaterialTemplateItem(
                    name: name,
                    quantity: quantity.isEmpty ? "1" : quantity,
                    unit: unit.isEmpty ? "个" : unit
                )
            )
        }

        return result
    }

    private func parseQuotationTemplate() -> QuotationTemplateParseResult {
        var result = QuotationTemplateParseResult()
        let separators: Set<Character> = ["¥", "￥"]

        for rawLine in template.content.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            guard let splitIndex = line.firstIndex(where: { separators.contains($0) }) else {
                result.rejectedLines.append(line)
                continue
            }

            let name = String(line[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valuePart = String(line[line.index(after: splitIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let price = valuePart.filter { "0123456789.".contains($0) }

            guard !name.isEmpty, !price.isEmpty else {
                result.rejectedLines.append(line)
                continue
            }

            result.items.append(ParsedQuotationTemplateItem(name: name, unitPrice: price))
        }

        return result
    }
}

private struct MaterialTemplateParseResult {
    var items: [ParsedMaterialTemplateItem] = []
    var rejectedLines: [String] = []
}

private struct ParsedMaterialTemplateItem: Identifiable {
    let id = UUID()
    let name: String
    let quantity: String
    let unit: String
}

private struct QuotationTemplateParseResult {
    var items: [ParsedQuotationTemplateItem] = []
    var rejectedLines: [String] = []
}

private struct ParsedQuotationTemplateItem: Identifiable {
    let id = UUID()
    let name: String
    let unitPrice: String
}
