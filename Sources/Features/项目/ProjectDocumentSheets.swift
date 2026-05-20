import SwiftUI

struct ProjectDocumentScanSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let constructionMethods: [ConstructionMethod]
    let onScan: (ProjectScanTarget) -> Void

    @State private var title = ""
    @State private var category: ProjectDocumentCategory
    @State private var amount = ""
    @State private var submissionStatus: ProjectDocumentSubmissionStatus = .notSubmitted
    @State private var responsiblePerson = ""
    @State private var hasFormedAt = true
    @State private var formedAtDate = Date()
    @State private var archiveNumber = ""
    @State private var workSection = ""
    @State private var note = ""
    @State private var linkedMethodIDs: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    init(
        projectId: UUID,
        constructionMethods: [ConstructionMethod],
        initialCategory: ProjectDocumentCategory = .constructionRecord,
        onScan: @escaping (ProjectScanTarget) -> Void
    ) {
        self.projectId = projectId
        self.constructionMethods = constructionMethods
        self.onScan = onScan
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "扫描资料")) {
                    Text(String(localized: "扫描后会自动压缩（长边约 1800px，JPEG 质量约 0.7）以控制备份体积。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "资料名称"), text: $title)
                        .focused($isInputFocused)
                    Picker(String(localized: "资料类型"), selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "关联金额（元，可选）"), text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                }
                Section(String(localized: "台账信息")) {
                    Picker(String(localized: "报验状态"), selection: $submissionStatus) {
                        ForEach(ProjectDocumentSubmissionStatus.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "责任人"), text: $responsiblePerson)
                        .focused($isInputFocused)
                    Toggle(String(localized: "填写形成日期"), isOn: $hasFormedAt)
                    if hasFormedAt {
                        DatePicker(
                            String(localized: "形成日期"),
                            selection: $formedAtDate,
                            displayedComponents: .date
                        )
                    }
                    TextField(String(localized: "分部/工序"), text: $workSection)
                        .focused($isInputFocused)
                    TextField(String(localized: "归档编号"), text: $archiveNumber)
                        .focused($isInputFocused)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }
                Section(String(localized: "关联施工工艺")) {
                    if constructionMethods.isEmpty {
                        Text(String(localized: "暂无可关联的施工工艺，请先到工具箱维护工艺库。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constructionMethods) { method in
                            Toggle(methodTitle(method), isOn: methodBinding(for: method.id))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "扫描项目资料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "开始扫描")) {
                        isInputFocused = false
                        onScan(ProjectScanTarget(
                            title: title,
                            category: category,
                            amount: amount,
                            linkedFinancialRecordId: nil,
                            linkedConstructionMethodIDs: sortedLinkedMethodIDs(),
                            submissionStatus: submissionStatus,
                            responsiblePerson: responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines),
                            formedAt: formattedFormedAt,
                            archiveNumber: archiveNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                            workSection: workSection.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(!amount.isEmpty && !InputValidator.nonNegativeNumber(amount))
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isLinked in
                if isLinked {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? String(localized: "未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }

    private var formattedFormedAt: String {
        hasFormedAt ? Formatters.date.string(from: formedAtDate) : ""
    }
}

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
                Section(String(localized: "资料")) {
                    LabeledContent(String(localized: "名称"), value: displayedDocument.title)
                    LabeledContent(String(localized: "类型"), value: displayedDocument.category.displayName)
                    LabeledContent(String(localized: "版本"), value: displayedDocument.versionDisplayText)
                    if let previousVersion = versionReferenceText(for: displayedDocument.replacesDocumentId) {
                        LabeledContent(String(localized: "替换上一版"), value: previousVersion)
                    }
                    if let nextVersion = versionReferenceText(for: displayedDocument.replacedByDocumentId) {
                        LabeledContent(String(localized: "后续版本"), value: nextVersion)
                    }
                    LabeledContent(String(localized: "报验状态"), value: displayedDocument.submissionStatus.displayName)
                    LabeledContent(String(localized: "页数"), value: "\(displayedDocument.pageCount)")
                    if displayedDocument.amountValue.isPositive {
                        LabeledContent(String(localized: "金额"), value: ReportBuilder.money(displayedDocument.amountValue.doubleValue))
                    }
                    if !displayedDocument.formedAt.isEmpty {
                        LabeledContent(String(localized: "形成日期"), value: displayedDocument.formedAt)
                    }
                    if !displayedDocument.responsiblePerson.isEmpty {
                        LabeledContent(String(localized: "责任人"), value: displayedDocument.responsiblePerson)
                    }
                    if !displayedDocument.workSection.isEmpty {
                        LabeledContent(String(localized: "分部/工序"), value: displayedDocument.workSection)
                    }
                    if !displayedDocument.archiveNumber.isEmpty {
                        LabeledContent(String(localized: "归档编号"), value: displayedDocument.archiveNumber)
                    }
                    LabeledContent(String(localized: "创建时间"), value: displayedDocument.createdAt)
                    if !linkedMethodTitles.isEmpty {
                        LabeledContent(String(localized: "关联工艺"), value: linkedMethodTitles.joined(separator: "、"))
                    }
                    if !displayedDocument.note.isEmpty {
                        Text(displayedDocument.note)
                    }
                }
                Section(String(localized: "状态流转")) {
                    ForEach(ProjectDocumentStatusQuickAction.allCases) { action in
                        Button {
                            handleStatusAction(action)
                        } label: {
                            HStack {
                                Label(action.title, systemImage: action.systemImage)
                                Spacer()
                                if displayedDocument.submissionStatus == action.status {
                                    Text(String(localized: "当前"))
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
                Section(String(localized: "流转记录")) {
                    if displayedDocument.statusHistory.isEmpty {
                        Text(String(localized: "暂无状态流转记录"))
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
                        Label(String(localized: "预览扫描件"), systemImage: "eye.fill")
                    }
                    Button {
                        showEditSheet = true
                    } label: {
                        Label(String(localized: "编辑资料"), systemImage: "square.and.pencil")
                    }
                    Button(String(localized: "删除扫描件"), role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "扫描件详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .alert(String(localized: "删除这份扫描件？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
                    onDelete(displayedDocument)
                    dismiss()
                }
            } message: {
                Text(String(localized: "删除后，关联账目的附件标记会同步清除。"))
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
            return "\(String(localized: "资料ID")) \(String(id.uuidString.prefix(8)))"
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
                Label(entry.changedAt, systemImage: "clock")
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
        return normalized.isEmpty ? String(localized: "现场操作") : normalized
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? String(localized: "未命名工艺") : title
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
        case .pending: return String(localized: "设为待报验")
        case .submitted: return String(localized: "设为已报验")
        case .returned: return String(localized: "退回修改")
        case .archived: return String(localized: "设为已归档")
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
                Section(String(localized: "流转信息")) {
                    LabeledContent(String(localized: "原状态"), value: fromStatus.displayName)
                    LabeledContent(String(localized: "新状态"), value: toStatus.displayName)
                    TextField(String(localized: "操作人"), text: $operatorName)
                        .focused($isInputFocused)
                    if requiresReason {
                        TextField(String(localized: "退回原因"), text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($isInputFocused)
                    }
                }
            }
            .navigationTitle(String(localized: "记录状态流转"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        isInputFocused = false
                        onConfirm(operatorName, reason)
                        dismiss()
                    }
                }
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

enum ProjectDocumentFormDate {
    static func date(from text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Formatters.date.date(from: normalized) ?? Formatters.dateTime.date(from: normalized)
    }
}

struct ProjectDocumentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserPreferenceKeys.userName) private var preferredOperatorName = ""
    let document: ProjectDocument
    let financialRecords: [ProjectFinancialRecord]
    let projectDocuments: [ProjectDocument]
    let constructionMethods: [ConstructionMethod]
    let onSave: (ProjectDocument) -> Void

    @State private var title: String
    @State private var category: ProjectDocumentCategory
    @State private var amount: String
    @State private var versionNumber: Int
    @State private var versionState: ProjectDocumentVersionState
    @State private var replacesDocumentId: UUID?
    @State private var submissionStatus: ProjectDocumentSubmissionStatus
    @State private var responsiblePerson: String
    @State private var hasFormedAt: Bool
    @State private var formedAtDate: Date
    @State private var archiveNumber: String
    @State private var workSection: String
    @State private var note: String
    @State private var linkedFinancialRecordId: UUID?
    @State private var linkedMethodIDs: Set<UUID>
    @FocusState private var isInputFocused: Bool

    init(
        document: ProjectDocument,
        financialRecords: [ProjectFinancialRecord],
        projectDocuments: [ProjectDocument],
        constructionMethods: [ConstructionMethod],
        onSave: @escaping (ProjectDocument) -> Void
    ) {
        self.document = document
        self.financialRecords = financialRecords
        self.projectDocuments = projectDocuments
        self.constructionMethods = constructionMethods
        self.onSave = onSave
        _title = State(initialValue: document.title)
        _category = State(initialValue: document.category)
        _amount = State(initialValue: document.amount)
        _versionNumber = State(initialValue: document.normalizedVersionNumber)
        _versionState = State(initialValue: document.versionState)
        _replacesDocumentId = State(initialValue: document.replacesDocumentId)
        _submissionStatus = State(initialValue: document.submissionStatus)
        _responsiblePerson = State(initialValue: document.responsiblePerson)
        let normalizedFormedAt = document.formedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        _hasFormedAt = State(initialValue: !normalizedFormedAt.isEmpty)
        _formedAtDate = State(initialValue: ProjectDocumentFormDate.date(from: normalizedFormedAt) ?? Date())
        _archiveNumber = State(initialValue: document.archiveNumber)
        _workSection = State(initialValue: document.workSection)
        _note = State(initialValue: document.note)
        _linkedFinancialRecordId = State(initialValue: document.linkedFinancialRecordId)
        _linkedMethodIDs = State(initialValue: Set(document.linkedConstructionMethodIDs))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "资料信息")) {
                    TextField(String(localized: "资料名称"), text: $title)
                        .focused($isInputFocused)
                    Picker(String(localized: "资料类型"), selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "关联金额（元，可选）"), text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                }

                Section(String(localized: "版本管理")) {
                    Stepper(value: $versionNumber, in: 1...999) {
                        LabeledContent(String(localized: "版本号"), value: "V\(versionNumber)")
                    }
                    Picker(String(localized: "版本状态"), selection: $versionState) {
                        ForEach(ProjectDocumentVersionState.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Picker(String(localized: "替换上一版"), selection: $replacesDocumentId) {
                        Text(String(localized: "不替换")).tag(nil as UUID?)
                        ForEach(versionCandidates) { item in
                            Text(versionReferenceLabel(item)).tag(item.id as UUID?)
                        }
                    }
                    if let previousVersion = selectedPreviousVersion {
                        Text(String(format: String(localized: "保存后会把 %@ 标记为已替换。"), versionReferenceLabel(previousVersion)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "台账信息")) {
                    Picker(String(localized: "报验状态"), selection: $submissionStatus) {
                        ForEach(ProjectDocumentSubmissionStatus.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(String(localized: "责任人"), text: $responsiblePerson)
                        .focused($isInputFocused)
                    Toggle(String(localized: "填写形成日期"), isOn: $hasFormedAt)
                    if hasFormedAt {
                        DatePicker(
                            String(localized: "形成日期"),
                            selection: $formedAtDate,
                            displayedComponents: .date
                        )
                    }
                    TextField(String(localized: "分部/工序"), text: $workSection)
                        .focused($isInputFocused)
                    TextField(String(localized: "归档编号"), text: $archiveNumber)
                        .focused($isInputFocused)
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }

                Section(String(localized: "关联账目")) {
                    Picker(String(localized: "账目"), selection: $linkedFinancialRecordId) {
                        Text(String(localized: "不关联")).tag(nil as UUID?)
                        ForEach(financialRecords) { item in
                            Text(recordLabel(item)).tag(item.id as UUID?)
                        }
                    }
                }

                Section(String(localized: "关联施工工艺")) {
                    if constructionMethods.isEmpty {
                        Text(String(localized: "暂无可关联的施工工艺，请先到工具箱维护工艺库。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constructionMethods) { method in
                            Toggle(methodTitle(method), isOn: methodBinding(for: method.id))
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "编辑资料"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: replacesDocumentId) { _, _ in
                syncVersionNumberWithSelectedPrevious()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        isInputFocused = false
                        onSave(updatedDocument)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!amount.isEmpty && !InputValidator.nonNegativeNumber(amount)))
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }

    private func recordLabel(_ record: ProjectFinancialRecord) -> String {
        let money = ReportBuilder.money(record.amountValue.doubleValue)
        return "\(record.date) · \(record.direction.displayName) \(money)"
    }

    private var updatedDocument: ProjectDocument {
        var value = document
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category
        value.amount = amount
        value.versionNumber = max(1, versionNumber)
        value.versionState = versionState
        value.replacesDocumentId = replacesDocumentId == document.id ? nil : replacesDocumentId
        value.submissionStatus = submissionStatus
        value.responsiblePerson = responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines)
        value.formedAt = hasFormedAt ? Formatters.date.string(from: formedAtDate) : ""
        value.archiveNumber = archiveNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        value.workSection = workSection.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.linkedFinancialRecordId = linkedFinancialRecordId
        value.linkedConstructionMethodIDs = sortedLinkedMethodIDs()
        if document.submissionStatus != submissionStatus {
            value.statusHistory.append(ProjectDocumentStatusHistoryEntry(
                fromStatus: document.submissionStatus,
                toStatus: submissionStatus,
                operatorName: defaultStatusOperatorName
            ))
        }
        return value
    }

    private var defaultStatusOperatorName: String {
        let normalized = preferredOperatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? String(localized: "现场操作") : normalized
    }

    private var versionCandidates: [ProjectDocument] {
        projectDocuments
            .filter { $0.projectId == document.projectId && $0.id != document.id }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private var selectedPreviousVersion: ProjectDocument? {
        guard let replacesDocumentId else { return nil }
        return versionCandidates.first { $0.id == replacesDocumentId }
    }

    private func versionReferenceLabel(_ document: ProjectDocument) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? document.fileName : title
        return "\(document.versionDisplayText) · \(document.category.displayName) · \(displayTitle)"
    }

    private func syncVersionNumberWithSelectedPrevious() {
        guard let selectedPreviousVersion else { return }
        let suggestedNumber = min(999, selectedPreviousVersion.normalizedVersionNumber + 1)
        if versionNumber < suggestedNumber {
            versionNumber = suggestedNumber
        }
    }

    private func methodBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { linkedMethodIDs.contains(id) },
            set: { isLinked in
                if isLinked {
                    linkedMethodIDs.insert(id)
                } else {
                    linkedMethodIDs.remove(id)
                }
            }
        )
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? String(localized: "未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }
}
