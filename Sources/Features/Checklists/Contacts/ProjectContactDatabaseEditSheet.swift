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
                Section(AppLocalization.string("归属项目")) {
                    Picker(AppLocalization.string("项目"), selection: $projectId) {
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
                Section(AppLocalization.string("联系人")) {
                    Button {
                        showSystemContactPicker = true
                    } label: {
                        Label(AppLocalization.string("从通讯录导入"), systemImage: "person.badge.plus")
                    }
                    TextField(AppLocalization.string("姓名/单位"), text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField(AppLocalization.string("公司/班组"), text: $company)
                    TextField(AppLocalization.string("电话"), text: $phone)
                        .keyboardType(.phonePad)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if contact != nil {
                    Section {
                        Button(AppLocalization.string("删除联系人"), role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(contact == nil ? AppLocalization.string("新增联系人") : AppLocalization.string("编辑联系人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        onSave(updatedContact)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(AppLocalization.string("删除这个联系人？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
                Button(AppLocalization.string("删除"), role: .destructive) {
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
        let marker = String(format: AppLocalization.string("备用号码：%@"), spareText)
        if note.contains(marker) { return }
        note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        note = note.isEmpty ? marker : "\(note)\n\(marker)"
    }
}
