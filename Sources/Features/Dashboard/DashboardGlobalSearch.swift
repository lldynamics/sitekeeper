import SwiftUI

struct DashboardGlobalSearch: View {
    @Binding var text: String
    @Binding var projectID: UUID?
    @Binding var category: RealtimeSearchSuggestion.Category?
    let projects: [Project]
    let suggestions: [RealtimeSearchSuggestion]
    let onSelect: (RealtimeSearchSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    projectPicker
                    categoryPicker
                }
                VStack(alignment: .leading) {
                    projectPicker
                    categoryPicker
                }
            }
            InlineSearchPanel(
                text: $text,
                prompt: AppLocalization.string("搜索项目、票号、报价、图纸或资料"),
                suggestions: suggestions,
                emptyStateText: AppLocalization.string("未找到匹配的业务记录或命令"),
                materialTone: .materialThin,
                onSelectSuggestion: { suggestion in
                    text = ""
                    onSelect(suggestion)
                }
            )
        }
    }

    private var projectPicker: some View {
        Picker(AppLocalization.string("项目"), selection: $projectID) {
            Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
            ForEach(projects) { Text($0.name).tag($0.id as UUID?) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("dashboard-search-project-filter")
    }

    private var categoryPicker: some View {
        Picker(AppLocalization.string("类型"), selection: $category) {
            Text(AppLocalization.string("全部类型")).tag(nil as RealtimeSearchSuggestion.Category?)
            ForEach(RealtimeSearchSuggestion.Category.allCases, id: \.self) {
                Text($0.displayName).tag($0 as RealtimeSearchSuggestion.Category?)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("dashboard-search-category-filter")
    }
}
