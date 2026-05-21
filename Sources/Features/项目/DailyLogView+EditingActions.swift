import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    var addLogForm: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基础信息")) {
                    DatePicker(String(localized: "日期"), selection: $composer.date, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $composer.weather) {
                        ForEach(weatherOptions, id: \.self) { Text(String(localized: String.LocalizationValue($0))).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $composer.workers)
                    Picker(String(localized: "选择工程"), selection: $composer.projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(String(localized: "施工内容")) {
                    Menu(String(localized: "套用内容模板")) {
                        ForEach(contentTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.content = tpl }
                        }
                    }
                    if !store.templates.filter({ $0.category == .dailyLog }).isEmpty {
                        Menu(String(localized: "套用我的日志模板")) {
                            ForEach(store.templates.filter { $0.category == .dailyLog }) { template in
                                Button(template.name) { applyDailyLogTemplate(template) }
                            }
                        }
                    }
                    TextField(String(localized: "内容"), text: $composer.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(String(localized: "安全与材料")) {
                    Menu(String(localized: "套用安全模板")) {
                        ForEach(safetyTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.safety = tpl }
                        }
                    }
                    TextField(String(localized: "安全事项"), text: $composer.safety, axis: .vertical)
                        .lineLimit(2...4)
                    Menu(String(localized: "套用材料模板")) {
                        ForEach(materialTemplates, id: \.self) { tpl in
                            Button(tpl) { composer.materials = tpl }
                        }
                    }
                    TextField(String(localized: "材料进场"), text: $composer.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "计划与质量")) {
                    Button {
                        composer.tomorrowPlan = generateTomorrowPlanFromTodos(for: composer.projectId)
                    } label: {
                        Label(String(localized: "从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(String(localized: "明日计划"), text: $composer.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $composer.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $composer.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $composer.confirmer)
                }
                constructionMethodLinkSection(selection: $composer.linkedMethodIDs)
                DailyLogWatermarkPhotoSection(
                    cameraPhotoTag: $composer.cameraPhotoTag,
                    selectedPhotos: $composer.selectedPhotos,
                    photoDrafts: $composer.photoDrafts,
                    onOpenCamera: { composer.showLogCamera = true }
                )
            }
            .navigationTitle(String(localized: "写日志"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showAdd = false
                        clearDraft()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
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
                        if let normalizedData = ImageDownsampleService.downsampledJPEGData(
                            data,
                            maxPixelSize: 1600,
                            compressionQuality: 0.8
                        ) {
                            drafts.append(PhotoDraft(data: normalizedData))
                        }
                    } catch {
                        StorageIssueLog.record(String(format: String(localized: "施工日志图片导入失败：%@"), error.localizedDescription))
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

    var editLogForm: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基础信息")) {
                    DatePicker(String(localized: "日期"), selection: $editor.date, displayedComponents: .date)
                    Picker(String(localized: "天气"), selection: $editor.weather) {
                        ForEach(weatherOptions, id: \.self) { Text(String(localized: String.LocalizationValue($0))).tag($0) }
                    }
                    TextField(String(localized: "人数"), text: $editor.workers)
                    Picker(String(localized: "选择工程"), selection: $editor.projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                    }
                }
                Section(String(localized: "施工内容")) {
                    TextField(String(localized: "内容"), text: $editor.content, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(String(localized: "安全与材料")) {
                    TextField(String(localized: "安全事项"), text: $editor.safety, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "材料进场"), text: $editor.materials, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section(String(localized: "计划与质量")) {
                    Button {
                        editor.tomorrowPlan = generateTomorrowPlanFromTodos(for: editor.projectId)
                    } label: {
                        Label(String(localized: "从今日待办生成明日计划"), systemImage: "wand.and.stars")
                    }
                    TextField(String(localized: "明日计划"), text: $editor.tomorrowPlan, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "质量问题"), text: $editor.qualityIssue, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "整改记录"), text: $editor.rectification, axis: .vertical)
                        .lineLimit(2...4)
                    TextField(String(localized: "现场确认人"), text: $editor.confirmer)
                }
                constructionMethodLinkSection(selection: $editor.linkedMethodIDs)
            }
            .navigationTitle(String(localized: "编辑日志"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        saveEditedLog()
                        showEdit = false
                    }
                    .disabled(editor.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    func save() {
        guard canSaveLog else { return }
        let logId = UUID()
        let fileNames: [String]
        do {
            fileNames = try PhotoStorage.saveManyOrThrow(originals: composer.photoDrafts.map(\.data), logId: logId)
        } catch {
            alertMessage = String(format: String(localized: "现场照片保存失败：%@"), error.localizedDescription)
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

    func deleteLogs(_ idx: IndexSet) {
        let ids = idx.map { filtered[$0].id }
        deleteLogIds(ids)
    }

    func deleteLogIds(_ ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.dailyLogs.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }

        let photoFileNames = targets.flatMap(\.allPhotoFileNames)
        let deletion = store.removeDailyLogs(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除施工日志 %lld 条"), Int64(targets.count)),
                detail: String(format: String(localized: "关联照片文件 %lld 个"), Int64(photoFileNames.count)),
                source: "DailyLogView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.photoFiles(
                photoFileNames,
                summary: "dailyLog.photoFiles"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条施工日志"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreDailyLogs(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func updatePhoto(context: SelectedPhotoContext, note: String, tag: PhotoTag) {
        guard store.updateDailyLogPhoto(
            logId: context.logId,
            photoId: context.photoId,
            legacyFileName: context.legacyFileName,
            note: note,
            tag: tag
        ) else { return }
        store.scheduleSave()
    }

    func deletePhoto(context: SelectedPhotoContext) {
        let snapshot = store.dailyLogs
        guard let deletedFileName = store.removeDailyLogPhoto(
            logId: context.logId,
            photoId: context.photoId,
            legacyFileName: context.legacyFileName
        ) else { return }
        let deferredCleanup = DataStoreDeferredFileCleanup.photoFiles(
            [deletedFileName],
            summary: "dailyLog.photoFiles.single"
        )
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除日志照片"),
            commit: {
                deferredCleanup?.perform()
                store.scheduleSave()
            },
            undo: {
                store.replaceDailyLogs(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.dailyLogs,
                    deletedIDs: Set([context.logId])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除施工日志照片"),
                detail: deletedFileName,
                source: "DailyLogView"
            )
        )
    }

    func logs(on date: Date) -> [DailyLog] {
        let key = Formatters.date.string(from: date)
        return filtered.filter { $0.date == key }
    }

    func moveMonth(_ value: Int) {
        calendarMonth = Calendar.current.date(byAdding: .month, value: value, to: calendarMonth) ?? calendarMonth
    }

    func jumpToToday() {
        let today = Date()
        selectedCalendarDate = today
        calendarMonth = today
    }

    func monthTitle(_ date: Date) -> String {
        DailyLogDateFormatters.monthTitle.string(from: date)
    }

    func dayTitle(_ date: Date) -> String {
        DailyLogDateFormatters.dayTitle.string(from: date)
    }

    func clearDraft() {
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

    func startEdit(_ log: DailyLog) {
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

    func openFocusedLogIfNeeded() {
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

    func saveEditedLog() {
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
        store.updateDailyLog(log)
        store.scheduleSave()
    }

    func copyLogToToday(_ log: DailyLog) {
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

    func generateTomorrowPlanFromTodos(for projectId: UUID?) -> String {
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
    func constructionMethodLinkSection(selection: Binding<Set<UUID>>) -> some View {
        Section(String(localized: "关联施工工艺")) {
            if store.constructionMethods.isEmpty {
                Text(String(localized: "暂无工艺条目，可先在工具箱-施工工艺库新增"))
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

    func methodSelectionBinding(_ id: UUID, selection: Binding<Set<UUID>>) -> Binding<Bool> {
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

    func constructionMethodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? String(localized: "未命名工艺") : title
    }

    func linkedMethodTitles(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.constructionMethods.map { ($0.id, constructionMethodTitle($0)) })
        return ids.compactMap { lookup[$0] }
    }

    func sortedLinkedMethodIDs(_ selectedIDs: Set<UUID>) -> [UUID] {
        store.constructionMethods
            .map(\.id)
            .filter { selectedIDs.contains($0) }
    }

    func applyDailyLogTemplate(_ template: ProjectTemplate) {
        composer.content = template.content
    }

    func appendCameraPhoto(_ image: UIImage, capturedAt: Date) {
        guard composer.photoDrafts.count < 6,
              let normalizedData = ImageDownsampleService.downsampledJPEGData(
                image,
                maxPixelSize: 1600,
                sourceCompressionQuality: 0.82,
                compressionQuality: 0.8
              ) else { return }
        composer.photoDrafts.append(
            PhotoDraft(
                data: normalizedData,
                note: logWatermarkPhotoNote(capturedAt: capturedAt),
                tag: composer.cameraPhotoTag
            )
        )
    }

    func logWatermarkPhotoNote(capturedAt: Date) -> String {
        [
            String(localized: "来源: 拍照"),
            String(format: String(localized: "拍摄时间: %@"), Formatters.dateTime.string(from: capturedAt)),
            String(format: String(localized: "标签: %@"), composer.cameraPhotoTag.displayName)
        ].compactMap { $0 }.joined(separator: "\n")
    }

    var canSaveLog: Bool {
        let contentReady = !composer.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let workersReady = composer.workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || InputValidator.nonNegativeNumber(composer.workers)
        return contentReady && workersReady
    }
}
