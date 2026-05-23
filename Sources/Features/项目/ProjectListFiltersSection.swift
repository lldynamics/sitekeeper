import SwiftUI

struct ProjectListFiltersSection: View {
    @Binding var searchText: String
    @Binding var statusFilter: ProjectStatus?
    @Binding var sortOption: ProjectSortOption
    @Binding var overviewFilter: ProjectOverviewFilter?
    let allowedStatuses: [ProjectStatus]
    let searchSuggestions: [RealtimeSearchSuggestion]
    let hasAnyFilterApplied: Bool
    let onSelectSuggestion: (RealtimeSearchSuggestion) -> Void
    let onClearAll: () -> Void

    var body: some View {
        Section {
            InlineSearchPanel(
                text: $searchText,
                prompt: String(localized: "搜索项目名称或地点"),
                suggestions: searchSuggestions,
                emptyStateText: String(localized: "未找到匹配的项目、地点或客户"),
                materialTone: .secondary,
                onSelectSuggestion: onSelectSuggestion
            )

            compactToolbar

            if overviewFilter != nil {
                HStack(spacing: AppSpacing.tight) {
                    if let overviewFilter {
                        Label(
                            String(
                                format: String(localized: "概况筛选：%@"),
                                overviewFilter.displayName
                            ),
                            systemImage: "scope"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("project-list-overview-filter-\(overviewFilter.rawValue)")
                    }
                    Spacer(minLength: 0)
                    Button {
                        overviewFilter = nil
                    } label: {
                        Label(String(localized: "清除概况筛选"), systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityIdentifier("project-list-overview-filter-clear")
                }
            }
        } header: {
            Text(String(localized: "搜索与筛选"))
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    FilterChip(title: String(localized: "全部"), isSelected: statusFilter == nil) {
                        statusFilter = nil
                    }
                    ForEach(allowedStatuses, id: \.rawValue) { status in
                        FilterChip(title: status.displayName, isSelected: statusFilter == status) {
                            statusFilter = status
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: AppSpacing.tight) {
                Picker(String(localized: "排序"), selection: $sortOption) {
                    ForEach(ProjectSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 0)

                if hasAnyFilterApplied {
                    Button(String(localized: "清除筛选"), action: onClearAll)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                }
            }
        }
    }
}
