import SwiftUI

struct CalculatorResultCard: View {
    @Environment(DataStore.self) var store

    let title: String
    let result: CalculationResult
    let copyText: String

    @State var copied = false
    @State var savedMessage: String?
    @State var savedDestination: CalculatorSavedProjectDestination?
    @State var activeDestination: CalculatorSavedProjectDestination?
    @State var selectedProjectId: UUID?
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
