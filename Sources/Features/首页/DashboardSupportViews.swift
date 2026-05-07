import SwiftUI

struct TodayPrimaryQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let destination: AnyView
}

struct TodayMiniAction: View {
    let title: String
    let systemImage: String
    let color: Color
    let destination: AnyView
    var quickActions: [TodayPrimaryQuickAction] = []

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("打开\(title)功能")
        .contextMenu {
            ForEach(quickActions) { action in
                NavigationLink {
                    action.destination
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
    }
}

struct BookkeepingProjectPickerView: View {
    let projects: [Project]

    var body: some View {
        List {
            if projects.isEmpty {
                ContentUnavailableView("暂无进行中工程", systemImage: "building.2")
            } else {
                Section("选择工程后直接进入项目记账") {
                    ForEach(projects) { project in
                        NavigationLink {
                            ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .font(.body.weight(.semibold))
                                HStack(spacing: 8) {
                                    Text(project.status)
                                    if !project.location.isEmpty {
                                        Text(project.location)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择记账工程")
        .navigationBarTitleDisplayMode(.inline)
    }
}
