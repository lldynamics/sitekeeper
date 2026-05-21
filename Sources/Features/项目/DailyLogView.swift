import SwiftUI
import PhotosUI
import UIKit

struct DailyLogView: View {
    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let initialProjectId: UUID?
    let autoOpenComposer: Bool
    let focusedLogId: UUID?
    let initialPhotoDrafts: [DailyLogSeedPhoto]
    let initialContent: String
    @State var searchText = ""
    @State var viewMode: DailyLogMode = .list
    @State var showAdd = false
    @State var didAutoOpenComposer = false
    @State var didOpenFocusedLog = false
    @State var composer = DailyLogComposerState()
    @State var showDateFilter = false
    @State var isDateFilterActive = false
    @State var filterStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State var filterEnd = Date()
    @State var filterProjectId: UUID?
    @State var calendarMonth = Date()
    @State var selectedCalendarDate = Date()
    @State var selectedPhotoContext: SelectedPhotoContext?
    @State var photoTagFilter: PhotoTag?
    @State var isPhotoSelecting = false
    @State var selectedPhotoKeys: Set<String> = []
    @State var batchPhotoTag: PhotoTag = .general
    @State var exportPayload: ExportPayload?
    @State var showExporter = false
    @State var showEdit = false
    @State var editor = DailyLogEditorState()
    @State var alertMessage = ""
    @State var showAlert = false
    @State var photoWallExportTask: Task<Void, Never>?
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    init(
        initialProjectId: UUID? = nil,
        autoOpenComposer: Bool = false,
        focusedLogId: UUID? = nil,
        initialPhotoDrafts: [DailyLogSeedPhoto] = [],
        initialContent: String = ""
    ) {
        self.initialProjectId = initialProjectId
        self.autoOpenComposer = autoOpenComposer
        self.focusedLogId = focusedLogId
        self.initialPhotoDrafts = initialPhotoDrafts
        self.initialContent = initialContent
        _composer = State(
            initialValue: DailyLogComposerState(
                initialProjectId: initialProjectId,
                initialDate: initialPhotoDrafts.first?.capturedAt ?? Date(),
                initialContent: initialContent,
                initialPhotoDrafts: initialPhotoDrafts.map(\.photoDraft)
            )
        )
        _filterProjectId = State(initialValue: initialProjectId)
    }

    let weatherOptions = ["晴", "多云", "阴", "小雨", "大雨", "雪"]
    let contentTemplates = [
        String(localized: "完成今日计划施工，现场质量正常"),
        String(localized: "完成线路敷设，待下一步复核"),
        String(localized: "完成材料进场与现场整理")
    ]
    let safetyTemplates = [
        String(localized: "已进行班前安全交底，未发现安全隐患"),
        String(localized: "临边洞口已复查，临电使用正常"),
        String(localized: "发现问题已现场整改并复核")
    ]
    let materialTemplates = [
        String(localized: "主材已进场并完成清点"),
        String(localized: "辅材已补齐，数量待复核"),
        String(localized: "暂无新增材料进场")
    ]

    var filtered: [DailyLog] {
        var result = store.dailyLogs
        if let filterProjectId {
            result = result.filter { $0.projectId == filterProjectId }
        }
        result = SearchMatcher.filter(
            result,
            keyword: searchText,
            extraFields: { log in
                linkedMethodTitles(for: log.linkedConstructionMethodIDs)
            }
        )
        if isDateFilterActive {
            let df = Formatters.date
            let start = Calendar.current.startOfDay(for: filterStart)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: filterEnd)) ?? filterEnd
            result = result.filter {
                guard let d = df.date(from: $0.date) else { return false }
                return d >= start && d < end
            }
        }
        return result
    }

    var selectedDateLogs: [DailyLog] {
        logs(on: selectedCalendarDate)
    }

    var calendarDays: [Date?] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: calendarMonth)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday + 5) % 7
        let days = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        let trailing = (7 - ((leading + days.count) % 7)) % 7
        return Array(repeating: nil, count: leading) + days + Array(repeating: nil, count: trailing)
    }

    var isCalendarOnCurrentMonth: Bool {
        Calendar.current.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
    }

    var isTodaySelected: Bool {
        Calendar.current.isDateInToday(selectedCalendarDate)
    }

    var usesSplitLogLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var dailyLogSearchSuggestions: [RealtimeSearchSuggestion] {
        filtered.prefix(8).map { log in
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? log.date : log.content
            return RealtimeSearchSuggestion(
                id: "log-\(log.id.uuidString)",
                category: .log,
                entityId: log.id,
                title: title,
                subtitleParts: [
                    log.date,
                    log.projectId.flatMap { projectId in
                        store.projects.first(where: { $0.id == projectId })?.name
                    } ?? "",
                    log.safety,
                ],
                score: 100
            )
        }
    }

    var body: some View {
        Group {
            if usesSplitLogLayout {
                splitLogLayout
            } else {
                compactLogLayout
            }
        }
        .navigationTitle(String(localized: "施工日志"))
        .toolbar {
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
        .sheet(isPresented: $showDateFilter) {
            NavigationStack {
                Form {
                    DatePicker(String(localized: "开始"), selection: $filterStart, displayedComponents: .date)
                    DatePicker(String(localized: "结束"), selection: $filterEnd, displayedComponents: .date)
                    Toggle(String(localized: "启用日期筛选"), isOn: $isDateFilterActive)
                }
                .navigationTitle(String(localized: "日期筛选"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "清除")) {
                            isDateFilterActive = false
                            showDateFilter = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "确定")) {
                            isDateFilterActive = true
                            showDateFilter = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAdd) {
            addLogForm
        }
        .sheet(isPresented: $showEdit) {
            editLogForm
        }
        .sheet(item: $selectedPhotoContext) { context in
            PhotoDetailSheet(
                context: context,
                allLogs: store.dailyLogs,
                onSave: { note, tag in
                    updatePhoto(context: context, note: note, tag: tag)
                },
                onDelete: {
                    deletePhoto(context: context)
                }
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .pdf,
            defaultFilename: exportPayload?.defaultFilename ?? String(localized: "现场照片页.pdf")
        ) { _ in }
        .alert(String(localized: "施工日志"), isPresented: $showAlert) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .operationToast(notice: $operationNotice)
        .onAppear {
            openFocusedLogIfNeeded()
            guard autoOpenComposer, !didAutoOpenComposer else { return }
            didAutoOpenComposer = true
            composer.projectId = initialProjectId
            showAdd = true
        }
        .onDisappear {
            photoWallExportTask?.cancel()
            photoWallExportTask = nil
            undoableDeletion.flushPendingCommit()
        }
    }

}
