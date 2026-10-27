import SwiftUI

struct RepositoryContactEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<RepositoryContactDraft>

    init(session: RepositoryWorkspaceSession, projectID: UUID, id: UUID?) {
        self.session = session
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .projectContacts, id: id,
            initial: RepositoryContactDraft(record: ProjectContact(projectId: projectID, name: ""))))
    }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("往来单位"),
            canSave: (try? editor.draft.command()) != nil, command: { try $0.command() }) {
            Section {
                TextField(AppLocalization.string("姓名"), text: $editor.draft.record.name).accessibilityIdentifier("repository-contact-name")
                Picker(AppLocalization.string("角色"), selection: $editor.draft.record.role) {
                    ForEach(ProjectContactRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("repository-contact-role")
                TextField(AppLocalization.string("单位"), text: $editor.draft.record.company).accessibilityIdentifier("repository-contact-company")
                TextField(AppLocalization.string("电话"), text: $editor.draft.record.phone).accessibilityIdentifier("repository-contact-phone")
                TextField(AppLocalization.string("备注"), text: $editor.draft.record.note, axis: .vertical).accessibilityIdentifier("repository-contact-note")
            }
            Section {
                Text(String(format: AppLocalization.string("保留主项目及 %lld 个其他项目关联"), Int64(editor.draft.record.relatedProjectIds.count)))
                    .font(.caption).foregroundStyle(.secondary)
                Text(AppLocalization.string("仅保存此副本中的往来单位，不修改系统通讯录。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
