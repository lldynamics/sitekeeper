import SwiftUI

extension ProjectDetailContainer {
    func openRecordsModeFromMetric() {
        openMode(.records, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    func openFinanceModeFromQuoteMetric() {
        openFinanceModeFromMetric(filter: .none)
    }

    func openTodoFilterFromMetric() {
        showTodoFilterView = true
    }

    func openFinanceModeFromMetric(filter: ProjectFinanceJumpFilter) {
        routeState.financeJumpFilter = filter
        openMode(.finance, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    func resetFinanceJumpFilter() {
        routeState.financeJumpFilter = .none
    }

    func updateProject(_ updated: Project) {
        guard store.updateProject(updated) else { return }
        store.scheduleSave()
    }
}
