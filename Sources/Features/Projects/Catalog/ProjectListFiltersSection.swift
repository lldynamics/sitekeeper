import SwiftUI

struct ProjectListFiltersSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                prompt: AppLocalization.string("搜索项目名称或地点"),
                suggestions: searchSuggestions,
                emptyStateText: AppLocalization.string("未找到匹配的项目、地点或客户"),
                materialTone: .secondary,
                onSelectSuggestion: onSelectSuggestion
            )

            compactToolbar

            if overviewFilter != nil {
                HStack(spacing: AppSpacing.tight) {
                    if let overviewFilter {
                        Label(
                            String(
                                format: AppLocalization.string("概况筛选：%@"),
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
                        Label(AppLocalization.string("清除概况筛选"), systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityIdentifier("project-list-overview-filter-clear")
                }
            }
        } header: {
            Text(AppLocalization.string("搜索与筛选"))
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    Button(AppLocalization.string("全部")) {
                        statusFilter = nil
                    }
                    ForEach(allowedStatuses, id: \.rawValue) { status in
                        Button(status.displayName) {
                            statusFilter = status
                        }
                    }
                } label: {
                    accessibilityMenuLabel(
                        title: AppLocalization.string("状态筛选"),
                        value: selectedStatusTitle
                    )
                }
                .buttonStyle(ProjectFilterAccessibilityMenuStyle())
                .accessibilityLabel(AppLocalization.string("状态筛选"))
                .accessibilityValue(selectedStatusTitle)
                .accessibilityIdentifier("project-status-filter-menu")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        FilterChip(title: AppLocalization.string("全部"), isSelected: statusFilter == nil) {
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
            }

            if dynamicTypeSize.isAccessibilitySize {
                Divider()

                Menu {
                    ForEach(ProjectSortOption.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            sortOption = option
                        }
                    }
                } label: {
                    accessibilityMenuLabel(
                        title: AppLocalization.string("排序"),
                        value: sortOption.displayName,
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .buttonStyle(ProjectFilterAccessibilityMenuStyle())
                .accessibilityLabel(AppLocalization.string("排序"))
                .accessibilityValue(sortOption.displayName)
                .accessibilityIdentifier("project-sort-menu")

                if hasAnyFilterApplied {
                    Button(AppLocalization.string("清除筛选"), action: onClearAll)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.vertical, AppSpacing.tight)
                }
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Picker(AppLocalization.string("排序"), selection: $sortOption) {
                        ForEach(ProjectSortOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer(minLength: 0)

                    if hasAnyFilterApplied {
                        Button(AppLocalization.string("清除筛选"), action: onClearAll)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.appPrimaryAction)
                    }
                }
            }
        }
    }

    private func accessibilityMenuLabel(
        title: String,
        value: String,
        systemImage: String = "chevron.up.chevron.down"
    ) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.tight) {
            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.25) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppSpacing.tight)

            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appPrimaryAction)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var selectedStatusTitle: String {
        statusFilter?.displayName ?? AppLocalization.string("全部")
    }
}

private struct ProjectFilterAccessibilityMenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, AppSpacing.normal)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
