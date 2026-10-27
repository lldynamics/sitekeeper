import Foundation

/// Scan result keeps preview names separate from opt-in embedded payload reads.
struct BackupArchiveReadContents {
    private var metadataData: Data?
    private var manifestData: Data?
    var photoFileNames: [String] = []
    var drawingFileNames: [String] = []
    var documentFileNames: [String] = []
    var quickNoteAttachmentFileNames: [String] = []
    var photoFiles: [PhotoBackupFile] = []
    var drawingFiles: [DrawingBackupFile] = []
    var documentFiles: [ProjectDocumentBackupFile] = []
    var quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile] = []

    mutating func accept(path: String, readData: () throws -> Data, includeEmbeddedData: Bool) throws {
        if path == BackupArchiveService.metadataPath {
            metadataData = try readData()
            return
        }
        if path == BackupArchiveService.manifestPath {
            manifestData = try readData()
            return
        }
        if let name = BackupArchiveService.leafFileName(for: path, prefix: BackupArchiveService.photoPrefix) {
            photoFileNames.append(name)
            if includeEmbeddedData { photoFiles.append(PhotoBackupFile(fileName: name, data: try readData())) }
            return
        }
        if let name = BackupArchiveService.leafFileName(for: path, prefix: BackupArchiveService.drawingPrefix) {
            drawingFileNames.append(name)
            if includeEmbeddedData { drawingFiles.append(DrawingBackupFile(fileName: name, data: try readData())) }
            return
        }
        if let name = BackupArchiveService.leafFileName(for: path, prefix: BackupArchiveService.documentPrefix) {
            documentFileNames.append(name)
            if includeEmbeddedData { documentFiles.append(ProjectDocumentBackupFile(fileName: name, data: try readData())) }
            return
        }
        if let name = BackupArchiveService.leafFileName(for: path, prefix: BackupArchiveService.quickNotePrefix) {
            quickNoteAttachmentFileNames.append(name)
            if includeEmbeddedData { quickNoteAttachmentFiles.append(QuickNoteAttachmentBackupFile(fileName: name, data: try readData())) }
        }
    }

    func validatedMetadataData(eventPrefix: String) throws -> (metadata: Data, manifest: Data) {
        guard let metadataData else {
            recordBackupArchiveIssue("backup.archive.\(eventPrefix)_missing_metadata", path: BackupArchiveService.metadataPath)
            throw BackupArchiveError.missingMetadata
        }
        guard let manifestData else {
            recordBackupArchiveIssue("backup.archive.\(eventPrefix)_missing_manifest", path: BackupArchiveService.manifestPath)
            throw BackupArchiveError.missingManifest
        }
        return (metadataData, manifestData)
    }
}
