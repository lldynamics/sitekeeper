import Foundation

extension DataHealthView {
    func projectName(_ id: UUID?) -> String {
        guard let id else { return "" }
        return store.projects.first(where: { $0.id == id })?.name ?? lf("项目ID %@", shortId(id))
    }

    func issueDetail(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    func shortId(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
