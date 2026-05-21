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
    var actions: [DataHealthIssueAction] = []

    var exportText: String {
        detail.isEmpty ? title : "\(title): \(detail)"
    }
}

struct DataHealthIssueAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let kind: DataHealthIssueActionKind

    static func navigate(
        title: String,
        systemImage: String = "arrow.right.circle",
        route: DataHealthIssueRoute
    ) -> DataHealthIssueAction {
        DataHealthIssueAction(
            id: "navigate-\(title)",
            title: title,
            systemImage: systemImage,
            kind: .navigate(route)
        )
    }

    static func repair(
        title: String,
        repair: DataHealthIssueRepair
    ) -> DataHealthIssueAction {
        DataHealthIssueAction(
            id: "repair-\(title)",
            title: title,
            systemImage: "wrench.and.screwdriver",
            kind: .repair(repair)
        )
    }

    static func moveToTrash(
        title: String,
        file: DataHealthOrphanFile
    ) -> DataHealthIssueAction {
        DataHealthIssueAction(
            id: "trash-\(file.kind.rawValue)-\(file.fileName)",
            title: title,
            systemImage: "trash",
            role: .destructive,
            kind: .moveOrphanFileToTrash(file)
        )
    }

    static func createTodo(title: String) -> DataHealthIssueAction {
        DataHealthIssueAction(
            id: "todo",
            title: title,
            systemImage: "checklist.checked",
            kind: .createTodo
        )
    }
}

enum DataHealthIssueActionKind {
    case navigate(DataHealthIssueRoute)
    case repair(DataHealthIssueRepair)
    case moveOrphanFileToTrash(DataHealthOrphanFile)
    case createTodo
}

enum DataHealthIssueRepair {
    case clearDailyLogLegacyPhoto(logId: UUID, fileName: String)
    case removeDailyLogPhoto(logId: UUID, photoId: UUID)
    case clearSiteTodoBeforePhoto(todoId: UUID, fileName: String)
    case clearSiteTodoAfterPhoto(todoId: UUID, fileName: String)
    case removeProjectDocument(documentId: UUID)
    case removeQuickNoteAttachment(noteId: UUID, attachmentId: UUID)
    case unlinkFinancialDocument(recordId: UUID, documentId: UUID)
    case unlinkWarehouseDocument(movementId: UUID, documentId: UUID)
    case clearDocumentLinkedFinancialRecord(documentId: UUID)
    case clearMaterialProject(itemId: UUID)
    case clearQuoteProject(itemId: UUID)
    case clearLaborProject(recordId: UUID)
    case clearDailyLogProject(logId: UUID)
    case clearSiteTodoProject(todoId: UUID)
    case clearQuickNoteProject(noteId: UUID)
}

struct DataHealthOrphanFile {
    let kind: DataHealthOrphanFileKind
    let fileName: String
}

enum DataHealthOrphanFileKind: String {
    case photo
    case drawing
    case projectDocument
    case quickNoteAttachment
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
