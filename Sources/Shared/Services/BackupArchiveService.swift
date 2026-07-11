import Foundation

enum BackupArchiveService {
    static var largeArchiveWarningBytes: Int { TransferLimitPolicy.backupArchiveWarningBytes }
    static let manifestPath = "manifest.json"
    static let metadataPath = "data/backup.json"
    static let readmePath = "README.txt"
    static let photoPrefix = "files/photos/"
    static let drawingPrefix = "files/drawings/"
    static let documentPrefix = "files/project-documents/"
    static let quickNotePrefix = "files/quick-note-attachments/"

    static func loc(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    static func locFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: loc(key), arguments: arguments)
    }
}

extension BackupSnapshot {
    func withoutEmbeddedFiles() -> BackupSnapshot {
        var copy = self
        copy.photoFiles = []
        copy.drawingFiles = []
        copy.documentFiles = []
        copy.quickNoteAttachmentFiles = []
        return copy
    }
}
