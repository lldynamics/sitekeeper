import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    var compactLogLayout: some View {
        List {
            searchPanelSection
            modePickerSection
            logDetailContent
        }
    }

    var splitLogLayout: some View {
        NavigationSplitView {
            List {
                searchPanelSection
                modePickerSection
                splitFilterSection
                Section(AppLocalization.string("快捷操作")) {
                    Button {
                        showAdd = true
                    } label: {
                        Label(AppLocalization.string("新建施工日志"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            }
            .navigationTitle(AppLocalization.string("日志筛选"))
        } detail: {
            List {
                logDetailContent
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    var searchPanelSection: some View {
        Section(AppLocalization.string("快速查找")) {
            InlineSearchPanel(
                text: $searchText,
                prompt: AppLocalization.string("按日期、内容、安全事项搜索"),
                suggestions: dailyLogSearchSuggestions,
                emptyStateText: AppLocalization.string("未找到匹配日志")
            ) { suggestion in
                searchText = suggestion.title
                viewMode = .list
            }
        }
    }

    var modePickerSection: some View {
        Section {
            Picker(AppLocalization.string("视图"), selection: $viewMode) {
                ForEach(DailyLogMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    var splitFilterSection: some View {
        Section(AppLocalization.string("筛选")) {
            Picker(AppLocalization.string("项目"), selection: $filterProjectId) {
                Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
                ForEach(store.projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            Button {
                showDateFilter = true
            } label: {
                Label(isDateFilterActive ? AppLocalization.string("调整日期筛选") : AppLocalization.string("日期筛选"), systemImage: "calendar")
            }
            if filterProjectId != nil || isDateFilterActive {
                Button(AppLocalization.string("清除筛选")) {
                    filterProjectId = nil
                    isDateFilterActive = false
                }
            }
        }
    }

    @ViewBuilder
    var logDetailContent: some View {
        if filtered.isEmpty {
            ContentUnavailableView(
                AppLocalization.string("暂无施工日志"),
                systemImage: "book.pages",
                description: Text(AppLocalization.string("添加日志后可按项目、日期、内容和安全事项检索"))
            )
        } else if viewMode == .list {
            ForEach(filtered) { log in
                DailyLogEntryRow(
                    log: log,
                    projectName: log.projectId.flatMap { projectId in
                        store.projects.first(where: { $0.id == projectId })?.name
                    },
                    linkedMethodTitles: linkedMethodTitles(for: log.linkedConstructionMethodIDs),
                    onOpenPhoto: { selectedPhotoContext = $0 }
                )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(AppLocalization.string("复制")) { copyLogToToday(log) }
                            .tint(Color.appDoc)
                        Button(AppLocalization.string("编辑")) { startEdit(log) }
                            .tint(Color.appPrimaryAction)
                    }
            }
            .onDelete(perform: deleteLogs)
        } else if viewMode == .calendar {
            calendarContent
        } else {
            photoWallContent
        }
    }

    var calendarContent: some View {
        let calendarIndex = DailyLogCalendarIndex(logs: filtered)
        let selectedDateLogs = calendarIndex.logs(on: selectedCalendarDate)

        return Group {
            Section {
                VStack(spacing: AppSpacing.normal) {
                    HStack {
                        Button {
                            moveMonth(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(AppLocalization.string("上个月"))
                        .accessibilityHint(AppLocalization.string("查看上个月日志"))
                        Spacer()
                        Button {
                            jumpToToday()
                        } label: {
                            Text(isCalendarOnCurrentMonth && isTodaySelected ? AppLocalization.string("今天") : AppLocalization.string("回到今天"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.appPrimarySurfaceSubtle)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("回到今天"))
                        .accessibilityHint(AppLocalization.string("返回本月并选中今天"))
                        Button {
                            moveMonth(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(AppLocalization.string("下个月"))
                        .accessibilityHint(AppLocalization.string("查看下个月日志"))
                    }
                    .overlay {
                        Button {
                            jumpToToday()
                        } label: {
                            Text(monthTitle(calendarMonth))
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("当前月份，双击回到今天"))
                        .accessibilityHint(AppLocalization.string("返回本月并选中今天"))
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach([
                            AppLocalization.string("一"),
                            AppLocalization.string("二"),
                            AppLocalization.string("三"),
                            AppLocalization.string("四"),
                            AppLocalization.string("五"),
                            AppLocalization.string("六"),
                            AppLocalization.string("日")
                        ], id: \.self) { weekday in
                            Text(weekday)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(calendarDaySlots) { slot in
                            CalendarDayCell(
                                date: slot.date,
                                isSelected: slot.date.map { Calendar.current.isDate($0, inSameDayAs: selectedCalendarDate) } ?? false,
                                isToday: slot.date.map { Calendar.current.isDateInToday($0) } ?? false,
                                logs: slot.date.map { calendarIndex.logs(on: $0) } ?? []
                            ) {
                                if let date = slot.date {
                                    selectedCalendarDate = date
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section(dayTitle(selectedCalendarDate)) {
                if selectedDateLogs.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("当天暂无日志"),
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(AppLocalization.string("可切换日期或新增一条施工日志。"))
                    )
                } else {
                    ForEach(selectedDateLogs) { log in
                        DailyLogEntryRow(
                            log: log,
                            projectName: log.projectId.flatMap { projectId in
                                store.projects.first(where: { $0.id == projectId })?.name
                            },
                            linkedMethodTitles: linkedMethodTitles(for: log.linkedConstructionMethodIDs),
                            onOpenPhoto: { selectedPhotoContext = $0 }
                        )
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button(AppLocalization.string("复制")) { copyLogToToday(log) }
                                    .tint(Color.appDoc)
                                Button(AppLocalization.string("编辑")) { startEdit(log) }
                                    .tint(Color.appPrimaryAction)
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { selectedDateLogs.indices.contains($0) ? selectedDateLogs[$0].id : nil }
                        deleteLogIds(ids)
                    }
                }
            }
        }
    }

    var photoWallContent: some View {
        DailyLogPhotoWallSection(
            items: filteredPhotoWallItems(),
            projects: store.projects,
            photoTagFilter: $photoTagFilter,
            isPhotoSelecting: $isPhotoSelecting,
            selectedPhotoKeys: $selectedPhotoKeys,
            batchPhotoTag: $batchPhotoTag,
            hasRectificationPair: hasRectificationPair(logId:),
            selectionKey: photoSelectionKey(_:),
            onToggleSelection: togglePhotoSelection(_:),
            onOpenPhoto: { selectedPhotoContext = $0 },
            onApplyBatchTag: applyBatchTagToSelectedPhotos,
            onExport: exportPhotoWallPDF(items:)
        )
    }
}

extension DailyLogView {
    @ToolbarContentBuilder
    var logToolbar: some ToolbarContent {
        if !usesSplitLogLayout {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(AppLocalization.string("项目"), selection: $filterProjectId) {
                        Text(AppLocalization.string("全部项目")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    Button {
                        showDateFilter = true
                    } label: {
                        Label(isDateFilterActive ? AppLocalization.string("调整日期筛选") : AppLocalization.string("日期筛选"), systemImage: "calendar")
                    }
                    if filterProjectId != nil || isDateFilterActive {
                        Button(AppLocalization.string("清除筛选")) {
                            filterProjectId = nil
                            isDateFilterActive = false
                        }
                    }
                } label: {
                    Image(systemName: filterProjectId != nil || isDateFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("筛选与排序"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("新建施工日志"))
            }
        }
    }

    var dateFilterSheet: some View {
        AppBusinessFormSheet(
            title: AppLocalization.string("日期筛选"),
            cancelTitle: AppLocalization.string("清除"),
            primaryActionTitle: AppLocalization.string("确定"),
            onCancel: {
                isDateFilterActive = false
                showDateFilter = false
            },
            onPrimaryAction: {
                isDateFilterActive = true
                showDateFilter = false
            }
        ) {
            DatePicker(AppLocalization.string("开始"), selection: $filterStart, displayedComponents: .date)
            DatePicker(AppLocalization.string("结束"), selection: $filterEnd, displayedComponents: .date)
            Toggle(AppLocalization.string("启用日期筛选"), isOn: $isDateFilterActive)
        }
        .presentationDetents([.medium])
    }
}
