import SwiftUI

enum ProjectDocumentFormDate {
    static func date(from value: BusinessDateValue) -> Date? { value.date() }
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
    @State private var formedAtDate: BusinessDateValue
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
        _amount = State(initialValue: document.amount.wireText)
        _versionNumber = State(initialValue: document.normalizedVersionNumber)
        _versionState = State(initialValue: document.versionState)
        _replacesDocumentId = State(initialValue: document.replacesDocumentId)
        _submissionStatus = State(initialValue: document.submissionStatus)
        _responsiblePerson = State(initialValue: document.responsiblePerson)
        let normalizedFormedAt = document.formedAt
        _hasFormedAt = State(initialValue: !normalizedFormedAt.isEmpty)
        _formedAtDate = State(initialValue: normalizedFormedAt)
        _archiveNumber = State(initialValue: document.archiveNumber)
        _workSection = State(initialValue: document.workSection)
        _note = State(initialValue: document.note)
        _linkedFinancialRecordId = State(initialValue: document.linkedFinancialRecordId)
        _linkedMethodIDs = State(initialValue: Set(document.linkedConstructionMethodIDs))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("资料信息")) {
                    TextField(AppLocalization.string("资料名称"), text: $title)
                        .focused($isInputFocused)
                    Picker(AppLocalization.string("资料类型"), selection: $category) {
                        ForEach(ProjectDocumentCategory.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(AppLocalization.string("关联金额（元，可选）"), text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                }

                Section(AppLocalization.string("版本管理")) {
                    Stepper(value: $versionNumber, in: 1...999) {
                        LabeledContent(AppLocalization.string("版本号"), value: "V\(versionNumber)")
                    }
                    Picker(AppLocalization.string("版本状态"), selection: $versionState) {
                        ForEach(ProjectDocumentVersionState.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    Picker(AppLocalization.string("替换上一版"), selection: $replacesDocumentId) {
                        Text(AppLocalization.string("不替换")).tag(nil as UUID?)
                        ForEach(versionCandidates) { item in
                            Text(versionReferenceLabel(item)).tag(item.id as UUID?)
                        }
                    }
                    if let previousVersion = selectedPreviousVersion {
                        Text(String(format: AppLocalization.string("保存后会把 %@ 标记为已替换。"), versionReferenceLabel(previousVersion)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(AppLocalization.string("台账信息")) {
                    Picker(AppLocalization.string("报验状态"), selection: $submissionStatus) {
                        ForEach(ProjectDocumentSubmissionStatus.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(AppLocalization.string("责任人"), text: $responsiblePerson)
                        .focused($isInputFocused)
                    Toggle(AppLocalization.string("填写形成日期"), isOn: $hasFormedAt)
                    if hasFormedAt {
                        DatePicker(
                            AppLocalization.string("形成日期"),
                            selection: $formedAtDate.daySelection,
                            displayedComponents: .date
                        )
                    }
                    TextField(AppLocalization.string("分部/工序"), text: $workSection)
                        .focused($isInputFocused)
                    TextField(AppLocalization.string("归档编号"), text: $archiveNumber)
                        .focused($isInputFocused)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                }

                Section(AppLocalization.string("关联账目")) {
                    Picker(AppLocalization.string("账目"), selection: $linkedFinancialRecordId) {
                        Text(AppLocalization.string("不关联")).tag(nil as UUID?)
                        ForEach(financialRecords) { item in
                            Text(recordLabel(item)).tag(item.id as UUID?)
                        }
                    }
                }

                Section(AppLocalization.string("关联施工工艺")) {
                    if constructionMethods.isEmpty {
                        Text(AppLocalization.string("暂无可关联的施工工艺，请先到工具箱维护工艺库。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(constructionMethods) { method in
                            Toggle(methodTitle(method), isOn: methodBinding(for: method.id))
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.string("编辑资料"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: replacesDocumentId) { _, _ in
                syncVersionNumberWithSelectedPrevious()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        isInputFocused = false
                        onSave(updatedDocument)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (!amount.isEmpty && !InputValidator.nonNegativeNumber(amount)))
                }
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }

    private func recordLabel(_ record: ProjectFinancialRecord) -> String {
        let money = ReportBuilder.money(record.amount)
        return "\(Formatters.displayDateText(record.date)) · \(record.direction.displayName) \(money)"
    }

    private var updatedDocument: ProjectDocument {
        var value = document
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category
        value.amount = NumericInputSupport.money(amount)
        value.versionNumber = max(1, versionNumber)
        value.versionState = versionState
        value.replacesDocumentId = replacesDocumentId == document.id ? nil : replacesDocumentId
        value.submissionStatus = submissionStatus
        value.responsiblePerson = responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines)
        value.formedAt = hasFormedAt ? formedAtDate : .empty
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
        return normalized.isEmpty ? AppLocalization.string("现场操作") : normalized
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
        let displayTitle = title.isEmpty ? AppLocalization.string("未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }
}
