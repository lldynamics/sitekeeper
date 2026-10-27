import Foundation

struct DataStoreDeferredFileCleanup {
    let summary: String
    let fileCount: Int
    let perform: () -> Void
}

extension DataStoreDeferredFileCleanup {
    private static func normalizedFileNames(_ fileNames: [String]) -> [String] {
        Array(
            Set(
                fileNames
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    static func combined(
        summary: String,
        cleanups: [DataStoreDeferredFileCleanup?]
    ) -> DataStoreDeferredFileCleanup {
        let validCleanups = cleanups.compactMap { $0 }
        let totalFileCount = validCleanups.reduce(0) { $0 + $1.fileCount }
        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: totalFileCount,
            perform: {
                for cleanup in validCleanups {
                    cleanup.perform()
                }
            }
        )
    }

    static func photoFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                PhotoStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deletePhotoFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try PhotoStorage.deleteOrThrow(fileName: fileName)
            PhotoCache.shared.invalidate(fileName: fileName)
        }
    }

    static func drawingFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                DrawingStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteDrawingFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try DrawingStorage.deleteOrThrow(fileName: fileName)
        }
    }

    static func quickNoteAttachmentFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                QuickNoteAttachmentStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteQuickNoteAttachmentFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try QuickNoteAttachmentStorage.deleteOrThrow(fileName: fileName)
        }
    }

    static func quickNoteAttachments(
        _ attachments: [QuickNoteAttachment],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        quickNoteAttachmentFiles(attachments.map(\.fileName), summary: summary)
    }

    static func projectDocumentFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                ProjectDocumentStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteProjectDocumentFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try ProjectDocumentStorage.deleteOrThrow(fileName: fileName)
        }
    }
}
