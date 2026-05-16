import SwiftUI

struct TemplateView: View {
    @Environment(DataStore.self) private var store
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newCategory: TemplateCategory = .quotation
    @State private var newContent = ""
    @State private var applyTarget: ProjectTemplate?
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    var body: some View {
        List {
            ForEach(TemplateCategory.allCases, id: \.self) { cat in
                Section(cat.displayName) {
                    let items = store.templates.filter { $0.category == cat }
                    if items.isEmpty {
                        ContentUnavailableView(
                            String(format: String(localized: "还没有%@"), cat.displayName),
                            systemImage: cat.emptyStateIcon,
                            description: Text(String(localized: "点击右上角 + 创建第一个模板"))
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
                            Button { applyTarget = tpl } label: { Label(String(localized: "应用"), systemImage: "arrow.turn.down.right") }
                                .tint(.appPrimaryAction)
                        }
                    }
                    .onDelete { idx in
                        let ids = Set(idx.compactMap { i in items.indices.contains(i) ? items[i].id : nil })
                        deleteTemplateIds(ids, source: "TemplateView")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "模板管理"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(String(localized: "新建模板"))
            }
        }
        .sheet(item: $applyTarget) { tpl in
            ApplyTemplateSheet(template: tpl)
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    TextField(String(localized: "模板名称"), text: $newName)
                    Picker(String(localized: "类型"), selection: $newCategory) {
                        ForEach(TemplateCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextEditor(text: $newContent).frame(minHeight: 150)
                }
                .navigationTitle(String(localized: "新建模板")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "保存")) {
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

    private func deleteTemplateIds(_ ids: Set<UUID>, source: String) {
        guard !ids.isEmpty else { return }
        let targets = store.templates.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeTemplates(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除模板 %lld 个"), Int64(targets.count)),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: source
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 个模板"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.templates = deletion.restoredItems(
                    current: store.templates,
                    id: \.id
                )
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
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
            return String(
                format: String(localized: "将新增 %lld 条材料记录。未识别行不会导入。"),
                Int64(materialParseResult.items.count)
            )
        case .quotation:
            return String(
                format: String(localized: "将新增 %lld 条报价记录。未识别行不会导入。"),
                Int64(quotationParseResult.items.count)
            )
        case .dailyLog:
            return String(localized: "将新增 1 条日志记录。")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "模板内容")) {
                    Text(template.content).font(.callout)
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "选择工程"), selection: $selectedProjectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                previewSection
                Section {
                    Button(String(localized: "预览无误，确认应用")) {
                        showApplyConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(!canApplyTemplate)
                }
            }
            .navigationTitle(String(format: String(localized: "应用：%@"), template.name)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } } }
        }
        .alert(String(localized: "确认应用模板？"), isPresented: $showApplyConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "确认应用")) {
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
            Section(String(localized: "解析预览")) {
                LabeledContent(
                    String(localized: "可导入材料"),
                    value: String(format: String(localized: "%lld 条"), Int64(materialParseResult.items.count))
                )
                if materialParseResult.items.isEmpty {
                    Text(String(localized: "未识别到可导入材料，请按“名称 × 数量单位”格式填写。"))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                } else {
                    ForEach(Array(materialParseResult.items.prefix(6))) { item in
                        Text("\(item.name) · \(item.quantity) \(item.unit)")
                            .font(.caption)
                    }
                    if materialParseResult.items.count > 6 {
                        Text(String(localized: "仅预览前 6 条"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !materialParseResult.rejectedLines.isEmpty {
                    Text(String(localized: "以下行未识别，不会导入："))
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
            Section(String(localized: "解析预览")) {
                LabeledContent(
                    String(localized: "可导入报价"),
                    value: String(format: String(localized: "%lld 条"), Int64(quotationParseResult.items.count))
                )
                if quotationParseResult.items.isEmpty {
                    Text(String(localized: "未识别到可导入报价，请按“名称 ¥ 单价”格式填写。"))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                } else {
                    ForEach(Array(quotationParseResult.items.prefix(6))) { item in
                        Text("\(item.name) · ¥\(item.unitPrice)")
                            .font(.caption)
                    }
                    if quotationParseResult.items.count > 6 {
                        Text(String(localized: "仅预览前 6 条"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if !quotationParseResult.rejectedLines.isEmpty {
                    Text(String(localized: "以下行未识别，不会导入："))
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
            Section(String(localized: "解析预览")) {
                Text(String(localized: "将以当前日期新增 1 条日志，内容为模板全文。"))
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
                        unit: String(localized: "项"),
                        notes: String(localized: "模板导入"),
                        taxRate: "0",
                        discountRate: "0",
                        projectId: selectedProjectId
                    )
                )
            }
        case .dailyLog:
            store.dailyLogs.insert(DailyLog(date: Formatters.date.string(from: Date()), weather: String(localized: "晴"), content: template.content, workers: "", photoFileName: nil, projectId: selectedProjectId), at: 0)
        }
        store.scheduleSave()
        AppHaptics.success()
        dismiss()
    }

    private func parseMaterialTemplate() -> MaterialTemplateParseResult {
        var result = MaterialTemplateParseResult()

        for rawLine in template.content.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parsed = NumericInputSupport.parseMaterialTemplateLine(
                line,
                defaultNumber: "",
                defaultUnit: String(localized: "材料默认单位")
            )

            guard !parsed.name.isEmpty, !parsed.quantity.isEmpty else {
                result.rejectedLines.append(line)
                continue
            }

            result.items.append(
                ParsedMaterialTemplateItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit
                )
            )
        }

        return result
    }

    private func parseQuotationTemplate() -> QuotationTemplateParseResult {
        var result = QuotationTemplateParseResult()

        for rawLine in template.content.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parsed = NumericInputSupport.parseQuotationTemplateLine(line, defaultPrice: "")

            guard !parsed.name.isEmpty, !parsed.price.isEmpty else {
                result.rejectedLines.append(line)
                continue
            }

            result.items.append(ParsedQuotationTemplateItem(name: parsed.name, unitPrice: parsed.price))
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
