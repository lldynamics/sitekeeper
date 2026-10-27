import SwiftUI

extension ProjectFileBrowserView {
    func exportDeliveryInspections(
        _ inspections: [ProjectDocumentDeliveryInspection],
        format: ProjectDocumentDeliveryInspectionExportFormat
    ) {
        guard !inspections.isEmpty else { return }
        deliveryInspectionExportPayload = ProjectDocumentDeliveryInspectionExport.makePayload(
            for: inspections,
            format: format
        )
        showDeliveryInspectionExporter = true
    }

    @ViewBuilder
    func deliveryDestination(
        for inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) -> some View {
        if let category = issue.kind.preferredCategory {
            ProjectFileListView(
                project: inspection.project,
                category: category,
                initialHealthFilter: issue.kind.preferredHealthFilter
            )
        } else {
            ProjectFileCategoryView(
                project: inspection.project,
                initialHealthFilter: issue.kind.preferredHealthFilter
            )
        }
    }

    func selectDeliveryInspection(
        _ inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) {
        selectedProjectId = inspection.project.id
        selectedCategory = issue.kind.preferredCategory ?? deliveryFallbackCategory(for: inspection, issue: issue)
        healthFilter = issue.kind.preferredHealthFilter
        selectedSplitItemId = nil
        syncSplitSelectionIfNeeded()
    }

    func deliveryFallbackCategory(
        for inspection: ProjectDocumentDeliveryInspection,
        issue: ProjectDocumentDeliveryInspectionIssue
    ) -> ProjectFileCategory {
        guard issue.kind == .missingFiles else { return .documents }
        return ProjectFileCategory.allCases.first { category in
            !(preparedFiles?.items(for: inspection.project.id, category: category, health: .missing).isEmpty ?? true)
        } ?? .documents
    }

    func syncSplitSelectionIfNeeded() {
        guard usesThreeColumnLayout, preparedFiles != nil,
              !fileBrowserModel.isPreparing, !fileBrowserModel.isSearching else { return }

        selectedProjectId = ProjectFileBrowserSelection.projectID(
            current: selectedProjectId,
            projectMatches: filteredProjects.map(\.id),
            fileMatches: displayedFileSearchResults.map { $0.project.id }
        )

        let itemIds = Set(splitCategoryItems.map(\.id))
        if let selectedSplitItemId, !itemIds.contains(selectedSplitItemId) {
            self.selectedSplitItemId = nil
        }
        if selectedSplitItemId == nil {
            selectedSplitItemId = splitCategoryItems.first?.id
        }
    }

    func projectMatchesHealthFilter(_ project: Project) -> Bool {
        !(preparedFiles?.items(for: project.id, health: healthFilter).isEmpty ?? true)
    }
}
