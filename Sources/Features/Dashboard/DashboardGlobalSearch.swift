import SwiftUI

struct DashboardGlobalSearch: View {
    @Binding var text: String
    @Binding var projectID: UUID?
    @Binding var category: RealtimeSearchSuggestion.Category?
    let projects: [Project]
    let suggestions: [RealtimeSearchSuggestion]
    let onSelect: (RealtimeSearchSuggestion) -> Void

    private var currentProjectName: String {
        if let projectID, let project = projects.first(where: { $0.id == projectID }) {
            return project.name
        }
        return AppLocalization.string("全部项目")
    }

    private var currentCategoryName: String {
        category?.displayName ?? AppLocalization.string("全部类型")
    }

    var body: some View {
        InlineSearchPanel(
            text: $text,
            prompt: AppLocalization.string("搜索项目、票号、报价、图纸或资料"),
            suggestions: suggestions,
            emptyStateText: AppLocalization.string("未找到匹配的业务记录或命令"),
            materialTone: .grouped,
            trailingContent: {
                searchFilterControls
            },
            onSelectSuggestion: { suggestion in
                text = ""
                onSelect(suggestion)
            }
        )
    }

    @ViewBuilder
    private var searchFilterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.tight * 0.75) {
                projectFilterMenu
                categoryFilterMenu
            }
            combinedCompactFilterMenu
        }
    }

    private var projectFilterMenu: some View {
        Menu {
            Button {
                projectID = nil
            } label: {
                HStack {
                    Text(AppLocalization.string("全部项目"))
                    if projectID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(projects) { project in
                Button {
                    projectID = project.id
                } label: {
                    HStack {
                        Text(project.name)
                        if projectID == project.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "building.2")
                    .font(.caption2)
                Text(currentProjectName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(projectID != nil ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
            )
            .overlay(
                Capsule()
                    .stroke(projectID != nil ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
            .foregroundStyle(projectID != nil ? Color.accentColor : Color.secondary)
        }
        .accessibilityIdentifier("dashboard-search-project-filter")
    }

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                category = nil
            } label: {
                HStack {
                    Text(AppLocalization.string("全部类型"))
                    if category == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(RealtimeSearchSuggestion.Category.allCases, id: \.self) { cat in
                Button {
                    category = cat
                } label: {
                    HStack {
                        Text(cat.displayName)
                        if category == cat {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.caption2)
                Text(currentCategoryName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(category != nil ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
            )
            .overlay(
                Capsule()
                    .stroke(category != nil ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
            .foregroundStyle(category != nil ? Color.accentColor : Color.secondary)
        }
        .accessibilityIdentifier("dashboard-search-category-filter")
    }

    private var combinedCompactFilterMenu: some View {
        Menu {
            Menu(AppLocalization.string("项目: ") + currentProjectName) {
                Button(AppLocalization.string("全部项目")) { projectID = nil }
                ForEach(projects) { project in
                    Button(project.name) { projectID = project.id }
                }
            }
            Menu(AppLocalization.string("类型: ") + currentCategoryName) {
                Button(AppLocalization.string("全部类型")) { category = nil }
                ForEach(RealtimeSearchSuggestion.Category.allCases, id: \.self) { cat in
                    Button(cat.displayName) { category = cat }
                }
            }
            if projectID != nil || category != nil {
                Divider()
                Button(role: .destructive) {
                    projectID = nil
                    category = nil
                } label: {
                    Label(AppLocalization.string("重置筛选"), systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: (projectID != nil || category != nil) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.body)
                if projectID != nil || category != nil {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle((projectID != nil || category != nil) ? Color.accentColor : Color.secondary)
            .padding(4)
        }
        .accessibilityIdentifier("dashboard-search-combined-filter")
    }
}
