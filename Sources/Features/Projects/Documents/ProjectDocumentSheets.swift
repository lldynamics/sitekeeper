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
    @State private var formedAtDate = BusinessDateValue.today()
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
                Section(AppLocalization.string("扫描资料")) {
                    Text(AppLocalization.string("扫描后会自动压缩（长边约 1800px，JPEG 质量约 0.7）以控制备份体积。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
            .navigationTitle(AppLocalization.string("扫描项目资料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("开始扫描")) {
                        isInputFocused = false
                        onScan(ProjectScanTarget(
                            title: title,
                            category: category,
                            amount: NumericInputSupport.money(amount),
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
            }
            .appKeyboardToolbar {
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
        let displayTitle = title.isEmpty ? AppLocalization.string("未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func sortedLinkedMethodIDs() -> [UUID] {
        constructionMethods.map(\.id).filter { linkedMethodIDs.contains($0) }
    }

    private var formattedFormedAt: BusinessDateValue {
        hasFormedAt ? formedAtDate : .empty
    }
}
