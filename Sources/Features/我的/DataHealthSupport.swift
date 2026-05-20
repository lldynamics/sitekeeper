import SwiftUI
import UniformTypeIdentifiers

struct DataHealthIssue: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    let actionTitle: String?
    let route: DataHealthIssueRoute?

    var exportText: String {
        detail.isEmpty ? title : "\(title): \(detail)"
    }
}

enum DataHealthIssueRoute {
    case project(projectId: UUID, mode: ProjectDetailMode?)
    case financialRecord(projectId: UUID, recordId: UUID)
    case document(projectId: UUID, documentId: UUID)
    case dailyLog(projectId: UUID?, logId: UUID)
    case siteTodo(projectId: UUID?, todoId: UUID)
    case material(materialId: UUID)
    case quote(quoteId: UUID)
    case labor(laborId: UUID)
    case quickNote(noteId: UUID)
    case contact(contactId: UUID)
    case warehouseProject(projectId: UUID)
}

struct OptionalInlineTitleModifier: ViewModifier {
    let isEnabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
