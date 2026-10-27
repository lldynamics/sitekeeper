import SwiftUI
import PhotosUI
import UIKit

struct DailyLogView: View {
    @Environment(\.dismiss) var dismissComposer
    @Environment(DataStore.self) var store
    @Environment(\.scenePhase) var draftScenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let standaloneComposer: Bool
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
    @State var draftRecordID = UUID()
    @State var draftScopeID: UUID?
    @State var draftLoaded = false
    @State var seedInputsApplied = false
    @State var draftCompleted = false
    @State var draftError: String?
    @State var isSavingLog = false
    @State var showDiscardLogDraft = false
    @State var pendingEditorDraft: DailyLogEditorState?
    @State var editorDraftReady = false
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
    @State var photoImportTask: Task<Void, Never>?
    @State var photoImportSession = DailyLogPhotoImportSession()
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()

    init(
        initialProjectId: UUID? = nil,
        standaloneComposer: Bool = false,
        autoOpenComposer: Bool = false,
        focusedLogId: UUID? = nil,
        initialPhotoDrafts: [DailyLogSeedPhoto] = [],
        initialContent: String = ""
    ) {
        self.standaloneComposer = standaloneComposer
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
        _draftScopeID = State(initialValue: initialProjectId)
    }

    let weatherOptions = ["晴", "多云", "阴", "小雨", "大雨", "雪"]
    let contentTemplates = [
        AppLocalization.string("完成今日计划施工，现场质量正常"),
        AppLocalization.string("完成线路敷设，待下一步复核"),
        AppLocalization.string("完成材料进场与现场整理")
    ]
    let safetyTemplates = [
        AppLocalization.string("已进行班前安全交底，未发现安全隐患"),
        AppLocalization.string("临边洞口已复查，临电使用正常"),
        AppLocalization.string("发现问题已现场整改并复核")
    ]
    let materialTemplates = [
        AppLocalization.string("主材已进场并完成清点"),
        AppLocalization.string("辅材已补齐，数量待复核"),
        AppLocalization.string("暂无新增材料进场")
    ]

    var body: some View {
        Group {
            if standaloneComposer {
                addLogForm
            } else {
                AppReviewWorkspace(primaryTitle: AppLocalization.string("施工日志"), secondaryTitle: AppLocalization.string("筛选")) {
                    compactLogLayout
                } secondary: {
                    List { splitFilterSection }
                }
            }
        }
        .navigationTitle(AppLocalization.string("施工日志"))
        .toolbar {
            logToolbar
        }
        .sheet(isPresented: $showDateFilter) {
            dateFilterSheet
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
            defaultFilename: exportPayload?.defaultFilename ?? AppLocalization.string("现场照片页.pdf")
        ) { result in
            handleExportCompletion(result)
        }
        .alert(AppLocalization.string("施工日志"), isPresented: $showAlert) {
            Button(AppLocalization.string("知道了"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .operationToast(notice: $operationNotice)
        .onAppear {
            restoreComposerDraft()
            openFocusedLogIfNeeded()
            guard autoOpenComposer, !didAutoOpenComposer else { return }
            didAutoOpenComposer = true
            showAdd = true
        }
        .onChange(of: composer.projectId) { _, projectID in switchComposerDraftScope(to: projectID) }
        .onChange(of: composerDraft) { _, _ in persistComposerDraft() }
        .onChange(of: editor) { _, _ in persistEditorDraft() }
        .onChange(of: draftScenePhase) { _, phase in
            if phase != .active { persistComposerDraft()
            persistEditorDraft() }
        }
        .onDisappear {
            persistComposerDraft()
            persistEditorDraft()
            photoWallExportTask?.cancel()
            photoWallExportTask = nil
            cancelPhotoImportAndResetSession()
            undoableDeletion.flushPendingCommit()
        }
        .onChange(of: showAdd) { _, isPresented in
            if isPresented, draftCompleted {
                draftCompleted = false
                draftLoaded = false
                restoreComposerDraft()
            }
            if !isPresented {
                persistComposerDraft()
                cancelPhotoImportAndResetSession()
            }
        }
    }
}
