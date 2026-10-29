import SwiftUI

struct DashboardBusinessOverviewPanel: View {
    let summary: ProjectBusinessSummary
    let projectCount: Int
    let onOpen: (ProjectOverviewFilter) -> Void

    var body: some View {
        DashboardPanel(
            title: AppLocalization.string("经营概况"),
            systemImage: "chart.xyaxis.line",
            destination: .projectList()
        ) {
            ProjectBusinessCardsView(
                summary: summary,
                onOpenReceivableAging: {
                    onOpen(.receivableAging)
                },
                onOpenRecentCollection: {
                    onOpen(.recentCollection)
                },
                onOpenCostAnomaly: {
                    onOpen(.costAnomaly)
                },
                onOpenProfitRisk: {
                    onOpen(.lowMarginRisk)
                }
            )
            Text(AppLocalization.string("business_scope_dashboard_note"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(String(format: AppLocalization.string("已关注 %lld 个工程"), Int64(projectCount)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
