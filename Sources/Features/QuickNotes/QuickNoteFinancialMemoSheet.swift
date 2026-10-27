import SwiftUI

struct QuickNoteFinancialMemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projectId: UUID
    let initialNote: String
    let onSave: (ProjectFinancialRecord) -> Void

    @State private var date = Date()
    @State private var direction: ProjectFinancialDirection = .expense
    @State private var category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var invoiceNumber = ""
    @State private var note: String

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    init(projectId: UUID, initialNote: String, onSave: @escaping (ProjectFinancialRecord) -> Void) {
        self.projectId = projectId
        self.initialNote = initialNote
        self.onSave = onSave
        _note = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("账目")) {
                    DatePicker(AppLocalization.string("日期"), selection: $date, displayedComponents: .date)
                    Picker(AppLocalization.string("类型"), selection: $direction) {
                        ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(AppLocalization.string("分类"), selection: $category) {
                        ForEach(availableCategories, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField(AppLocalization.string("金额"), text: $amount)
                        .keyboardType(.decimalPad)
                    TextField(AppLocalization.string("对方单位/个人"), text: $counterparty)
                    TextField(AppLocalization.string("发票号/收据号"), text: $invoiceNumber)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Text(AppLocalization.string("随手记不会再直接生成空金额流水。补齐金额后才会写入项目财务。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(AppLocalization.string("转为项目记账"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: direction) { _, newDirection in
                category = ProjectFinancialCategory.normalized(category, for: newDirection)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        onSave(ProjectFinancialRecord(
                            projectId: projectId,
                            date: .day(CalendarDay(date: date)),
                            direction: direction,
                            category: category,
                            amount: NumericInputSupport.money(amount),
                            counterparty: counterparty,
                            invoiceNumber: invoiceNumber,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(!InputValidator.nonNegativeNumber(amount) || !NumericInputSupport.money(amount).isPositive)
                }
            }
        }
    }
}
