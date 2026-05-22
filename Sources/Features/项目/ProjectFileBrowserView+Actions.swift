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
            ProjectFileCollector.items(for: inspection.project.id, category: category, projectStore: projectStore)
                .contains { !$0.exists }
        } ?? .documents
    }

    func syncSplitSelectionIfNeeded() {
        guard usesThreeColumnLayout else { return }

        if let selectedProjectId,
           !filteredProjects.contains(where: { $0.id == selectedProjectId }) {
            self.selectedProjectId = nil
        }
        if selectedProjectId == nil {
            selectedProjectId = filteredProjects.first?.id
        }

        let itemIds = Set(splitCategoryItems.map(\.id))
        if let selectedSplitItemId, !itemIds.contains(selectedSplitItemId) {
            self.selectedSplitItemId = nil
        }
        if selectedSplitItemId == nil {
            selectedSplitItemId = splitCategoryItems.first?.id
        }
    }

    func projectMatchesHealthFilter(_ project: Project) -> Bool {
        ProjectFileCollector.allItems(for: project.id, projectStore: projectStore).contains {
            healthFilter.matches($0)
        }
    }
}
