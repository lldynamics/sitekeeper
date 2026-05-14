import SwiftUI
import PhotosUI
import UIKit
import ImageIO

private struct DailyLogComposerState {
    var date: Date = Date()
    var weather: String = autoWeatherNow()
    var content: String = ""
    var workers: String = ""
    var safety: String = ""
    var materials: String = ""
    var tomorrowPlan: String = ""
    var qualityIssue: String = ""
    var rectification: String = ""
    var confirmer: String = ""
    var linkedMethodIDs: Set<UUID> = []
    var selectedPhotos: [PhotosPickerItem] = []
    var photoDrafts: [PhotoDraft] = []
    var showLogCamera = false
    var cameraPhotoTag: PhotoTag = .general
    var projectId: UUID?

    init(
        initialProjectId: UUID? = nil,
        initialDate: Date = Date(),
        initialContent: String = "",
        initialPhotoDrafts: [PhotoDraft] = []
    ) {
        date = initialDate
        content = initialContent
        photoDrafts = initialPhotoDrafts
        projectId = initialProjectId
    }
}

private struct DailyLogEditorState {
    var logId: UUID?
    var date = Date()
    var weather = "晴"
    var content = ""
    var workers = ""
    var safety = ""
    var materials = ""
    var tomorrowPlan = ""
    var qualityIssue = ""
    var rectification = ""
    var confirmer = ""
    var linkedMethodIDs: Set<UUID> = []
    var projectId: UUID?
}

struct DailyLogView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let initialProjectId: UUID?
    let autoOpenComposer: Bool
    let focusedLogId: UUID?
    let initialPhotoDrafts: [DailyLogSeedPhoto]
    let initialContent: String
    @State private var searchText = ""
    @State private var viewMode: DailyLogMode = .list
    @State private var showAdd = false
    @State private var didAutoOpenComposer = false
    @State private var didOpenFocusedLog = false
    @State private var composer = DailyLogComposerState()
    @State private var showDateFilter = false
    @State private var isDateFilterActive = false
    @State private var filterStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var filterEnd = Date()
    @State private var filterProjectId: UUID?
    @State private var calendarMonth = Date()
    @State private var selectedCalendarDate = Date()
    @State private var selectedPhotoContext: SelectedPhotoContext?
    @State private var photoTagFilter: PhotoTag?
    @State private var isPhotoSelecting = false
    @State private var selectedPhotoKeys: Set<String> = []
    @State private var batchPhotoTag: PhotoTag = .general
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var showEdit = false
    @State private var editor = DailyLogEditorState()
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var photoWallExportTask: Task<Void, Never>?

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

    private let weatherOptions = ["晴", "多云", "阴", "小雨", "大雨", "雪"]
    private let contentTemplates = ["完成今日计划施工，现场质量正常", "完成线路敷设，待下一步复核", "完成材料进场与现场整理"]
    private let safetyTemplates = ["已进行班前安全交底，未发现安全隐患", "临边洞口已复查，临电使用正常", "发现问题已现场整改并复核"]
    private let materialTemplates = ["主材已进场并完成清点", "辅材已补齐，数量待复核", "暂无新增材料进场"]

    private var filtered: [DailyLog] {
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

    private var selectedDateLogs: [DailyLog] {
        logs(on: selectedCalendarDate)
    }

    private var calendarDays: [Date?] {
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

    private var isCalendarOnCurrentMonth: Bool {
        Calendar.current.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(selectedCalendarDate)
    }

    private var usesSplitLogLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLogLayout {
                splitLogLayout
            } else {
                compactLogLayout
            }
        }
        .searchable(text: $searchText, prompt: "按日期、内容、安全事项搜索")
        .navigationTitle("施工日志")
        .toolbar {
            if !usesSplitLogLayout {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("项目", selection: $filterProjectId) {
                            Text("全部项目").tag(nil as UUID?)
                            ForEach(store.projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                        Button {
                            showDateFilter = true
                        } label: {
                            Label(isDateFilterActive ? "调整日期筛选" : "日期筛选", systemImage: "calendar")
                        }
                        if filterProjectId != nil || isDateFilterActive {
                            Button("清除筛选") {
                                filterProjectId = nil
                                isDateFilterActive = false
                            }
                        }
                    } label: {
                        Image(systemName: filterProjectId != nil || isDateFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                    .accessibilityLabel("筛选与排序")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                        .accessibilityLabel("新建施工日志")
                }
            }
        }
        .sheet(isPresented: $showDateFilter) {
            NavigationStack {
                Form {
                    DatePicker("开始", selection: $filterStart, displayedComponents: .date)
                    DatePicker("结束", selection: $filterEnd, displayedComponents: .date)
                    Toggle("启用日期筛选", isOn: $isDateFilterActive)
                }
                .navigationTitle("日期筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("清除") {
                            isDateFilterActive = false
                            showDateFilter = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
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
            defaultFilename: exportPayload?.defaultFilename ?? "现场照片页.pdf"
        ) { _ in }
        .alert("施工日志", isPresented: $showAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
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
        }
    }

    private var compactLogLayout: some View {
        List {
            modePickerSection
            logDetailContent
        }
    }

    private var splitLogLayout: some View {
        NavigationSplitView {
            List {
                modePickerSection
                splitFilterSection
                Section("快捷操作") {
                    Button {
                        showAdd = true
                    } label: {
                        Label("新建施工日志", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            }
            .navigationTitle("日志筛选")
        } detail: {
            List {
                logDetailContent
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var modePickerSection: some View {
        Section {
            Picker("视图", selection: $viewMode) {
                ForEach(DailyLogMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var splitFilterSection: some View {
        Section("筛选") {
            Picker("项目", selection: $filterProjectId) {
                Text("全部项目").tag(nil as UUID?)
                ForEach(store.projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            Button {
                showDateFilter = true
            } label: {
                Label(isDateFilterActive ? "调整日期筛选" : "日期筛选", systemImage: "calendar")
            }
            if filterProjectId != nil || isDateFilterActive {
                Button("清除筛选") {
                    filterProjectId = nil
                    isDateFilterActive = false
                }
            }
        }
    }

    @ViewBuilder
    private var logDetailContent: some View {
        if filtered.isEmpty {
            ContentUnavailableView("暂无施工日志", systemImage: "book.pages", description: Text("添加日志后可按项目、日期、内容和安全事项检索"))
        } else if viewMode == .list {
            ForEach(filtered) { log in
                logRow(log)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("复制") { copyLogToToday(log) }
                            .tint(Color.appDoc)
                        Button("编辑") { startEdit(log) }
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

    private var calendarContent: some View {
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
                        .accessibilityLabel("上个月")
                        .accessibilityHint("查看上个月日志")
                        Spacer()
                        Button {
                            jumpToToday()
                        } label: {
                            Text(isCalendarOnCurrentMonth && isTodaySelected ? "今天" : "回到今天")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.appPrimarySurfaceSubtle)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("回到今天")
                        .accessibilityHint("返回本月并选中今天")
                        Button {
                            moveMonth(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("下个月")
                        .accessibilityHint("查看下个月日志")
                    }
                    .overlay {
                        Button {
                            jumpToToday()
                        } label: {
                            Text(monthTitle(calendarMonth))
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("当前月份，双击回到今天")
                        .accessibilityHint("返回本月并选中今天")
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                            Text(weekday)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                            CalendarDayCell(
                                date: date,
                                isSelected: date.map { Calendar.current.isDate($0, inSameDayAs: selectedCalendarDate) } ?? false,
                                isToday: date.map { Calendar.current.isDateInToday($0) } ?? false,
                                logs: date.map { logs(on: $0) } ?? []
                            ) {
                                if let date {
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
                        "当天暂无日志",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("可切换日期或新增一条施工日志。")
                    )
                } else {
                    ForEach(selectedDateLogs) { log in
                        logRow(log)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("复制") { copyLogToToday(log) }
                                    .tint(Color.appDoc)
                                Button("编辑") { startEdit(log) }
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

    private func logRow(_ log: DailyLog) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack {
                Text(log.date).font(.body.weight(.medium))
                Spacer()
                Text(log.weather).font(.caption).foregroundStyle(.secondary)
                Text(log.workers).font(.caption).foregroundStyle(.secondary)
            }
            if let pid = log.projectId, let project = store.projects.first(where: { $0.id == pid }) {
                Text(project.name).font(.caption2).foregroundStyle(Color.appDoc)
            }
            Text(log.content).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            if !log.safety.isEmpty {
                Label(log.safety, systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.materials.isEmpty {
                Label(log.materials, systemImage: "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.tomorrowPlan.isEmpty {
                Label(log.tomorrowPlan, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !log.qualityIssue.isEmpty || !log.rectification.isEmpty {
                Label(log.qualityIssue.isEmpty ? log.rectification : log.qualityIssue, systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .foregroundStyle(.appRisk)
                    .lineLimit(2)
            }
            let linkedTitles = linkedMethodTitles(for: log.linkedConstructionMethodIDs)
            if !linkedTitles.isEmpty {
                Label(linkedTitles.joined(separator: " · "), systemImage: "book.pages")
                    .font(.caption)
                    .foregroundStyle(Color.appPrimaryAction)
                    .lineLimit(2)
            }
            if !log.photoAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppSpacing.tight) {
                        ForEach(log.photoAttachments) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    selectedPhotoContext = SelectedPhotoContext(logId: log.id, photoId: photo.id, legacyFileName: photo.fileName)
                                } label: {
                                    AsyncPhotoThumbnailImageView(fileName: photo.fileName) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 110, height: 82)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(uiColor: .secondarySystemFill))
                                            .frame(width: 110, height: 82)
                                            .overlay {
                                                Image(systemName: "photo")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看日志照片，标签 \(photo.tag.displayName)")
                                .accessibilityHint("打开照片详情")
                                Text(photo.tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appDoc)
                                if !photo.note.isEmpty {
                                    Text(photo.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(width: 110, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var photoWallContent: some View {
        Section("照片墙") {
            let items = filteredPhotoWallItems()
            HStack {
                Picker("标签", selection: $photoTagFilter) {
                    Text("全部").tag(nil as PhotoTag?)
                    ForEach(PhotoTag.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item as PhotoTag?)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button(isPhotoSelecting ? "结束批量" : "批量操作") {
                    isPhotoSelecting.toggle()
                    if !isPhotoSelecting {
                        selectedPhotoKeys.removeAll()
                    }
                }
                .font(.caption)
            }
            if isPhotoSelecting {
                HStack {
                    Picker("批量标签", selection: $batchPhotoTag) {
                        ForEach(PhotoTag.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    Button("应用到\(selectedPhotoKeys.count)张") {
                        applyBatchTagToSelectedPhotos()
                    }
                    .disabled(selectedPhotoKeys.isEmpty)
                    Button("清空选择") {
                        selectedPhotoKeys.removeAll()
                    }
                    .disabled(selectedPhotoKeys.isEmpty)
                }
                .font(.caption)
            }
            Button {
                exportPhotoWallPDF(items: items)
            } label: {
                Label("按当前项目/筛选导出照片页", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .disabled(items.isEmpty)
            if items.isEmpty {
                ContentUnavailableView(
                    "暂无现场照片",
                    systemImage: "photo.on.rectangle",
                    description: Text("添加日志照片后可在这里按标签查看。")
                )
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.tight), count: 3), spacing: AppSpacing.normal) {
                    ForEach(items) { item in
                        Button {
                            if isPhotoSelecting {
                                togglePhotoSelection(item)
                            } else {
                                selectedPhotoContext = SelectedPhotoContext(logId: item.logId, photoId: item.photo.id, legacyFileName: item.photo.fileName)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncPhotoThumbnailImageView(fileName: item.photo.fileName) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 88)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            if isPhotoSelecting {
                                                let selected = selectedPhotoKeys.contains(photoSelectionKey(item))
                                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(selected ? Color.appPrimaryAction : .white)
                                                    .padding(4)
                                            }
                                        }
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                        .frame(height: 88)
                                        .overlay(alignment: .topTrailing) {
                                            if isPhotoSelecting {
                                                let selected = selectedPhotoKeys.contains(photoSelectionKey(item))
                                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(selected ? Color.appPrimaryAction : .secondary)
                                                    .padding(4)
                                            }
                                        }
                                }
                                Text(item.logDate)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(item.photo.tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appDoc)
                                    .lineLimit(1)
                                if hasRectificationPair(logId: item.logId),
                                   (item.photo.tag == .rectificationBefore || item.photo.tag == .rectificationAfter) {
                                    Text("已配对")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.appSuccess)
                                }
                                if !item.photo.note.isEmpty {
                                    Text(item.photo.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let project = item.projectId.flatMap({ pid in store.projects.first(where: { $0.id == pid }) }) {
                                    Text(project.name)
                                        .font(.caption2)
                                        .foregroundStyle(Color.appDoc)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.logDate)，\(item.photo.tag.displayName)")
                        .accessibilityHint(isPhotoSelecting ? "双击切换选择状态" : "双击查看照片详情")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func filteredPhotoWallItems() -> [PhotoWallItem] {
        let allItems = filtered.flatMap { log in
            log.photoAttachments.map { PhotoWallItem(logId: log.id, logDate: log.date, projectId: log.projectId, photo: $0) }
        }
        guard let photoTagFilter else { return allItems }
        return allItems.filter { $0.photo.tag == photoTagFilter }
    }

    private func photoSelectionKey(_ item: PhotoWallItem) -> String {
        "\(item.logId.uuidString)-\(item.photo.fileName)"
    }

    private func togglePhotoSelection(_ item: PhotoWallItem) {
        let key = photoSelectionKey(item)
        if selectedPhotoKeys.contains(key) {
            selectedPhotoKeys.remove(key)
        } else {
            selectedPhotoKeys.insert(key)
        }
    }

    private func applyBatchTagToSelectedPhotos() {
        guard !selectedPhotoKeys.isEmpty else { return }
        for logIndex in store.dailyLogs.indices {
            for photoIndex in store.dailyLogs[logIndex].photos.indices {
                let photo = store.dailyLogs[logIndex].photos[photoIndex]
                let key = "\(store.dailyLogs[logIndex].id.uuidString)-\(photo.fileName)"
                if selectedPhotoKeys.contains(key) {
                    store.dailyLogs[logIndex].photos[photoIndex].tag = batchPhotoTag
                }
            }
            if let legacy = store.dailyLogs[logIndex].photoFileName {
                let key = "\(store.dailyLogs[logIndex].id.uuidString)-\(legacy)"
                if selectedPhotoKeys.contains(key) {
                    if let idx = store.dailyLogs[logIndex].photos.firstIndex(where: { $0.fileName == legacy }) {
                        store.dailyLogs[logIndex].photos[idx].tag = batchPhotoTag
                    } else {
                        store.dailyLogs[logIndex].photos.append(LogPhoto(fileName: legacy, tag: batchPhotoTag))
                    }
                }
            }
        }
        store.scheduleSave()
        selectedPhotoKeys.removeAll()
    }

    private func hasRectificationPair(logId: UUID) -> Bool {
        guard let log = store.dailyLogs.first(where: { $0.id == logId }) else { return false }
        let tags = Set(log.photoAttachments.map(\.tag))
        return tags.contains(.rectificationBefore) && tags.contains(.rectificationAfter)
    }

    private func exportPhotoWallPDF(items: [PhotoWallItem]) {
        let projectName: String
        if let filterProjectId, let project = store.projects.first(where: { $0.id == filterProjectId }) {
            projectName = project.name
        } else {
            projectName = "全部项目"
        }
        let payloads = items.map { item in
            ReportPhotoItem(
                date: item.logDate,
                projectName: item.projectId.flatMap { pid in store.projects.first(where: { $0.id == pid })?.name } ?? "未归属",
                tag: item.photo.tag.displayName,
                note: item.photo.note,
                fileName: item.photo.fileName
            )
        }
        photoWallExportTask?.cancel()
        photoWallExportTask = Task {
            let data = await ReportBuilder.makePhotoWallPDFAsync(title: "\(projectName)-现场照片页", items: payloads)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                exportPayload = ExportPayload(data: data, contentType: .pdf, defaultFilename: "\(projectName)_现场照片页.pdf")
                showExporter = true
                photoWallExportTask = nil
            }
        }
    }

    private var addLogForm: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    DatePicker("日期", selection: $composer.date, displayedComponents: .date)
                    Picker("天气", selection: $composer.weather) {
                        ForEach(weatherOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("人数", text: $composer.workers)
                    Picker("选择工程", selection: $composer.projectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section("施工内容") {
                    Menu("套用内容模板") {
                        ForEach(contentTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.content = tpl }
                        }
                    }
                    if !store.templates.filter({ $0.category == .dailyLog }).isEmpty {
                        Menu("套用我的日志模板") {
                            ForEach(store.templates.filter { $0.category == .dailyLog }) { template in
                                Button(template.name) { applyDailyLogTemplate(template) }
                            }
                        }
                    }
                    TextField("内容", text: $composer.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("安全与材料") {
                    Menu("套用安全模板") {
                        ForEach(safetyTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.safety = tpl }
                        }
                    }
                    TextField("安全事项", text: $composer.safety, axis: .vertical)
                        .lineLimit(2...4)
                    Menu("套用材料模板") {
                        ForEach(materialTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.materials = tpl }
                        }
                    }
                    TextField("材料进场", text: $composer.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("计划与质量") {
                    Button {
                        composer.tomorrowPlan = generateTomorrowPlanFromTodos(for: composer.projectId)
                    } label: {
                        Label("从今日待办生成明日计划", systemImage: "wand.and.stars")
                    }
                    TextField("明日计划", text: $composer.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("质量问题", text: $composer.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("整改记录", text: $composer.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("现场确认人", text: $composer.confirmer)
                }
                constructionMethodLinkSection(selection: $composer.linkedMethodIDs)
                DailyLogWatermarkPhotoSection(
                    cameraPhotoTag: $composer.cameraPhotoTag,
                    selectedPhotos: $composer.selectedPhotos,
                    photoDrafts: $composer.photoDrafts,
                    onOpenCamera: { composer.showLogCamera = true }
                )
            }
            .navigationTitle("写日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showAdd = false
                        clearDraft()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        showAdd = false
                    }
                    .disabled(!canSaveLog)
                }
            }
        }
        .onChange(of: composer.selectedPhotos) { _, newItems in
            let remainingSlots = max(6 - composer.photoDrafts.count, 0)
            Task {
                guard !newItems.isEmpty else { return }
                var drafts: [PhotoDraft] = []
                for item in newItems.prefix(remainingSlots) {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                        if let normalizedData = normalizePhotoData(data, maxPixelSize: 1600, compressionQuality: 0.8) {
                            drafts.append(PhotoDraft(data: normalizedData))
                        }
                    } catch {
                        StorageIssueLog.record("施工日志图片导入失败：\(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    composer.photoDrafts.append(contentsOf: drafts)
                    composer.selectedPhotos = []
                }
            }
        }
        .sheet(isPresented: $composer.showLogCamera) {
            ImagePickerView(
                sourceType: .camera,
                onPickedWithTimestamp: { image, capturedAt in
                    appendCameraPhoto(image, capturedAt: capturedAt)
                },
                onPicked: { image in
                    appendCameraPhoto(image, capturedAt: Date())
                }
            )
        }
    }

    private var editLogForm: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    DatePicker("日期", selection: $editor.date, displayedComponents: .date)
                    Picker("天气", selection: $editor.weather) {
                        ForEach(weatherOptions, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("人数", text: $editor.workers)
                    Picker("选择工程", selection: $editor.projectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section("施工内容") {
                    TextField("内容", text: $editor.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("安全与材料") {
                    TextField("安全事项", text: $editor.safety, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("材料进场", text: $editor.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("计划与质量") {
                    Button {
                        editor.tomorrowPlan = generateTomorrowPlanFromTodos(for: editor.projectId)
                    } label: {
                        Label("从今日待办生成明日计划", systemImage: "wand.and.stars")
                    }
                    TextField("明日计划", text: $editor.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("质量问题", text: $editor.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("整改记录", text: $editor.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("现场确认人", text: $editor.confirmer)
                }
                constructionMethodLinkSection(selection: $editor.linkedMethodIDs)
            }
            .navigationTitle("编辑日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveEditedLog()
                        showEdit = false
                    }
                    .disabled(editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard canSaveLog else { return }
        let logId = UUID()
        let fileNames: [String]
        do {
            fileNames = try PhotoStorage.saveManyOrThrow(originals: composer.photoDrafts.map(\.data), logId: logId)
        } catch {
            alertMessage = "现场照片保存失败：\(error.localizedDescription)"
            showAlert = true
            return
        }
        let photos = zip(fileNames, composer.photoDrafts).map { fileName, draft in
            LogPhoto(fileName: fileName, note: draft.note, tag: draft.tag)
        }
        store.insertDailyLogAtTop(DailyLog(
            id: logId,
            date: Formatters.date.string(from: composer.date),
            weather: composer.weather,
            content: composer.content,
            workers: composer.workers,
            photoFileName: fileNames.first,
            photos: photos,
            safety: composer.safety,
            materials: composer.materials,
            tomorrowPlan: composer.tomorrowPlan,
            qualityIssue: composer.qualityIssue,
            rectification: composer.rectification,
            confirmer: composer.confirmer,
            linkedConstructionMethodIDs: sortedLinkedMethodIDs(composer.linkedMethodIDs),
            projectId: composer.projectId
        ))
        store.scheduleSave()
        clearDraft()
    }

    private func deleteLogs(_ idx: IndexSet) {
        let ids = idx.map { filtered[$0].id }
        deleteLogIds(ids)
    }

    private func deleteLogIds(_ ids: [UUID]) {
        for id in ids {
            if let log = store.dailyLogs.first(where: { $0.id == id }) {
                PhotoStorage.delete(fileNames: log.allPhotoFileNames)
            }
        }
        store.removeDailyLogs(ids: Set(ids))
        store.scheduleSave()
    }

    private func updatePhoto(context: SelectedPhotoContext, note: String, tag: PhotoTag) {
        guard let logIndex = store.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = store.dailyLogs[logIndex]
        if let photoIndex = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            log.photos[photoIndex].note = note
            log.photos[photoIndex].tag = tag
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            log.photos.append(LogPhoto(fileName: legacy, note: note, tag: tag))
        }
        store.dailyLogs[logIndex] = log
        store.scheduleSave()
    }

    private func deletePhoto(context: SelectedPhotoContext) {
        guard let logIndex = store.dailyLogs.firstIndex(where: { $0.id == context.logId }) else { return }
        var log = store.dailyLogs[logIndex]
        if let index = log.photos.firstIndex(where: { $0.id == context.photoId }) {
            let fileName = log.photos[index].fileName
            PhotoStorage.delete(fileName: fileName)
            log.photos.remove(at: index)
            if log.photoFileName == fileName {
                log.photoFileName = log.photos.first?.fileName
            }
        } else if let legacy = log.photoFileName, legacy == context.legacyFileName {
            PhotoStorage.delete(fileName: legacy)
            log.photoFileName = nil
        }
        store.dailyLogs[logIndex] = log
        store.scheduleSave()
    }

    private func logs(on date: Date) -> [DailyLog] {
        let key = Formatters.date.string(from: date)
        return filtered.filter { $0.date == key }
    }

    private func moveMonth(_ value: Int) {
        calendarMonth = Calendar.current.date(byAdding: .month, value: value, to: calendarMonth) ?? calendarMonth
    }

    private func jumpToToday() {
        let today = Date()
        selectedCalendarDate = today
        calendarMonth = today
    }

    private func monthTitle(_ date: Date) -> String {
        DailyLogDateFormatters.monthTitle.string(from: date)
    }

    private func dayTitle(_ date: Date) -> String {
        DailyLogDateFormatters.dayTitle.string(from: date)
    }

    private func clearDraft() {
        composer.selectedPhotos = []
        composer.photoDrafts = []
        composer.showLogCamera = false
        composer.cameraPhotoTag = .general
        composer.projectId = initialProjectId
        composer.content = ""
        composer.workers = ""
        composer.safety = ""
        composer.materials = ""
        composer.tomorrowPlan = ""
        composer.qualityIssue = ""
        composer.rectification = ""
        composer.confirmer = ""
        composer.linkedMethodIDs.removeAll()
        composer.weather = autoWeatherNow()
    }

    private func startEdit(_ log: DailyLog) {
        editor.logId = log.id
        editor.date = Formatters.date.date(from: log.date) ?? Date()
        editor.weather = log.weather
        editor.content = log.content
        editor.workers = log.workers
        editor.safety = log.safety
        editor.materials = log.materials
        editor.tomorrowPlan = log.tomorrowPlan
        editor.qualityIssue = log.qualityIssue
        editor.rectification = log.rectification
        editor.confirmer = log.confirmer
        editor.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        editor.projectId = log.projectId
        showEdit = true
    }

    private func openFocusedLogIfNeeded() {
        guard let focusedLogId, !didOpenFocusedLog,
              let log = store.dailyLogs.first(where: { $0.id == focusedLogId }) else { return }
        didOpenFocusedLog = true
        viewMode = .list
        filterProjectId = log.projectId
        searchText = ""
        Task { @MainActor in
            startEdit(log)
        }
    }

    private func saveEditedLog() {
        guard let id = editor.logId,
              let index = store.dailyLogs.firstIndex(where: { $0.id == id }) else { return }
        var log = store.dailyLogs[index]
        log.date = Formatters.date.string(from: editor.date)
        log.weather = editor.weather
        log.content = editor.content
        log.workers = editor.workers
        log.safety = editor.safety
        log.materials = editor.materials
        log.tomorrowPlan = editor.tomorrowPlan
        log.qualityIssue = editor.qualityIssue
        log.rectification = editor.rectification
        log.confirmer = editor.confirmer
        log.linkedConstructionMethodIDs = sortedLinkedMethodIDs(editor.linkedMethodIDs)
        log.projectId = editor.projectId
        store.dailyLogs[index] = log
        store.scheduleSave()
    }

    private func copyLogToToday(_ log: DailyLog) {
        composer.date = Date()
        composer.weather = log.weather
        composer.content = log.content
        composer.workers = log.workers
        composer.safety = log.safety
        composer.materials = log.materials
        composer.tomorrowPlan = log.tomorrowPlan
        composer.qualityIssue = log.qualityIssue
        composer.rectification = log.rectification
        composer.confirmer = log.confirmer
        composer.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        composer.projectId = log.projectId
        composer.selectedPhotos = []
        composer.photoDrafts = []
        showAdd = true
    }

    private func generateTomorrowPlanFromTodos(for projectId: UUID?) -> String {
        let today = Formatters.date.string(from: Date())
        let items = store.siteTodos.filter { todo in
            guard !todo.isDone else { return false }
            if todo.dueDate != today { return false }
            if let projectId {
                return todo.projectId == projectId
            }
            return true
        }
        if items.isEmpty { return "" }
        return items.map { "• \($0.title)" }.joined(separator: "\n")
    }

    @ViewBuilder
    private func constructionMethodLinkSection(selection: Binding<Set<UUID>>) -> some View {
        Section("关联施工工艺") {
            if store.constructionMethods.isEmpty {
                Text("暂无工艺条目，可先在工具箱-施工工艺库新增")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.constructionMethods) { method in
                    Toggle(isOn: methodSelectionBinding(method.id, selection: selection)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(constructionMethodTitle(method))
                            HStack(spacing: 6) {
                                if !method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(method.trade)
                                }
                                Text(method.versionName.isEmpty ? "V1" : method.versionName)
                                Text(method.publishStatus.displayName)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private func methodSelectionBinding(_ id: UUID, selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(id)
                } else {
                    selection.wrappedValue.remove(id)
                }
            }
        )
    }

    private func constructionMethodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "未命名工艺" : title
    }

    private func linkedMethodTitles(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.constructionMethods.map { ($0.id, constructionMethodTitle($0)) })
        return ids.compactMap { lookup[$0] }
    }

    private func sortedLinkedMethodIDs(_ selectedIDs: Set<UUID>) -> [UUID] {
        store.constructionMethods
            .map(\.id)
            .filter { selectedIDs.contains($0) }
    }

    private func applyDailyLogTemplate(_ template: ProjectTemplate) {
        composer.content = template.content
    }

    private func appendCameraPhoto(_ image: UIImage, capturedAt: Date) {
        guard composer.photoDrafts.count < 6,
              let data = image.jpegData(compressionQuality: 0.82),
              let normalizedData = normalizePhotoData(data, maxPixelSize: 1600, compressionQuality: 0.8) else { return }
        composer.photoDrafts.append(
            PhotoDraft(
                data: normalizedData,
                note: logWatermarkPhotoNote(capturedAt: capturedAt),
                tag: composer.cameraPhotoTag
            )
        )
    }

    private func normalizePhotoData(_ data: Data, maxPixelSize: CGFloat, compressionQuality: CGFloat) -> Data? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality)
    }

    private func logWatermarkPhotoNote(capturedAt: Date) -> String {
        [
            "来源: 拍照",
            "拍摄时间: \(Formatters.dateTime.string(from: capturedAt))",
            "标签: \(composer.cameraPhotoTag.rawValue)"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private var canSaveLog: Bool {
        let contentReady = !composer.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let workersReady = composer.workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || InputValidator.nonNegativeNumber(composer.workers)
        return contentReady && workersReady
    }
}

private enum DailyLogDateFormatters {
    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}
