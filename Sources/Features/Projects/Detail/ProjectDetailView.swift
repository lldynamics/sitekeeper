import SwiftUI

struct ProjectDetailView: View {
    let projectId: UUID
    let initialMode: ProjectDetailMode?
    let focus: ProjectDetailFocus?
    let autoOpenFinancialAdd: Bool
    let autoOpenDocumentScanSetup: Bool
    let autoOpenDeliveryGuide: Bool

    init(
        projectId: UUID,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false
    ) {
        self.projectId = projectId
        self.initialMode = initialMode
        self.focus = focus
        self.autoOpenFinancialAdd = autoOpenFinancialAdd
        self.autoOpenDocumentScanSetup = autoOpenDocumentScanSetup
        self.autoOpenDeliveryGuide = autoOpenDeliveryGuide
    }

    var body: some View {
        ProjectDetailContainer(
            projectId: projectId,
            initialMode: initialMode,
            focus: focus,
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide
        )
    }
}
