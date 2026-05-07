import SwiftUI
import UniformTypeIdentifiers

struct ProjectContactDatabaseView: View {
    @Environment(DataStore.self) private var store
    let focusedContactId: UUID?
    @State private var searchText = ""
    @State private var selectedProjectId: UUID?
    @State private var showAdd = false
    @State private var editingContact: ProjectContact?
    @State private var didOpenFocusedContact = false
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false

    init(focusedContactId: UUID? = nil) {
        self.focusedContactId = focusedContactId
    }

    private var filteredContacts: [ProjectContact] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.projectContacts
            .filter { contact in
                guard let selectedProjectId else { return true }
                return contact.projectId == selectedProjectId
            }
            .filter { contact in
                guard !keyword.isEmpty else { return true }
                return contact.name.localizedStandardContains(keyword)
                    || contact.role.localizedStandardContains(keyword)
                    || contact.company.localizedStandardContains(keyword)
                    || contact.phone.localizedStandardContains(keyword)
                    || contact.note.localizedStandardContains(keyword)
                    || projectName(contact.projectId).localizedStandardContains(keyword)
            }
            .sorted { lhs, rhs in
                let leftProject = projectName(lhs.projectId)
                let rightProject = projectName(rhs.projectId)
                if leftProject != rightProject { return leftProject < rightProject }
                return lhs.name < rhs.name
            }
    }

    private var duplicatePhoneGroups: [(phone: String, contacts: [ProjectContact])] {
        let grouped = Dictionary(grouping: store.projectContacts) { normalizedPhone($0.phone) }
        return grouped
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map { (phone: $0.key, contacts: $0.value.sorted { projectName($0.projectId) < projectName($1.projectId) }) }
            .sorted { $0.phone < $1.phone }
    }

    var body: some View {
        List {
            Section {
                projectFilterBar
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if selectedProjectId == nil && !duplicatePhoneGroups.isEmpty {
                Section("疑似重复联系人") {
                    ForEach(duplicatePhoneGroups, id: \.phone) { group in
                        DisclosureGroup("\(group.phone) · \(group.contacts.count) 条") {
                            ForEach(group.contacts) { contact in
                                Button {
                                    editingContact = contact
                                } label: {
                                    ProjectContactDatabaseRow(contact: contact, projectName: projectName(contact.projectId))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "联系人 (\(filteredContacts.count))")) {
                if filteredContacts.isEmpty {
                    ContentUnavailableView("暂无联系人", systemImage: "person.crop.rectangle.stack", description: Text("项目联系人会统一显示在这里，可按项目筛选。"))
                } else {
                    ForEach(filteredContacts) { contact in
                        Button { editingContact = contact } label: {
                            ProjectContactDatabaseRow(contact: contact, projectName: projectName(contact.projectId))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteContact(contact)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("联系人")
        .searchable(text: $searchText, prompt: "搜索姓名、电话、公司、项目")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportContactsCSV()
                    } label: {
                        Label("导出联系人 CSV", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showAdd = true
                    } label: {
                        Label("新增联系人", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .onAppear(perform: openFocusedContactIfNeeded)
        .sheet(isPresented: $showAdd) {
            ProjectContactDatabaseEditSheet(contact: nil, projects: store.projects, initialProjectId: selectedProjectId) { contact in
                store.projectContacts.insert(contact, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingContact) { contact in
            ProjectContactDatabaseEditSheet(contact: contact, projects: store.projects, initialProjectId: contact.projectId) { updated in
                if let index = store.projectContacts.firstIndex(where: { $0.id == updated.id }) {
                    store.projectContacts[index] = updated
                    store.scheduleSave()
                }
                editingContact = nil
            } onDelete: { target in
                deleteContact(target)
                editingContact = nil
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .commaSeparatedText,
            defaultFilename: exportPayload?.defaultFilename ?? "项目联系人.csv"
        ) { _ in }
    }

    private var projectFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                contactFilterChip(title: "全部", isSelected: selectedProjectId == nil) {
                    selectedProjectId = nil
                }
                ForEach(store.projects.sorted { $0.name < $1.name }) { project in
                    contactFilterChip(title: project.name, isSelected: selectedProjectId == project.id) {
                        selectedProjectId = project.id
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func contactFilterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openFocusedContactIfNeeded() {
        guard let focusedContactId, !didOpenFocusedContact,
              let contact = store.projectContacts.first(where: { $0.id == focusedContactId }) else { return }
        didOpenFocusedContact = true
        searchText = ""
        selectedProjectId = contact.projectId
        DispatchQueue.main.async {
            editingContact = contact
        }
    }

    private func deleteContact(_ contact: ProjectContact) {
        store.projectContacts.removeAll { $0.id == contact.id }
        store.scheduleSave()
    }

    private func exportContactsCSV() {
        var rows = ["项目,姓名/单位,角色,公司/班组,电话,备注,重复手机号"]
        rows += filteredContacts.map { contact in
            let phoneKey = normalizedPhone(contact.phone)
            let duplicateMark = duplicatePhoneGroups.contains { $0.phone == phoneKey } ? "是" : ""
            return csv([projectName(contact.projectId), contact.name, contact.role, contact.company, contact.phone, contact.note, duplicateMark])
        }
        exportPayload = ExportPayload(
            data: rows.joined(separator: "\n").data(using: .utf8) ?? Data(),
            contentType: .commaSeparatedText,
            defaultFilename: "项目联系人.csv"
        )
        showExporter = true
    }

    private func projectName(_ id: UUID) -> String {
        store.projects.first(where: { $0.id == id })?.name ?? "未知项目"
    }

    private func normalizedPhone(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    private func csv(_ values: [String]) -> String {
        values
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: ",")
    }
}

private struct ProjectContactDatabaseRow: View {
    let contact: ProjectContact
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(contact.name.isEmpty ? "未命名联系人" : contact.name)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(contact.role)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            Text(projectName)
                .font(.caption)
                .foregroundStyle(.orange)
            if !contact.company.isEmpty || !contact.phone.isEmpty {
                Text([contact.company, contact.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !contact.note.isEmpty {
                Text(contact.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ProjectContactDatabaseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contact: ProjectContact?
    let projects: [Project]
    let initialProjectId: UUID?
    let onSave: (ProjectContact) -> Void
    var onDelete: ((ProjectContact) -> Void)?

    @State private var projectId: UUID?
    @State private var name: String
    @State private var role: String
    @State private var company: String
    @State private var phone: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(
        contact: ProjectContact?,
        projects: [Project],
        initialProjectId: UUID?,
        onSave: @escaping (ProjectContact) -> Void,
        onDelete: ((ProjectContact) -> Void)? = nil
    ) {
        self.contact = contact
        self.projects = projects
        self.initialProjectId = initialProjectId
        self.onSave = onSave
        self.onDelete = onDelete
        _projectId = State(initialValue: contact?.projectId ?? initialProjectId ?? projects.first?.id)
        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? ProjectContactRole.owner.rawValue)
        _company = State(initialValue: contact?.company ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _note = State(initialValue: contact?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("归属项目") {
                    Picker("项目", selection: $projectId) {
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section("联系人") {
                    TextField("姓名/单位", text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField("公司/班组", text: $company)
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if contact != nil {
                    Section {
                        Button("删除联系人", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(contact == nil ? "新增联系人" : "编辑联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedContact)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("删除这个联系人？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let contact { onDelete?(contact) }
                    dismiss()
                }
            }
        }
    }

    private var canSave: Bool {
        projectId != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var updatedContact: ProjectContact {
        let targetProjectId = projectId ?? initialProjectId ?? projects.first?.id ?? UUID()
        var value = contact ?? ProjectContact(projectId: targetProjectId, name: "")
        value.projectId = targetProjectId
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.role = normalizedRole
        value.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var normalizedRole: String {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProjectContactRole.other.rawValue : trimmed
    }
}
