import SwiftUI

struct CalculatorResultCard: View {
    @Environment(DataStore.self) var store
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let title: String
    let result: CalculationResult
    let copyText: String

    @State var savedToHistory = false
    @State var copied = false
    @State var savedMessage: String?
    @State var savedDestination: CalculatorSavedProjectDestination?
    @State var activeDestination: CalculatorSavedProjectDestination?
    @State var selectedProjectId: UUID?
    @State var pendingProjectDraft: CalculatorProjectDraftRequest?
    @State var saveMessageToken = UUID()
    @State var saveErrorMessage = ""
    @State var showSaveError = false

    init(
        title: String,
        result: CalculationResult,
        copyText: String? = nil
    ) {
        self.title = title
        self.result = result
        self.copyText = copyText ?? result.plainText(title: title)
    }
}

extension CalculatorResultCard {
    func projectDraftConfirmation(_ request: CalculatorProjectDraftRequest) -> some View {
        let project = store.projects.first { $0.id == request.projectId }
        let confirmationTitle = request.kind == .materialSheet
            ? calculatorLoc("核对材料单草稿") : calculatorLoc("核对报价项")
        return AppBusinessFormSheet(
            title: confirmationTitle,
            primaryActionTitle: calculatorLoc("确认生成"),
            isPrimaryActionDisabled: project == nil,
            onCancel: { pendingProjectDraft = nil },
            onPrimaryAction: { confirmProjectDraft(request) }
        ) {
            Section {
                if let project {
                    LabeledContent(calculatorLoc("目标工程"), value: project.name)
                        .accessibilityIdentifier("calculator-draft-project")
                } else {
                    Text(calculatorLoc("已选择的工程已不存在，请重新选择。"))
                        .foregroundStyle(.appWarning)
                }
                LabeledContent(calculatorLoc("名称"), value: title)
                LabeledContent(calculatorLoc("数量"), value: "1")
                LabeledContent(calculatorLoc("单位"), value: calculatorLoc("项"))
                LabeledContent(calculatorLoc("单价"), value: calculatorLoc("待填写"))
                Text(calculatorLoc("初始数量为 1 项，计算结果保留在备注中。请在生成后核对实际数量、单位和单价。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calculator-draft-review-notice")
            }
            Section(calculatorLoc("备注")) {
                Text(copyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum CalculatorProjectSelection {
    static func resolve(id: UUID?, availableIDs: [UUID]) -> UUID? {
        guard let id, availableIDs.contains(id) else { return nil }
        return id
    }
}

struct CalculatorProjectDraftRequest: Identifiable {
    enum Kind: Equatable, Sendable {
        case materialSheet
        case quoteItem
    }

    let id = UUID()
    let kind: Kind
    let projectId: UUID
}

struct CalculatorSavedProjectDestination: Identifiable, Hashable {
    let id = UUID()
    let projectId: UUID
    let mode: ProjectDetailMode
    let focus: ProjectDetailFocus?
    let actionTitle: String

    static func == (lhs: CalculatorSavedProjectDestination, rhs: CalculatorSavedProjectDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
