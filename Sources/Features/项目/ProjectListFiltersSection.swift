import SwiftUI

struct ProjectListFiltersSection: View {
    @Binding var searchText: String
    @Binding var statusFilter: ProjectStatus?
    @Binding var sortOption: ProjectSortOption
    @Binding var overviewFilter: ProjectOverviewFilter?
    let hasAnyFilterApplied: Bool
    let isSplitNavigation: Bool
    let onClearAll: () -> Void

    var body: some View {
        Section {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("搜索项目名称或地点", text: $searchText)
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

            if isSplitNavigation {
                splitToolbar
            } else {
                compactToolbar
            }

            if overviewFilter != nil {
                Button {
                    overviewFilter = nil
                } label: {
                    Label("清除概况筛选", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }
        } header: {
            Text("搜索与筛选")
        }
    }

    private var splitToolbar: some View {
        HStack(spacing: AppSpacing.tight) {
            Menu {
                Button("全部状态") { statusFilter = nil }
                ForEach(ProjectStatus.allCases, id: \.rawValue) { status in
                    Button(status.displayName) {
                        statusFilter = status
                    }
                }
            } label: {
                Label(statusFilter?.displayName ?? "全部状态", systemImage: "line.3.horizontal.decrease.circle")
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
                    Label("清除", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var compactToolbar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    FilterChip(title: "全部", isSelected: statusFilter == nil) {
                        statusFilter = nil
                    }
                    ForEach(ProjectStatus.allCases, id: \.rawValue) { status in
                        FilterChip(title: status.displayName, isSelected: statusFilter == status) {
                            statusFilter = status
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: AppSpacing.tight) {
                Picker("排序", selection: $sortOption) {
                    ForEach(ProjectSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 0)

                if hasAnyFilterApplied {
                    Button("清除筛选", action: onClearAll)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
