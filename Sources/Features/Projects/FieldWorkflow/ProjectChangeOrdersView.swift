import SwiftUI

struct ProjectChangeOrdersView: View {
    private let projectID: UUID
    @Environment(DataStore.self) private var store
    @State private var editing: ChangeOrderSelection?
    @State private var preview: ChangeOrderPreview?

    init(project: Project) { projectID = project.id }

    private var currentProject: Project? { store.projects.first { $0.id == projectID } }
    private var documents: [ProjectDocument] { store.projectDocuments.filter { $0.projectId == projectID } }

    var body: some View {
        List {
            Section {
                Text(AppLocalization.string("增项独立记录，不计入合同金额、经营汇总或结算。确认仅为本机记录，不代表甲方签章。"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AppLocalization.string("新增增项"), systemImage: "plus.circle") {
                    editing = ChangeOrderSelection(order: ProjectChangeOrder(title: ""), expected: nil)
                }
                .disabled(currentProject == nil)
                .accessibilityIdentifier("changeOrder.add")
            }
            if let project = currentProject {
                if project.changeOrders.isEmpty {
                    Text(AppLocalization.string("暂无增项记录")).foregroundStyle(.secondary)
                }
                ForEach(project.changeOrders) { order in
                    Section {
                        Button {
                            editing = ChangeOrderSelection(order: order, expected: order)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(order.title).font(.headline)
                                Text(order.confirmationState.displayName).font(.subheadline)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        LabeledContent(AppLocalization.string("申报金额"), value: amountText(order.proposedAmount))
                        if order.confirmationState == .confirmed {
                            LabeledContent(AppLocalization.string("确认金额"), value: amountText(order.confirmedAmount))
                        }
                        if order.documentIDs.contains(where: { id in !documents.contains { $0.id == id } }) {
                            Text(AppLocalization.string("部分关联资料已失效，请编辑后重新选择。"))
                                .font(.footnote).foregroundStyle(Color.appRisk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(AppLocalization.string("预览增项确认单"), systemImage: "doc.text") {
                            guard let latest = currentProject,
                                  let value = latest.changeOrders.first(where: { $0.id == order.id }) else { return }
                            preview = ChangeOrderPreview(text: ReportBuilder.changeOrderConfirmationText(
                                project: latest, order: value, documents: documents
                            ))
                        }
                        .accessibilityIdentifier("changeOrder.preview.\(order.id)")
                    }
                }
            } else {
                Text(AppLocalization.string("项目不存在")).foregroundStyle(Color.appRisk)
            }
        }
        .navigationTitle(AppLocalization.string("增项记录"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { selection in
            ProjectChangeOrderEditor(projectID: projectID, order: selection.order, expected: selection.expected)
        }
        .sheet(item: $preview) { selection in
            NavigationStack {
                ScrollView {
                    Text(selection.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle(AppLocalization.string("增项确认单"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLocalization.string("关闭")) { preview = nil }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: selection.text) {
                            Label(AppLocalization.string("分享确认单"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private func amountText(_ amount: MoneyValue) -> String {
        amount.isEmpty ? AppLocalization.string("未填写") : ReportBuilder.money(amount)
    }

    private struct ChangeOrderSelection: Identifiable {
        var id: UUID { order.id }
        let order: ProjectChangeOrder
        let expected: ProjectChangeOrder?
    }
    private struct ChangeOrderPreview: Identifiable {
        let id = UUID()
        let text: String
    }
}

private struct ProjectChangeOrderEditor: View {
    let projectID: UUID
    let expected: ProjectChangeOrder?
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var order: ProjectChangeOrder
    @State private var proposedAmount: String
    @State private var confirmedAmount: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(projectID: UUID, order: ProjectChangeOrder, expected: ProjectChangeOrder?) {
        self.projectID = projectID
        self.expected = expected
        _order = State(initialValue: order)
        _proposedAmount = State(initialValue: order.proposedAmount.wireText)
        _confirmedAmount = State(initialValue: order.confirmedAmount.wireText)
    }

    private var documents: [ProjectDocument] { store.projectDocuments.filter { $0.projectId == projectID } }
    private var missingIDs: [UUID] { order.documentIDs.filter { id in !documents.contains { $0.id == id } } }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("增项内容")) {
                    TextField(AppLocalization.string("增项标题"), text: $order.title, axis: .vertical).lineLimit(1...4)
                        .accessibilityIdentifier("changeOrder.title")
                    TextField(AppLocalization.string("增项说明"), text: $order.detail, axis: .vertical).lineLimit(3...8)
                    TextField(AppLocalization.string("提出人"), text: $order.requester, axis: .vertical).lineLimit(1...3)
                    LabeledContent(AppLocalization.string("记录日期"), value: Formatters.displayDateText(order.createdAt))
                    TextField(AppLocalization.string("申报金额"), text: $proposedAmount).keyboardType(.decimalPad)
                }
                Section {
                    Picker(AppLocalization.string("确认状态"), selection: $order.confirmationState) {
                        ForEach(ProjectChangeOrder.ConfirmationState.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    if order.confirmationState == .confirmed {
                        TextField(AppLocalization.string("确认金额"), text: $confirmedAmount).keyboardType(.decimalPad)
                        TextField(AppLocalization.string("确认记录人"), text: $order.confirmedBy, axis: .vertical).lineLimit(1...3)
                        if let date = order.confirmedAt {
                            LabeledContent(AppLocalization.string("确认记录日期"), value: Formatters.displayDateText(date))
                        } else {
                            Text(AppLocalization.string("确认记录日期将在保存时记录。"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    TextField(AppLocalization.string("确认备注"), text: $order.confirmationNote, axis: .vertical).lineLimit(2...6)
                    Text(AppLocalization.string("增项独立记录，不计入合同金额、经营汇总或结算。确认仅为本机记录，不代表甲方签章。"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: { Text(AppLocalization.string("增项确认")) }

                Section {
                    Text(AppLocalization.string("仅引用本项目已有资料；不会复制附件，也不会申请照片权限。"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(documents) { document in
                        Toggle(isOn: Binding(
                            get: { order.documentIDs.contains(document.id) },
                            set: { selected in
                                order.documentIDs.removeAll { $0 == document.id }
                                if selected { order.documentIDs.append(document.id) }
                            }
                        )) {
                            Text(document.title).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if documents.isEmpty { Text(AppLocalization.string("本项目暂无可关联资料")) }
                    ForEach(missingIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.string("关联资料已失效，请移除引用后重新选择。"))
                                .foregroundStyle(Color.appRisk)
                            Text(id.uuidString).font(.caption).foregroundStyle(.secondary)
                            Button(AppLocalization.string("移除失效引用")) { order.documentIDs.removeAll { $0 == id } }
                        }
                    }
                } header: { Text(AppLocalization.string("关联项目资料")) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appRisk) } }
            }
            .disabled(isSaving)
            .navigationTitle(AppLocalization.string("增项记录"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) { Task { await save() } }.disabled(isSaving)
                        .accessibilityIdentifier("changeOrder.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var value = order
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.proposedAmount = MoneyValue(storage: DecimalFieldStorage(text: proposedAmount))
        value.confirmedAmount = MoneyValue(storage: DecimalFieldStorage(text: confirmedAmount))
        if value.confirmationState == .confirmed {
            value.confirmedBy = value.confirmedBy.trimmingCharacters(in: .whitespacesAndNewlines)
            if expected?.confirmationState != .confirmed || value.confirmedAt == nil { value.confirmedAt = .now() }
        } else {
            value.confirmedBy = ""
            value.confirmedAt = nil
        }
        do {
            try value.validate(projectID: projectID, documents: documents)
            try await store.saveProjectChangeOrder(value, projectID: projectID, expected: expected)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
