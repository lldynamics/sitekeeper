import SwiftUI

struct QuotationTemplateLibraryView: View {
    @Environment(DataStore.self) private var store
    let focusedTemplateId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingTemplate: ProjectTemplate?
    @State private var didOpenFocusedTemplate = false

    init(focusedTemplateId: UUID? = nil) {
        self.focusedTemplateId = focusedTemplateId
    }

    private var templates: [ProjectTemplate] {
        let items = store.templates.filter { $0.category == .quotation }
        return SearchMatcher.filter(items, keyword: searchText)
    }

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView("暂无报价模板", systemImage: "doc.text.fill", description: Text("沉淀常用报价项目和单价，后续可快速套用。"))
            } else {
                ForEach(templates) { template in
                    Button { editingTemplate = template } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(template.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(template.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteTemplates)
            }
        }
        .navigationTitle("报价模板库")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索模板名称或内容"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel("添加报价模板")
            }
        }
        .onAppear(perform: openFocusedTemplateIfNeeded)
        .sheet(isPresented: $showAdd) {
            QuoteTemplateEditSheet(template: nil) { template in
                store.templates.insert(template, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingTemplate) { template in
            QuoteTemplateEditSheet(template: template) { updated in
                if let index = store.templates.firstIndex(where: { $0.id == updated.id }) {
                    store.templates[index] = updated
                    store.scheduleSave()
                }
                editingTemplate = nil
            } onDelete: { target in
                store.templates.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingTemplate = nil
            }
        }
    }

    private func deleteTemplates(_ offsets: IndexSet) {
        let ids = offsets.compactMap { templates.indices.contains($0) ? templates[$0].id : nil }
        store.templates.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func openFocusedTemplateIfNeeded() {
        guard let focusedTemplateId, !didOpenFocusedTemplate,
              let template = store.templates.first(where: { $0.id == focusedTemplateId }) else { return }
        didOpenFocusedTemplate = true
        searchText = ""
        Task { @MainActor in
            editingTemplate = template
        }
    }
}

private struct QuoteTemplateEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let template: ProjectTemplate?
    let onSave: (ProjectTemplate) -> Void
    var onDelete: ((ProjectTemplate) -> Void)?

    @State private var name: String
    @State private var content: String
    @State private var showDeleteConfirm = false

    init(template: ProjectTemplate?, onSave: @escaping (ProjectTemplate) -> Void, onDelete: ((ProjectTemplate) -> Void)? = nil) {
        self.template = template
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: template?.name ?? "")
        _content = State(initialValue: template?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板") {
                    TextField("名称", text: $name)
                    TextField("报价内容", text: $content, axis: .vertical)
                        .lineLimit(8...16)
                }
                Section("格式参考") {
                    Text("一行一个项目，例如：\n布线 ¥45/m\n插座安装 ¥25/个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if template != nil {
                    Section {
                        Button("删除报价模板", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(template == nil ? "新增报价模板" : "编辑报价模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedTemplate)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这个报价模板？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = template { onDelete?(target) }
                    dismiss()
                }
            }
        }
    }

    private var updatedTemplate: ProjectTemplate {
        if var template {
            template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return template
        }
        return ProjectTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: .quotation, content: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
