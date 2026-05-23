import SwiftUI

struct ProjectContactDatabaseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contact: ProjectContact?
    let projects: [Project]
    let initialProjectId: UUID?
    let onSave: (ProjectContact) -> Void
    var onDelete: ((ProjectContact) -> Void)?

    @State private var projectId: UUID?
    @State private var relatedProjectIDs: Set<UUID>
    @State private var name: String
    @State private var role: ProjectContactRole
    @State private var company: String
    @State private var phone: String
    @State private var note: String
    @State private var showDeleteConfirm = false
    @State private var showSystemContactPicker = false

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
        _relatedProjectIDs = State(initialValue: Set(contact?.relatedProjectIds ?? []))
        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? .owner)
        _company = State(initialValue: contact?.company ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _note = State(initialValue: contact?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "项目"), selection: $projectId) {
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    ProjectTagMultiSelectView(
                        projects: projects,
                        primaryProjectId: projectId,
                        selectedProjectIDs: $relatedProjectIDs
                    )
                }
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
                if contact != nil {
                    Section {
                        Button(String(localized: "删除联系人"), role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(contact == nil ? String(localized: "新增联系人") : String(localized: "编辑联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        onSave(updatedContact)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(String(localized: "删除这个联系人？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    if let contact { onDelete?(contact) }
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

    private var canSave: Bool {
        projectId != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var updatedContact: ProjectContact {
        let targetProjectId = projectId ?? initialProjectId ?? projects.first?.id ?? UUID()
        var value = contact ?? ProjectContact(projectId: targetProjectId, name: "")
        value.projectId = targetProjectId
        value.relatedProjectIds = Array(relatedProjectIDs.filter { $0 != targetProjectId })
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.role = role
        value.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
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
