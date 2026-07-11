import SwiftUI

extension DailyLogView {
    @ToolbarContentBuilder
    var logToolbar: some ToolbarContent {
        if !usesSplitLogLayout {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(String(localized: "项目"), selection: $filterProjectId) {
                        Text(String(localized: "全部项目")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    Button {
                        showDateFilter = true
                    } label: {
                        Label(isDateFilterActive ? String(localized: "调整日期筛选") : String(localized: "日期筛选"), systemImage: "calendar")
                    }
                    if filterProjectId != nil || isDateFilterActive {
                        Button(String(localized: "清除筛选")) {
                            filterProjectId = nil
                            isDateFilterActive = false
                        }
                    }
                } label: {
                    Image(systemName: filterProjectId != nil || isDateFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "筛选与排序"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "新建施工日志"))
            }
        }
    }

    var dateFilterSheet: some View {
        AppBusinessFormSheet(
            title: String(localized: "日期筛选"),
            cancelTitle: String(localized: "清除"),
            primaryActionTitle: String(localized: "确定"),
            onCancel: {
                isDateFilterActive = false
                showDateFilter = false
            },
            onPrimaryAction: {
                isDateFilterActive = true
                showDateFilter = false
            }
        ) {
            DatePicker(String(localized: "开始"), selection: $filterStart, displayedComponents: .date)
            DatePicker(String(localized: "结束"), selection: $filterEnd, displayedComponents: .date)
            Toggle(String(localized: "启用日期筛选"), isOn: $isDateFilterActive)
        }
        .presentationDetents([.medium])
    }
}
