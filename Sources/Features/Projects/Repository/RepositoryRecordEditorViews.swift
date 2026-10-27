import SwiftUI

struct RepositoryProjectEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<Project>

    init(session: RepositoryWorkspaceSession, id: UUID?) {
        self.session = session
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .projects, id: id,
            initial: Project(name: "", location: "", startDate: .day(CalendarDay(date: Date())))))
    }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("项目详情"),
            canSave: !editor.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, command: RepositoryCommand.putProject) {
            Section(AppLocalization.string("基本信息")) {
                TextField(AppLocalization.string("项目名称"), text: $editor.draft.name)
                    .accessibilityIdentifier("repository-project-name")
                TextField(AppLocalization.string("项目地址"), text: $editor.draft.location)
                Picker(AppLocalization.string("状态"), selection: $editor.draft.status) {
                    ForEach(ProjectStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField(AppLocalization.string("开工日期"), text: $editor.draft.startDate.dateInputText)
                TextField(AppLocalization.string("预计完工日期"), text: $editor.draft.expectedEndDate.dateInputText)
            }
            Section(AppLocalization.string("联系人")) {
                TextField(AppLocalization.string("客户名称"), text: $editor.draft.customerName)
                TextField(AppLocalization.string("客户电话"), text: $editor.draft.customerPhone)
                TextField(AppLocalization.string("负责人"), text: $editor.draft.managerName)
            }
        }
    }
}

struct RepositoryDailyLogEditorView: View {
    let session: RepositoryWorkspaceSession
    @State private var editor: RepositoryRecordEditor<DailyLog>

    init(session: RepositoryWorkspaceSession, projectID: UUID, id: UUID?) {
        self.session = session
        _editor = State(initialValue: RepositoryRecordEditor(repository: session.repository, collection: .dailyLogs, id: id,
            initial: DailyLog(date: .day(CalendarDay(date: Date())), weather: "", content: "", workers: NumericInputSupport.quantity(""), projectId: projectID)))
    }

    var body: some View {
        @Bindable var editor = editor
        RepositoryEditorForm(editor: editor, session: session, title: AppLocalization.string("施工日志"),
            canSave: !editor.draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !editor.draft.date.isEmpty,
            command: RepositoryCommand.putDailyLog) {
            Section(AppLocalization.string("施工记录")) {
                TextField(AppLocalization.string("日期"), text: $editor.draft.date.dateInputText)
                TextField(AppLocalization.string("天气"), text: $editor.draft.weather)
                TextField(AppLocalization.string("施工内容"), text: $editor.draft.content, axis: .vertical)
                    .accessibilityIdentifier("repository-log-content")
                TextField(AppLocalization.string("施工人数"), text: Binding(
                    get: { editor.draft.workers.wireText },
                    set: { editor.draft.workers = NumericInputSupport.quantity($0) }
                )).keyboardType(.numberPad)
                TextField(AppLocalization.string("安全记录"), text: $editor.draft.safety, axis: .vertical)
                TextField(AppLocalization.string("材料情况"), text: $editor.draft.materials, axis: .vertical)
                TextField(AppLocalization.string("明日计划"), text: $editor.draft.tomorrowPlan, axis: .vertical)
            }
            Section(AppLocalization.string("质量与确认")) {
                TextField(AppLocalization.string("质量问题"), text: $editor.draft.qualityIssue, axis: .vertical)
                TextField(AppLocalization.string("整改情况"), text: $editor.draft.rectification, axis: .vertical)
                TextField(AppLocalization.string("确认人"), text: $editor.draft.confirmer)
                Text(String(format: AppLocalization.string("保留 %lld 个照片引用、%lld 个工法关联"),
                            Int64(editor.draft.allPhotoFileNames.count), Int64(editor.draft.linkedConstructionMethodIDs.count)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RepositoryEditorForm<Value: Codable & Sendable, Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let editor: RepositoryRecordEditor<Value>
    let session: RepositoryWorkspaceSession
    let title: String
    let canSave: Bool
    let command: (Value) throws -> RepositoryCommand
    @ViewBuilder let content: () -> Content
    @State private var confirmDiscard = false
    @State private var confirmReload = false

    var body: some View {
        NavigationStack {
            Form {
                if editor.isLoaded { content().disabled(editor.isBusy) }
                if editor.isBusy { ProgressView() }
                if let message = editor.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button(AppLocalization.string("重新载入原记录")) { confirmReload = true }
                            .disabled(editor.isBusy)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { confirmDiscard = true }.disabled(editor.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        Task {
                            if await editor.save(command: command) { session.didCommit()
                            dismiss() }
                        }
                    }
                    .disabled(!editor.isLoaded || editor.isBusy || !canSave)
                    .accessibilityIdentifier("repository-editor-save")
                }
            }
            .task { if !editor.isLoaded { await editor.load() } }
            .confirmationDialog(AppLocalization.string("放弃当前编辑？"), isPresented: $confirmDiscard) {
                Button(AppLocalization.string("放弃编辑"), role: .destructive) { dismiss() }
            }
            .confirmationDialog(AppLocalization.string("重新载入会替换当前编辑内容。"), isPresented: $confirmReload) {
                Button(AppLocalization.string("重新载入原记录"), role: .destructive) { Task { await editor.load() } }
            }
        }
        .interactiveDismissDisabled()
    }
}
