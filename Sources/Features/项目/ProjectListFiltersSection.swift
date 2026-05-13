import SwiftUI

struct ProjectListFiltersSection: View {
    @Binding var searchText: String
    @Binding var statusFilter: ProjectStatus?
    @Binding var sortOption: ProjectSortOption
    @Binding var overviewFilter: ProjectOverviewFilter?
    let allowedStatuses: [ProjectStatus]
    let searchSuggestions: [RealtimeSearchSuggestion]
    let hasAnyFilterApplied: Bool
    let isSplitNavigation: Bool
    let onSelectSuggestion: (RealtimeSearchSuggestion) -> Void
    let onClearAll: () -> Void

    var body: some View {
        Section {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "搜索项目名称或地点"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !searchSuggestions.isEmpty {
                RealtimeSearchSuggestionInlineList(
                    suggestions: searchSuggestions,
                    onSelect: onSelectSuggestion
                )
                .padding(.top, 2)
            }

            if isSplitNavigation {
                splitToolbar
            } else {
                compactToolbar
            }

            if overviewFilter != nil {
                HStack(spacing: AppSpacing.tight) {
                    if let overviewFilter {
                        Label(String(localized: "概况筛选：\(overviewFilter.displayName)"), systemImage: "scope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        overviewFilter = nil
                    } label: {
                        Label(String(localized: "清除概况筛选"), systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        } header: {
            Text(String(localized: "搜索与筛选"))
        }
    }

    private var splitToolbar: some View {
        HStack(spacing: AppSpacing.tight) {
            Menu {
                Button(String(localized: "全部状态")) { statusFilter = nil }
                ForEach(allowedStatuses, id: \.rawValue) { status in
                    Button(status.displayName) {
                        statusFilter = status
                    }
                }
            } label: {
                Label(statusFilter?.displayName ?? String(localized: "全部状态"), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppSpacing.normal)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }

            Menu {
                ForEach(ProjectSortOption.allCases, id: \.self) { option in
                    Button(option.displayName) {
                        sortOption = option
                    }
                }
            } label: {
                Label(sortOption.displayName, systemImage: "arrow.up.arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, AppSpacing.normal)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }

            Spacer(minLength: 0)

            if hasAnyFilterApplied {
                Button(action: onClearAll) {
                    Label(String(localized: "清除"), systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }
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
