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
                Section(String(localized: "快捷操作")) {
                    Button {
                        showAdd = true
                    } label: {
                        Label(String(localized: "新建施工日志"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            }
            .navigationTitle(String(localized: "日志筛选"))
        } detail: {
            List {
                logDetailContent
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    var searchPanelSection: some View {
        Section(String(localized: "快速查找")) {
            InlineSearchPanel(
                text: $searchText,
                prompt: String(localized: "按日期、内容、安全事项搜索"),
                suggestions: dailyLogSearchSuggestions,
                emptyStateText: String(localized: "未找到匹配日志")
            ) { suggestion in
                searchText = suggestion.title
                viewMode = .list
            }
        }
    }

    var modePickerSection: some View {
        Section {
            Picker(String(localized: "视图"), selection: $viewMode) {
                ForEach(DailyLogMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    var splitFilterSection: some View {
        Section(String(localized: "筛选")) {
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
        }
    }

    @ViewBuilder
    var logDetailContent: some View {
        if filtered.isEmpty {
            ContentUnavailableView(
                String(localized: "暂无施工日志"),
                systemImage: "book.pages",
                description: Text(String(localized: "添加日志后可按项目、日期、内容和安全事项检索"))
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
                        Button(String(localized: "复制")) { copyLogToToday(log) }
                            .tint(Color.appDoc)
                        Button(String(localized: "编辑")) { startEdit(log) }
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
        Group {
            Section {
                VStack(spacing: AppSpacing.normal) {
                    HStack {
                        Button {
                            moveMonth(-1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "上个月"))
                        .accessibilityHint(String(localized: "查看上个月日志"))
                        Spacer()
                        Button {
                            jumpToToday()
                        } label: {
                            Text(isCalendarOnCurrentMonth && isTodaySelected ? String(localized: "今天") : String(localized: "回到今天"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.appPrimarySurfaceSubtle)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "回到今天"))
                        .accessibilityHint(String(localized: "返回本月并选中今天"))
                        Button {
                            moveMonth(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "下个月"))
                        .accessibilityHint(String(localized: "查看下个月日志"))
                    }
                    .overlay {
                        Button {
                            jumpToToday()
                        } label: {
                            Text(monthTitle(calendarMonth))
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "当前月份，双击回到今天"))
                        .accessibilityHint(String(localized: "返回本月并选中今天"))
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach([
                            String(localized: "一"),
                            String(localized: "二"),
                            String(localized: "三"),
                            String(localized: "四"),
                            String(localized: "五"),
                            String(localized: "六"),
                            String(localized: "日")
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
                                logs: slot.date.map { logs(on: $0) } ?? []
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
                        String(localized: "当天暂无日志"),
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(String(localized: "可切换日期或新增一条施工日志。"))
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
                                Button(String(localized: "复制")) { copyLogToToday(log) }
                                    .tint(Color.appDoc)
                                Button(String(localized: "编辑")) { startEdit(log) }
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
