import SwiftUI

extension DashboardView {
    var globalSearchInput: some View {
        DashboardGlobalSearch(
            text: $dashboardSearchText,
            projectID: $dashboardSearchProjectID,
            category: $dashboardSearchCategory,
            projects: projectStore.projects,
            suggestions: dashboardSearchSuggestions,
            onSelect: { selectedDashboardSuggestion = $0 }
        )
        .task(id: dashboardSearchRequest) {
            let request = dashboardSearchRequest
            await dashboardSearchModel.refresh(snapshot: dashboardSearchSnapshot, request: request)
        }
    }
}
