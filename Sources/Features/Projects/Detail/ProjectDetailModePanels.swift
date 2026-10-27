import SwiftUI

struct CompactProjectDetailModeContent<Overview: View, Records: View, Assets: View, Finance: View, Timeline: View>: View {
    let mode: ProjectDetailMode
    @ViewBuilder let overview: () -> Overview
    @ViewBuilder let records: () -> Records
    @ViewBuilder let assets: () -> Assets
    @ViewBuilder let finance: () -> Finance
    @ViewBuilder let timeline: () -> Timeline

    var body: some View {
        switch mode {
        case .overview:
            overview()
        case .records:
            records()
        case .assets:
            assets()
        case .finance:
            finance()
        case .timeline:
            timeline()
        }
    }
}
