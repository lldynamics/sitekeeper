import SwiftUI
import UIKit

enum ProjectFileCategory: CaseIterable {
    case images
    case drawings
    case documents
    case quickNoteAttachments

    var title: String {
        switch self {
        case .images: return String(localized: "project.files.category.images.title")
        case .drawings: return String(localized: "project.files.category.drawings.title")
        case .documents: return String(localized: "project.files.category.documents.title")
        case .quickNoteAttachments: return String(localized: "project.files.category.quickNoteAttachments.title")
        }
    }

    var description: String {
        switch self {
        case .images: return String(localized: "project.files.category.images.description")
        case .drawings: return String(localized: "project.files.category.drawings.description")
        case .documents: return String(localized: "project.files.category.documents.description")
        case .quickNoteAttachments: return String(localized: "project.files.category.quickNoteAttachments.description")
        }
    }

    var systemImage: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .drawings: return "doc.viewfinder"
        case .documents: return "doc.richtext"
        case .quickNoteAttachments: return "paperclip"
        }
    }

    var tint: Color {
        switch self {
        case .images: return .appDoc
        case .drawings: return .appPrimaryAction
        case .documents: return .appPrimaryAction
        case .quickNoteAttachments: return .appPrimaryAction
        }
    }
}

enum ProjectFileHealthFilter: String, CaseIterable {
    case all
    case missing
    case actionDocuments
    case returnedDocuments
    case unarchivedDocuments
    case incompleteDocumentLedger
    case largeFiles

    var title: String {
        switch self {
        case .all: return String(localized: "project.files.healthFilter.all")
        case .missing: return String(localized: "project.files.healthFilter.missing")
        case .actionDocuments: return String(localized: "project.files.healthFilter.actionDocuments")
        case .returnedDocuments: return String(localized: "project.files.healthFilter.returnedDocuments")
        case .unarchivedDocuments: return String(localized: "project.files.healthFilter.unarchivedDocuments")
        case .incompleteDocumentLedger: return String(localized: "project.files.healthFilter.incompleteDocumentLedger")
        case .largeFiles: return String(localized: "project.files.healthFilter.largeFiles")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .missing: return "exclamationmark.triangle.fill"
        case .actionDocuments: return "clock.badge.exclamationmark"
        case .returnedDocuments: return "arrow.uturn.backward.circle.fill"
        case .unarchivedDocuments: return "archivebox"
        case .incompleteDocumentLedger: return "list.clipboard"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .appPrimaryAction
        case .missing, .returnedDocuments, .largeFiles: return .appRisk
        case .actionDocuments, .unarchivedDocuments, .incompleteDocumentLedger: return .appWarning
        }
    }

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

    func loadImageAsync() async -> UIImage? {
        switch self {
        case .photo(let fileName):
            return await PhotoStorage.thumbnailAsync(for: fileName)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                guard let data = await QuickNoteAttachmentStorage.dataAsync(for: fileName) else { return nil }
                return await loadDetachedThumbnail {
                    guard !Task.isCancelled else { return nil }
                    return ImageDownsampleService.downsampledImage(data, maxPixelSize: 256)
                }
            case .video:
                return await loadDetachedThumbnail {
                    guard !Task.isCancelled else { return nil }
                    return QuickNoteAttachmentStorage.videoThumbnail(for: fileName)
                }
            case .audio, .file:
                return nil
            }
        }
    }

    private func loadDetachedThumbnail(_ work: @escaping @Sendable () -> UIImage?) async -> UIImage? {
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            let image = work()
            guard !Task.isCancelled else { return nil }
            return image
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
