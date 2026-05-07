import SwiftUI

struct ProjectContactAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let onSave: (ProjectContact) -> Void

    @State private var name = ""
    @State private var role = ProjectContactRole.owner.rawValue
    @State private var company = ""
    @State private var phone = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("联系人") {
                    TextField("姓名/单位", text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField("公司/班组", text: $company)
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("添加联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(ProjectContact(
                            projectId: projectId,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            role: normalizedRole,
                            company: company,
                            phone: phone,
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var normalizedRole: String {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProjectContactRole.other.rawValue : trimmed
    }
}

struct ProjectContactEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let contact: ProjectContact
    let onSave: (ProjectContact) -> Void
    let onDelete: (ProjectContact) -> Void

    @State private var name: String
    @State private var role: String
    @State private var company: String
    @State private var phone: String
    @State private var note: String
    @State private var showDeleteConfirm = false

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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("联系人") {
                    TextField("姓名/单位", text: $name)
                    ProjectContactRoleField(role: $role)
                    TextField("公司/班组", text: $company)
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button("删除联系人", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("编辑联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = contact
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.role = normalizedRole
                        updated.company = company.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这个联系人？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    onDelete(contact)
                    dismiss()
                }
            }
        }
    }

    private var normalizedRole: String {
        let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProjectContactRole.other.rawValue : trimmed
    }
}
