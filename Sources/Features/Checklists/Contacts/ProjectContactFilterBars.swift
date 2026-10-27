import SwiftUI

struct ProjectContactFilterBars: View {
    let projects: [Project]
    @Binding var selectedProjectId: UUID?
    @Binding var roleFilter: ProjectContactRole?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            // 项目筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    contactFilterChip(title: AppLocalization.string("全部项目"), isSelected: selectedProjectId == nil && roleFilter == nil, isColored: false) {
                        selectedProjectId = nil
                        roleFilter = nil
                    }
                    ForEach(projects.sorted { $0.name < $1.name }) { project in
                        contactFilterChip(title: project.name, isSelected: selectedProjectId == project.id, isColored: true) {
                            selectedProjectId = project.id
                            roleFilter = nil
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            // 角色筛选
            if selectedProjectId == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        contactFilterChip(title: AppLocalization.string("全部"), isSelected: roleFilter == nil, isColored: false) {
                            roleFilter = nil
                        }
                        ForEach(ProjectContactRole.allCases, id: \.rawValue) { role in
                            contactFilterChip(title: role.displayName, isSelected: roleFilter == role, isColored: true) {
                                roleFilter = role
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func contactFilterChip(title: String, isSelected: Bool, isColored: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.appPrimaryAction : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
