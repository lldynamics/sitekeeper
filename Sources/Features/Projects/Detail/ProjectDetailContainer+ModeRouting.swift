import SwiftUI

extension ProjectDetailContainer {
    func openMode(_ mode: ProjectDetailMode, prefersInlineSections: Bool) {
        routeState.mode = mode
        if prefersInlineSections {
            requestAnchorScrollIfNeeded(anchor(for: mode))
        }
    }

    func requestAnchorScroll(_ anchor: ProjectDetailAnchor) {
        routeState.anchorRequest = ProjectDetailAnchorRequest(anchor: anchor)
    }

    func syncSingleCanvasAnchorIfNeeded(for mode: ProjectDetailMode) {
        guard usesSingleCanvasLayoutOnPad else { return }
        requestAnchorScrollIfNeeded(anchor(for: mode))
    }

    func anchor(for mode: ProjectDetailMode) -> ProjectDetailAnchor {
        switch mode {
        case .overview:
            .overview
        case .records:
            .records
        case .assets:
            .assets
        case .finance:
            .finance
        case .timeline:
            .timeline
        }
    }

    func usesInlineDetailLayout(for availableWidth: CGFloat) -> Bool {
        _ = availableWidth
        return usesSingleCanvasLayoutOnPad
    }

    private func requestAnchorScrollIfNeeded(_ anchor: ProjectDetailAnchor) {
        if routeState.anchorRequest?.anchor != anchor {
            requestAnchorScroll(anchor)
        }
    }
}
