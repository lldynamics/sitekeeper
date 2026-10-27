import SwiftUI

struct ProjectDocumentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserPreferenceKeys.userName) private var preferredOperatorName = ""
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
    let projectDocuments: [ProjectDocument]
    let constructionMethods: [ConstructionMethod]
    let onPreview: (ProjectDocument) -> Void
    let onSave: (ProjectDocument) -> Void
    let onDelete: (ProjectDocument) -> Void

    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var statusActionRequiringInput: ProjectDocumentStatusQuickAction?
    @State private var localDocument: ProjectDocument?

    private var displayedDocument: ProjectDocument {
        localDocument ?? document
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("资料")) {
                    LabeledContent(AppLocalization.string("名称"), value: displayedDocument.title)
                    LabeledContent(AppLocalization.string("类型"), value: displayedDocument.category.displayName)
                    LabeledContent(AppLocalization.string("版本"), value: displayedDocument.versionDisplayText)
                    if let previousVersion = versionReferenceText(for: displayedDocument.replacesDocumentId) {
                        LabeledContent(AppLocalization.string("替换上一版"), value: previousVersion)
                    }
                    if let nextVersion = versionReferenceText(for: displayedDocument.replacedByDocumentId) {
                        LabeledContent(AppLocalization.string("后续版本"), value: nextVersion)
                    }
                    LabeledContent(AppLocalization.string("报验状态"), value: displayedDocument.submissionStatus.displayName)
                    LabeledContent(AppLocalization.string("页数"), value: "\(displayedDocument.pageCount)")
                    if displayedDocument.amount.isPositive {
                        LabeledContent(AppLocalization.string("金额"), value: ReportBuilder.money(displayedDocument.amount))
                    }
                    if !displayedDocument.formedAt.isEmpty {
                        LabeledContent(AppLocalization.string("形成日期"), value: displayedDocument.formedAt)
                    }
                    if !displayedDocument.responsiblePerson.isEmpty {
                        LabeledContent(AppLocalization.string("责任人"), value: displayedDocument.responsiblePerson)
                    }
                    if !displayedDocument.workSection.isEmpty {
                        LabeledContent(AppLocalization.string("分部/工序"), value: displayedDocument.workSection)
                    }
                    if !displayedDocument.archiveNumber.isEmpty {
                        LabeledContent(AppLocalization.string("归档编号"), value: displayedDocument.archiveNumber)
                    }
                    LabeledContent(AppLocalization.string("创建时间"), value: Formatters.displayDateText(displayedDocument.createdAt))
                    if !linkedMethodTitles.isEmpty {
                        LabeledContent(AppLocalization.string("关联工艺"), value: linkedMethodTitles.joined(separator: "、"))
                    }
                    if !displayedDocument.note.isEmpty {
                        Text(displayedDocument.note)
                    }
                }
                Section(AppLocalization.string("状态流转")) {
                    ForEach(ProjectDocumentStatusQuickAction.allCases) { action in
                        Button {
                            handleStatusAction(action)
                        } label: {
                            HStack {
                                Label(action.title, systemImage: action.systemImage)
                                Spacer()
                                if displayedDocument.submissionStatus == action.status {
                                    Text(AppLocalization.string("当前"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(displayedDocument.submissionStatus == action.status)
                        .foregroundStyle(
                            displayedDocument.submissionStatus == action.status
                            ? Color.secondary
                            : action.tint
                        )
                    }
                }
                Section(AppLocalization.string("流转记录")) {
                    if displayedDocument.statusHistory.isEmpty {
                        Text(AppLocalization.string("暂无状态流转记录"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedDocument.statusHistory.reversed()) { entry in
                            statusHistoryRow(entry)
                        }
                    }
                }
                Section {
                    Button {
                        onPreview(displayedDocument)
                    } label: {
                        Label(AppLocalization.string("预览扫描件"), systemImage: "eye.fill")
                    }
                    Button {
                        showEditSheet = true
                    } label: {
                        Label(AppLocalization.string("编辑资料"), systemImage: "square.and.pencil")
                    }
                    Button(AppLocalization.string("删除扫描件"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(AppLocalization.string("扫描件详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("关闭")) { dismiss() }
                }
            }
            .alert(AppLocalization.string("删除这份扫描件？"), isPresented: $showDeleteConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
                Button(AppLocalization.string("删除"), role: .destructive) {
                    onDelete(displayedDocument)
                    dismiss()
                }
            } message: {
                Text(AppLocalization.string("删除后，关联账目的附件标记会同步清除。"))
            }
            .sheet(isPresented: $showEditSheet) {
                ProjectDocumentEditSheet(
                    document: displayedDocument,
                    financialRecords: financialRecords,
                    projectDocuments: projectDocuments,
                    constructionMethods: constructionMethods
                ) { updated in
                    localDocument = updated
                    onSave(updated)
                }
            }
            .sheet(item: $statusActionRequiringInput) { action in
                ProjectDocumentStatusChangeSheet(
                    fromStatus: displayedDocument.submissionStatus,
                    toStatus: action.status,
                    defaultOperatorName: defaultStatusOperatorName,
                    requiresReason: action.requiresReason
                ) { operatorName, reason in
                    applyStatus(action.status, operatorName: operatorName, reason: reason)
                }
            }
        }
    }

    private var linkedMethodTitles: [String] {
        guard !displayedDocument.linkedConstructionMethodIDs.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: constructionMethods.map { method in
            (method.id, methodTitle(method))
        })
        return displayedDocument.linkedConstructionMethodIDs.compactMap { lookup[$0] }
    }

    private func versionReferenceText(for id: UUID?) -> String? {
        guard let id else { return nil }
        guard let document = projectDocuments.first(where: { $0.id == id }) else {
            return "\(AppLocalization.string("资料ID")) \(String(id.uuidString.prefix(8)))"
        }
        return versionReferenceLabel(document)
    }

    private func versionReferenceLabel(_ document: ProjectDocument) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? document.fileName : title
        return "\(document.versionDisplayText) · \(document.category.displayName) · \(displayTitle)"
    }

    @ViewBuilder
    private func statusHistoryRow(_ entry: ProjectDocumentStatusHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.appPrimaryAction)
                Text("\(entry.fromStatus.displayName) → \(entry.toStatus.displayName)")
                    .font(.callout.weight(.semibold))
                Spacer()
            }
            HStack(spacing: 8) {
                Label(Formatters.displayDateText(entry.changedAt), systemImage: "clock")
                if !entry.displayOperatorName.isEmpty {
                    Label(entry.displayOperatorName, systemImage: "person.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func handleStatusAction(_ action: ProjectDocumentStatusQuickAction) {
        guard displayedDocument.submissionStatus != action.status else { return }
        if action.requiresReason {
            statusActionRequiringInput = action
        } else {
            applyStatus(action.status, operatorName: defaultStatusOperatorName)
        }
    }

    private func applyStatus(
        _ status: ProjectDocumentSubmissionStatus,
        operatorName: String,
        reason: String = ""
    ) {
        guard displayedDocument.submissionStatus != status else { return }
        let normalizedOperator = operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = displayedDocument
        let previousStatus = updated.submissionStatus
        updated.submissionStatus = status
        updated.statusHistory.append(ProjectDocumentStatusHistoryEntry(
            fromStatus: previousStatus,
            toStatus: status,
            operatorName: normalizedOperator.isEmpty ? defaultStatusOperatorName : normalizedOperator,
            reason: normalizedReason
        ))
        localDocument = updated
        onSave(updated)
    }

    private var defaultStatusOperatorName: String {
        let normalized = preferredOperatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? AppLocalization.string("现场操作") : normalized
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? AppLocalization.string("未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }
}

private enum ProjectDocumentStatusQuickAction: CaseIterable, Identifiable {
    case pending
    case submitted
    case returned
    case archived

    var id: ProjectDocumentSubmissionStatus { status }

    var status: ProjectDocumentSubmissionStatus {
        switch self {
        case .pending: return .pending
        case .submitted: return .submitted
        case .returned: return .returned
        case .archived: return .archived
        }
    }

    var title: String {
        switch self {
        case .pending: return AppLocalization.string("设为待报验")
        case .submitted: return AppLocalization.string("设为已报验")
        case .returned: return AppLocalization.string("退回修改")
        case .archived: return AppLocalization.string("设为已归档")
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "clock.badge.exclamationmark"
        case .submitted: return "paperplane.fill"
        case .returned: return "arrow.uturn.backward.circle.fill"
        case .archived: return "archivebox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .appWarning
        case .submitted: return .appPrimaryAction
        case .returned: return .appRisk
        case .archived: return .appSuccess
        }
    }

    var requiresReason: Bool {
        switch self {
        case .returned:
            return true
        case .pending, .submitted, .archived:
            return false
        }
    }
}

private struct ProjectDocumentStatusChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fromStatus: ProjectDocumentSubmissionStatus
    let toStatus: ProjectDocumentSubmissionStatus
    let defaultOperatorName: String
    let requiresReason: Bool
    let onConfirm: (String, String) -> Void

    @State private var operatorName: String
    @State private var reason = ""
    @FocusState private var isInputFocused: Bool

    init(
        fromStatus: ProjectDocumentSubmissionStatus,
        toStatus: ProjectDocumentSubmissionStatus,
        defaultOperatorName: String,
        requiresReason: Bool,
        onConfirm: @escaping (String, String) -> Void
    ) {
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.defaultOperatorName = defaultOperatorName
        self.requiresReason = requiresReason
        self.onConfirm = onConfirm
        _operatorName = State(initialValue: defaultOperatorName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("流转信息")) {
                    LabeledContent(AppLocalization.string("原状态"), value: fromStatus.displayName)
                    LabeledContent(AppLocalization.string("新状态"), value: toStatus.displayName)
                    TextField(AppLocalization.string("操作人"), text: $operatorName)
                        .focused($isInputFocused)
                    if requiresReason {
                        TextField(AppLocalization.string("退回原因"), text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($isInputFocused)
                    }
                }
            }
            .navigationTitle(AppLocalization.string("记录状态流转"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        isInputFocused = false
                        onConfirm(operatorName, reason)
                        dismiss()
                    }
                }
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }
}

private extension ProjectDocumentStatusHistoryEntry {
    var displayOperatorName: String {
        operatorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
