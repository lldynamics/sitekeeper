import SwiftUI

struct ProjectContactRoleField: View {
    @Binding var role: String

    private var commonRoleBinding: Binding<String> {
        Binding(
            get: {
                let trimmed = role.trimmingCharacters(in: .whitespacesAndNewlines)
                return Self.commonRoles.contains(trimmed) ? trimmed : Self.customRoleToken
            },
            set: { value in
                guard value != Self.customRoleToken else { return }
                role = value
            }
        )
    }

    var body: some View {
        Picker("常用角色", selection: commonRoleBinding) {
            ForEach(Self.commonRoles, id: \.self) { item in
                Text(item).tag(item)
            }
            Text("自定义").tag(Self.customRoleToken)
        }
        TextField("自定义角色，例如：设计师、采购、物业", text: $role)
    }

    private static let customRoleToken = "__custom_project_contact_role__"
    private static var commonRoles: [String] {
        ProjectContactRole.allCases.map(\.rawValue)
    }
}
