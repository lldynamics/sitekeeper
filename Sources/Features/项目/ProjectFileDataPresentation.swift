import SwiftUI

extension ProjectFileCategory {
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

extension ProjectFileHealthFilter {
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
}
