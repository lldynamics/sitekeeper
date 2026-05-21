import SwiftUI

struct QuotationTemplateLibraryView: View {
    @Environment(DataStore.self) private var store
    @Environment(MaterialLibraryStore.self) private var materialLibraryStore
    let focusedTemplateId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingTemplate: ProjectTemplate?
    @State private var didOpenFocusedTemplate = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedTemplateId: UUID? = nil) {
        self.focusedTemplateId = focusedTemplateId
    }

    private var templates: [ProjectTemplate] {
        let items = materialLibraryStore.templates.filter { $0.category == .quotation }
        return SearchMatcher.filter(items, keyword: searchText)
    }

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView(
                    String(localized: "暂无报价模板"),
                    systemImage: "doc.text.fill",
                    description: Text(String(localized: "沉淀常用报价项目和单价，后续可快速套用。"))
                )
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
        .navigationTitle(String(localized: "报价模板库"))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(String(localized: "搜索模板名称或内容"))
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(String(localized: "添加报价模板"))
            }
        }
        .onAppear(perform: openFocusedTemplateIfNeeded)
        .sheet(isPresented: $showAdd) {
            QuoteTemplateEditSheet(template: nil) { template in
                store.insertTemplateAtTop(template)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingTemplate) { template in
            QuoteTemplateEditSheet(template: template) { updated in
                store.upsertTemplate(updated)
                store.scheduleSave()
                editingTemplate = nil
            } onDelete: { target in
                deleteTemplateIds(Set([target.id]))
                editingTemplate = nil
            }
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private func deleteTemplates(_ offsets: IndexSet) {
        let ids = Set(offsets.compactMap { templates.indices.contains($0) ? templates[$0].id : nil })
        deleteTemplateIds(ids)
    }

    private func deleteTemplateIds(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let snapshot = materialLibraryStore.templates
        let targets = snapshot.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeTemplates(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除报价模板 %lld 个"), Int64(targets.count)),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: "QuotationTemplateLibraryView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 个报价模板"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreTemplates(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func openFocusedTemplateIfNeeded() {
        guard let focusedTemplateId, !didOpenFocusedTemplate,
              let template = materialLibraryStore.templates.first(where: { $0.id == focusedTemplateId }) else { return }
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
                Section(String(localized: "模板")) {
                    TextField(String(localized: "名称"), text: $name)
                    TextField(String(localized: "报价内容"), text: $content, axis: .vertical)
                        .lineLimit(8...16)
                }
                Section(String(localized: "格式参考")) {
                    Text(String(localized: "一行一个项目，例如：\n布线 ¥45/m\n插座安装 ¥25/个"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if template != nil {
                    Section {
                        Button(String(localized: "删除报价模板"), role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(template == nil ? String(localized: "新增报价模板") : String(localized: "编辑报价模板"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        onSave(updatedTemplate)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(String(localized: "删除这个报价模板？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
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
