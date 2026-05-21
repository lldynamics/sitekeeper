import SwiftUI

struct ProjectContactRoleField: View {
    @Binding var role: ProjectContactRole

    var body: some View {
        Picker(String(localized: "角色"), selection: $role) {
            ForEach(ProjectContactRole.allCases, id: \.self) { item in
                Text(item.displayName).tag(item)
            }
        }
    }
}
