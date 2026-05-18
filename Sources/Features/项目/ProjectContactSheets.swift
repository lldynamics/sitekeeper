import SwiftUI

struct ProjectContactAddSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let onSave: (ProjectContact) -> Void

    @State private var name = ""
    @State private var role: ProjectContactRole = .owner
    @State private var company = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var relatedProjectIDs: Set<UUID> = []
    @State private var showSystemContactPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "联系人")) {
                    Button {
                        showSystemContactPicker = true
                    } label: {
                        Label(String(localized: "从通讯录导入"), systemImage: "person.badge.plus")
                    }
                    TextField(String(localized: "姓名/单位"), text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField(String(localized: "公司/班组"), text: $company)
                    TextField(String(localized: "电话"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "历史项目（可多选）")) {
                    ProjectTagMultiSelectView(
                        projects: store.projects,
                        primaryProjectId: projectId,
                        selectedProjectIDs: $relatedProjectIDs
                    )
                }
            }
            .navigationTitle(String(localized: "添加联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        onSave(ProjectContact(
                            projectId: projectId,
                            relatedProjectIds: Array(relatedProjectIDs),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            role: role,
                            company: company,
                            phone: phone,
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showSystemContactPicker) {
                SystemContactPicker(
                    onSelect: { imported in
                        applyImportedContact(imported)
                    },
                    onCancel: {}
                )
            }
        }
    }

    private func applyImportedContact(_ imported: ImportedSystemContact) {
        showSystemContactPicker = false
        if !imported.fullName.isEmpty { name = imported.fullName }
        if !imported.organizationName.isEmpty { company = imported.organizationName }
        if !imported.primaryPhone.isEmpty { phone = imported.primaryPhone }
        appendSparePhones(imported)
    }

    private func appendSparePhones(_ imported: ImportedSystemContact) {
        guard imported.phoneNumbers.count > 1 else { return }
        let spareText = imported.phoneNumbers.dropFirst().joined(separator: "、")
        guard !spareText.isEmpty else { return }
        let marker = String(format: String(localized: "备用号码：%@"), spareText)
        if note.contains(marker) { return }
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.isEmpty ? marker : "\(note)\n\(marker)"
    }
}

struct ProjectContactEditSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contact: ProjectContact
    let onSave: (ProjectContact) -> Void
    let onDelete: (ProjectContact) -> Void

    @State private var name: String
    @State private var role: ProjectContactRole
    @State private var company: String
    @State private var phone: String
    @State private var note: String
    @State private var relatedProjectIDs: Set<UUID>
    @State private var showDeleteConfirm = false
    @State private var showSystemContactPicker = false

    init(
        contact: ProjectContact,
        onSave: @escaping (ProjectContact) -> Void,
        onDelete: @escaping (ProjectContact) -> Void
    ) {
        self.contact = contact
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: contact.name)
        _role = State(initialValue: contact.role)
        _company = State(initialValue: contact.company)
        _phone = State(initialValue: contact.phone)
        _note = State(initialValue: contact.note)
        _relatedProjectIDs = State(initialValue: Set(contact.relatedProjectIds))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "联系人")) {
                    Button {
                        showSystemContactPicker = true
                    } label: {
                        Label(String(localized: "从通讯录导入"), systemImage: "person.badge.plus")
                    }
                    TextField(String(localized: "姓名/单位"), text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField(String(localized: "公司/班组"), text: $company)
                    TextField(String(localized: "电话"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "历史项目（可多选）")) {
                    ProjectTagMultiSelectView(
                        projects: store.projects,
                        primaryProjectId: contact.projectId,
                        selectedProjectIDs: $relatedProjectIDs
                    )
                }
                Section {
                    Button(String(localized: "删除联系人"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "编辑联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        var updated = contact
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.role = role
                        updated.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.relatedProjectIds = Array(relatedProjectIDs.filter { $0 != contact.projectId })
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(String(localized: "删除这个联系人？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete(contact)
                    dismiss()
                }
            }
            .sheet(isPresented: $showSystemContactPicker) {
                SystemContactPicker(
                    onSelect: { imported in
                        applyImportedContact(imported)
                    },
                    onCancel: {}
                )
            }
        }
    }

    private func applyImportedContact(_ imported: ImportedSystemContact) {
        showSystemContactPicker = false
        if !imported.fullName.isEmpty { name = imported.fullName }
        if !imported.organizationName.isEmpty { company = imported.organizationName }
        if !imported.primaryPhone.isEmpty { phone = imported.primaryPhone }
        appendSparePhones(imported)
    }

    private func appendSparePhones(_ imported: ImportedSystemContact) {
        guard imported.phoneNumbers.count > 1 else { return }
        let spareText = imported.phoneNumbers.dropFirst().joined(separator: "、")
        guard !spareText.isEmpty else { return }
        let marker = String(format: String(localized: "备用号码：%@"), spareText)
        if note.contains(marker) { return }
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.isEmpty ? marker : "\(note)\n\(marker)"
    }
}

struct ProjectTagMultiSelectView: View {
    let projects: [Project]
    let primaryProjectId: UUID?
    @Binding var selectedProjectIDs: Set<UUID>

    private var selectableProjects: [Project] {
        projects
            .filter { project in
                guard let primaryProjectId else { return true }
                return project.id != primaryProjectId
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        if selectableProjects.isEmpty {
            Text(String(localized: "暂无可选项目"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(selectableProjects) { project in
                    let isSelected = selectedProjectIDs.contains(project.id)
                    Button {
                        toggle(project.id)
                    } label: {
                        Text(project.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggle(_ projectID: UUID) {
        if selectedProjectIDs.contains(projectID) {
            selectedProjectIDs.remove(projectID)
        } else {
            selectedProjectIDs.insert(projectID)
        }
    }
}
