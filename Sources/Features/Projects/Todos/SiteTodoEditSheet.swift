import SwiftUI
import PhotosUI
import UIKit

struct SiteTodoEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(DataStore.self) var store
    @Environment(\.scenePhase) var scenePhase
    let todo: SiteTodo?
    let projects: [Project]
    let constructionMethods: [ConstructionMethod]
    let initialProjectId: UUID?
    let initialBeforePhotoData: Data?
    let initialAfterPhotoData: Data?
    let onSave: (SiteTodo) -> Void
    var onDelete: ((SiteTodo) -> Void)?

    @State var draft: SiteTodoFormDraft
    @State var beforePhotoData: Data?
    @State var afterPhotoData: Data?
    @State var beforePhotoItem: PhotosPickerItem?
    @State var afterPhotoItem: PhotosPickerItem?
    @State var beforePhotoImportTask: Task<Void, Never>?
    @State var afterPhotoImportTask: Task<Void, Never>?
    @State var draftLoaded = false
    @State var hasSavedDraft = false
    @State var draftCompleted = false
    @State var draftError: String?
    @State var pendingRestoration: SiteTodoFormDraft?
    @State var isSaving = false
    @State var showDeleteConfirm = false
    @State var showDiscardDraft = false

    init(
        todo: SiteTodo?, projects: [Project], constructionMethods: [ConstructionMethod], initialProjectId: UUID?,
        initialBeforePhotoData: Data? = nil, initialAfterPhotoData: Data? = nil,
        onSave: @escaping (SiteTodo) -> Void, onDelete: ((SiteTodo) -> Void)? = nil
    ) {
        self.todo = todo
        self.projects = projects
        self.constructionMethods = constructionMethods
        self.initialProjectId = initialProjectId
        self.initialBeforePhotoData = initialBeforePhotoData
        self.initialAfterPhotoData = initialAfterPhotoData
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: SiteTodoFormDraft(
            record: todo ?? SiteTodo(title: "", projectId: initialProjectId),
            baseRecord: todo.flatMap { BusinessDraftStore.fingerprint($0) }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                draftStatusSection
                Section(AppLocalization.string("事项")) {
                    TextField(AppLocalization.string("待办事项"), text: $draft.record.title, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("todo-draft-title")
                    TextField(AppLocalization.string("负责人"), text: $draft.record.owner)
                        .accessibilityIdentifier("todo-draft-owner")
                    DatePicker(AppLocalization.string("日期"), selection: $draft.record.dueDate.daySelection, displayedComponents: .date)
                    Picker(AppLocalization.string("优先级"), selection: $draft.record.priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker(AppLocalization.string("问题类型"), selection: $draft.record.issueType) {
                        ForEach(TodoIssueType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField(AppLocalization.string("备注"), text: $draft.record.note, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("todo-draft-note")
                }
                if showsDrawingIssueClosureFields { drawingIssueSection }
                methodSection
                Section(AppLocalization.string("归属项目")) {
                    Picker(AppLocalization.string("项目"), selection: $draft.record.projectId) {
                        Text(AppLocalization.string("不关联项目")).tag(nil as UUID?)
                        ForEach(projects) { Text($0.name).tag($0.id as UUID?) }
                    }
                }
                Section(AppLocalization.string("整改照片")) {
                    photoPickerRow(before: true)
                    photoPickerRow(before: false)
                }
                Section(AppLocalization.string("状态")) {
                    Toggle(AppLocalization.string("已完成"), isOn: $draft.record.isDone)
                    if let completedAt = draft.record.completedAt, draft.record.isDone {
                        LabeledContent(AppLocalization.string("完成时间"), value: completedAt)
                    }
                }
                if todo != nil {
                    Section {
                        Button(AppLocalization.string("删除待办"), role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(todo == nil ? AppLocalization.string("新增待办") : AppLocalization.string("编辑待办"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { persistDraft()
                    if draftError == nil { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存"), action: saveDraft)
                        .disabled(!draftLoaded || pendingRestoration != nil || draft.record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo-draft-save")
                }
            }
            .disabled(isSaving || isImportingPhoto)
            .interactiveDismissDisabled(isSaving || isImportingPhoto || draftError != nil)
            .confirmationDialog(AppLocalization.string("丢弃草稿？"), isPresented: $showDiscardDraft, titleVisibility: .visible) {
                Button(AppLocalization.string("丢弃草稿"), role: .destructive, action: discardDraft)
            }
            .alert(AppLocalization.string("删除这条待办？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
                Button(AppLocalization.string("删除"), role: .destructive) {
                    do {
                        try draftStore.discardTodo(key: draftKey, in: store)
                        draftCompleted = true
                        if let todo { onDelete?(todo) }
                        dismiss()
                    } catch { draftError = error.localizedDescription }
                }
            }
            .onChange(of: beforePhotoItem) { _, item in
                guard let item else { return }
                beforePhotoImportTask?.cancel()
                beforePhotoImportTask = Task { await importTodoPhoto(item, before: true) }
            }
            .onChange(of: afterPhotoItem) { _, item in
                guard let item else { return }
                afterPhotoImportTask?.cancel()
                afterPhotoImportTask = Task { await importTodoPhoto(item, before: false) }
            }
            .onChange(of: draft) { _, _ in persistDraft() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { persistDraft() } }
            .onAppear(perform: loadDraft)
            .onDisappear {
                persistDraft()
                beforePhotoImportTask?.cancel()
                afterPhotoImportTask?.cancel()
            }
        }
    }

    var showsDrawingIssueClosureFields: Bool {
        let record = draft.record
        let haystack = "\(record.title)\n\(record.note)"
        return !record.drawingIssueLocation.isEmpty || !record.drawingIssueLayerOrPage.isEmpty
            || !record.drawingIssueMeasurement.isEmpty || !record.drawingIssueCloseEvidence.isEmpty
            || haystack.localizedCaseInsensitiveContains(AppLocalization.string("图纸问题"))
            || haystack.localizedCaseInsensitiveContains("Drawing Issue")
    }

    private var drawingIssueSection: some View {
        Section(AppLocalization.string("图纸问题闭环")) {
            TextField(AppLocalization.string("问题位置"), text: $draft.record.drawingIssueLocation, axis: .vertical).lineLimit(1...3)
            TextField(AppLocalization.string("图层/页码"), text: $draft.record.drawingIssueLayerOrPage)
            TextField(AppLocalization.string("测量结果"), text: $draft.record.drawingIssueMeasurement, axis: .vertical).lineLimit(1...4)
            TextField(AppLocalization.string("关闭证据（验收人/复测/照片说明）"), text: $draft.record.drawingIssueCloseEvidence, axis: .vertical).lineLimit(1...4)
            Text(AppLocalization.string("整改后照片和关闭证据会进入交付包的图纸问题清单。"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var methodSection: some View {
        Section(AppLocalization.string("关联施工工艺")) {
            if constructionMethods.isEmpty {
                Text(AppLocalization.string("暂无工艺条目，可先在工具箱-施工工艺库新增"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(constructionMethods) { method in
                    Toggle(isOn: Binding(
                        get: { draft.record.linkedConstructionMethodIDs.contains(method.id) },
                        set: { linked in
                            draft.record.linkedConstructionMethodIDs.removeAll { $0 == method.id }
                            if linked { draft.record.linkedConstructionMethodIDs.append(method.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.title.isEmpty ? AppLocalization.string("未命名工艺") : method.title)
                            Text([method.trade, method.versionName.isEmpty ? "V1" : method.versionName, method.publishStatus.displayName].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }
}
