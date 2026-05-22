import Foundation

@MainActor
extension DataStore {
    func appendProject(_ project: Project) {
        replaceProjects(projects + [project])
    }

    @discardableResult
    func updateProject(_ project: Project) -> Bool {
        var current = projects
        guard let index = current.firstIndex(where: { $0.id == project.id }) else { return false }
        current[index] = project
        replaceProjects(current)
        return true
    }

    func mergeProjectsByID(_ values: [Project]) {
        replaceProjects(mergedProjectActivityElementsByID(projects, with: values))
    }
}
