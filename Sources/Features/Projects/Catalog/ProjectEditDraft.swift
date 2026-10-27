import Foundation
import Observation

/// Owned by the presentation coordinator, so adaptive editor recreation cannot discard edits.
@MainActor
@Observable
final class ProjectEditDraft {
    enum Field: Hashable {
        case name, location, customerName, customerPhone, managerName, contractAmount
    }

    let original: Project
    var focusedField: Field?
    var name: String
    var location: String
    var customerName: String
    var customerPhone: String
    var managerName: String
    var startDate: BusinessDateValue
    var expectedEndDate: BusinessDateValue
    var contractAmount: String
    var paymentStatus: PaymentStatus
    var requiredDocumentCategories: Set<ProjectDocumentCategory>
    var recommendationStage: ProjectDocumentRecommendationStage

    init(project: Project, progressTasks: [ProgressTask] = []) {
        original = project
        name = project.name
        location = project.location
        customerName = project.customerName
        customerPhone = project.customerPhone
        managerName = project.managerName
        startDate = project.startDate
        expectedEndDate = project.expectedEndDate
        contractAmount = project.contractAmount.wireText
        paymentStatus = project.paymentStatus
        requiredDocumentCategories = Set(project.requiredDocumentCategories)
        recommendationStage = ProjectDocumentCategory.recommendedStage(for: project, progressTasks: progressTasks)
    }

    func updatedProject(basedOn current: Project) -> Project {
        // Reuse current noneditable fields, including costs updated while this draft was open.
        precondition(current.id == original.id)
        var updated = current
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.location = location
        updated.customerName = customerName
        updated.customerPhone = customerPhone
        updated.managerName = managerName
        updated.startDate = startDate
        updated.expectedEndDate = expectedEndDate
        updated.contractAmount = NumericInputSupport.money(contractAmount)
        updated.paymentStatus = paymentStatus
        updated.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
            Array(requiredDocumentCategories)
        )
        return updated
    }
}
