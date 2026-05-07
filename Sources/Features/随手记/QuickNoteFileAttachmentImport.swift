import Foundation
import UniformTypeIdentifiers

enum QuickNoteFileAttachmentImport {
    static let maxAttachmentBytes = ImportLimitPolicy.maxImportBytes

    static let allowedContentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .text, .rtf, .data]
        let extensions = [
            "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx",
            "pages", "numbers", "key", "dwg", "dxf", "ifc", "rvt",
            "txt", "zip", "rar", "7z"
        ]
        types.append(contentsOf: extensions.compactMap { UTType(filenameExtension: $0) })
        return types
    }()

    static func copyFile(from source: URL) throws -> QuickNoteAttachment {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let sourceSize = QuickNoteAttachmentStorage.fileSize(at: source)
        if sourceSize > maxAttachmentBytes {
            throw QuickNoteFileAttachmentImportError.tooLarge(sourceSize)
        }

        return try QuickNoteAttachmentStorage.importFileOrThrow(from: source)
    }
}

enum QuickNoteFileAttachmentImportError: LocalizedError {
    case tooLarge(Int)

    var userMessage: String {
        switch self {
        case .tooLarge(let size):
            return ImportLimitPolicy.genericTooLargeMessage(itemName: "附件", size: size, limit: QuickNoteFileAttachmentImport.maxAttachmentBytes)
        }
    }
}
