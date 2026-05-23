import Foundation

enum ProjectFileCategory: CaseIterable {
    case images
    case drawings
    case documents
    case quickNoteAttachments
}

enum ProjectFileHealthFilter: String, CaseIterable {
    case all
    case missing
    case actionDocuments
    case returnedDocuments
    case unarchivedDocuments
    case incompleteDocumentLedger
    case largeFiles

    func matches(_ item: ProjectFileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .missing:
            return !item.exists
        case .actionDocuments:
            return item.documentStatus?.requiresArchiveAttention == true
        case .returnedDocuments:
            return item.documentStatus == .returned
        case .unarchivedDocuments:
            guard let status = item.documentStatus else { return false }
            return status != .archived
        case .incompleteDocumentLedger:
            return item.documentLedgerIssueCount > 0
        case .largeFiles:
            return item.isLargeFile
        }
    }
}

@MainActor
struct ProjectFileSummary {
    let imageCount: Int
    let drawingCount: Int
    let documentCount: Int
    let quickNoteAttachmentCount: Int

    var totalCount: Int {
        imageCount + drawingCount + documentCount + quickNoteAttachmentCount
    }

    init(projectId: UUID, projectStore: ProjectStore) {
        imageCount = ProjectFileCollector.count(for: projectId, category: .images, projectStore: projectStore)
        drawingCount = ProjectFileCollector.count(for: projectId, category: .drawings, projectStore: projectStore)
        documentCount = ProjectFileCollector.count(for: projectId, category: .documents, projectStore: projectStore)
        quickNoteAttachmentCount = ProjectFileCollector.count(for: projectId, category: .quickNoteAttachments, projectStore: projectStore)
    }

    init(projectId: UUID, store: DataStore) {
        self.init(projectId: projectId, projectStore: store.projectStore)
    }

    func count(for category: ProjectFileCategory) -> Int {
        switch category {
        case .images: return imageCount
        case .drawings: return drawingCount
        case .documents: return documentCount
        case .quickNoteAttachments: return quickNoteAttachmentCount
        }
    }
}

struct ProjectFileItem: Identifiable {
    static let largeFileWarningBytes = 100 * 1024 * 1024

    let id: String
    let title: String
    let subtitle: String
    let fileType: String
    let url: URL
    let exists: Bool
    let size: Int
    let category: ProjectFileCategory
    let systemImage: String
    let thumbnailToken: ProjectFileThumbnailToken?
    let sortDate: Date
    let documentStatus: ProjectDocumentSubmissionStatus?
    var documentLedgerIssueCount = 0

    var formattedSize: String {
        size > 0 ? QuickNoteAttachmentStorage.formattedFileSize(size) : "-"
    }

    var isLargeFile: Bool {
        size >= Self.largeFileWarningBytes
    }

    var hasDocumentLedgerIssues: Bool {
        documentLedgerIssueCount > 0
    }
}

enum ProjectFileThumbnailToken: Hashable {
    case photo(fileName: String)
    case quickNote(kind: QuickNoteAttachmentKind, fileName: String)

    var cacheKey: String {
        switch self {
        case .photo(let fileName):
            return "photo:\(fileName)"
        case .quickNote(let kind, let fileName):
            return "quick:\(kind.rawValue):\(fileName)"
        }
    }
}
