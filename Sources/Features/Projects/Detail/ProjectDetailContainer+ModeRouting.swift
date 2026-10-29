import SwiftUI

extension ProjectDetailContainer {
    func openMode(_ mode: ProjectDetailMode, prefersInlineSections: Bool, isUserInitiated: Bool = true) {
        routeState.selectMode(mode, anchor: anchor(for: mode), prefersInlineSections: prefersInlineSections,
                              isUserInitiated: isUserInitiated)
    }

    func syncSingleCanvasAnchorIfNeeded(for mode: ProjectDetailMode) {
        guard usesSingleCanvasLayoutOnPad else { return }
        routeState.requestAnchorScroll(anchor(for: mode))
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

}
