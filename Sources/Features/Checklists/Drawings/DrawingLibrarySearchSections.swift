import SwiftUI

struct DrawingLibrarySearchSections: View {
    let projects: [Project]
    let listModel: DrawingListViewModel
    @Binding var selectedProjectID: UUID?
    @Binding var searchText: String
    @Binding var availabilityFilter: DrawingAvailabilityFilter
    let suggestions: [RealtimeSearchSuggestion]
    let onSelectSuggestion: (RealtimeSearchSuggestion) -> Void
    let onScan: () -> Void

    var body: some View {
        Section(AppLocalization.string("项目筛选")) {
            Picker(AppLocalization.string("查看范围"), selection: $selectedProjectID) {
                Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
        }

        Section(AppLocalization.string("图纸能力边界")) {
            InlineNotice(
                title: AppLocalization.string("图纸台账 + 外部打开"),
                message: AppLocalization.string("App 管理 DWG / DXF / PDF 原件、版本、当前版和交付导出；DWG/DXF 原件通过外部专业看图软件打开，PDF 使用系统预览。"),
                tone: .info
            )
        }

        Section(AppLocalization.string("快速查找")) {
            InlineSearchPanel(
                text: $searchText,
                prompt: AppLocalization.string("搜索名称、图号、专业、楼层、项目"),
                suggestions: suggestions,
                emptyStateText: AppLocalization.string("未找到匹配图纸")
            ) { suggestion in
                onSelectSuggestion(suggestion)
            }
            if !listModel.normalizedSearchText.isEmpty {
                Text(String(format: AppLocalization.string("匹配 %lld 张图纸"), Int64(listModel.filteredDrawings.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section(AppLocalization.string("状态筛选")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DrawingAvailabilityFilter.allCases) { filter in
                        DrawingAvailabilityFilterChip(
                            filter: filter,
                            count: listModel.count(for: filter),
                            isSelected: availabilityFilter == filter
                        ) {
                            availabilityFilter = filter
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let summary = listModel.filteredResultSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                onScan()
            } label: {
                Label(AppLocalization.string("扫描原件状态"), systemImage: "checkmark.folder.fill")
            }
        }
    }
}
