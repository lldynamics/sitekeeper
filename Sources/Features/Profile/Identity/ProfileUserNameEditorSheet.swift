import SwiftUI

struct ProfileUserNameEditorSheet: View {
    @Binding var userNameDraft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("用户名")) {
                    TextField(AppLocalization.string("请输入用户名"), text: $userNameDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("profile-username-input")
                    Text(AppLocalization.string("留空将显示“未设置用户名”。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(AppLocalization.string("编辑用户名"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        onSave()
                    }
                    .accessibilityIdentifier("profile-username-save")
                }
            }
        }
    }
}
