import Foundation

@MainActor
extension DataStore {
    func saveProjectChangeOrder(
        _ value: ProjectChangeOrder,
        projectID: UUID,
        expected: ProjectChangeOrder?
    ) async throws {
        try await ProjectChangeOrderService.save(value, projectID: projectID, expected: expected, store: self)
    }
}
