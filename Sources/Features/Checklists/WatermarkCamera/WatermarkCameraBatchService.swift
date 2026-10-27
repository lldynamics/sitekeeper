import Foundation
import UIKit

enum WatermarkCameraBatchError: LocalizedError {
    case emptySelection, mixedProjects, missingProject, imageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptySelection: return AppLocalization.string("请先选择照片。")
        case .mixedProjects: return AppLocalization.string("请只选择同一项目的照片，再写入施工日志。")
        case .missingProject: return AppLocalization.string("拍摄时关联的项目已不存在或未关联，请保留照片并先核对项目。")
        case .imageUnavailable: return AppLocalization.string("照片原文件无法读取，已停止导出，请保留草稿并重试。")
        }
    }
}

enum WatermarkCameraBatchService {
    struct ExportRecord: Codable {
        let photoId: UUID
        let capturedAt: Date
        let projectId: UUID?
        let imagePath: String
        let context: CameraWatermarkContext
    }
    static func logProject(for photos: [WatermarkCapturedPhoto]) throws -> UUID? {
        guard let first = photos.first else { throw WatermarkCameraBatchError.emptySelection }
        guard photos.allSatisfy({ $0.projectId == first.projectId }) else { throw WatermarkCameraBatchError.mixedProjects }
        return first.projectId
    }

    static func jpeg(_ photo: WatermarkCapturedPhoto, compression: CGFloat) throws -> Data {
        guard let data = try photo.imageForDelivery().jpegData(compressionQuality: compression) else {
            throw WatermarkCameraBatchError.imageUnavailable
        }
        return data
    }

    static func pdf(_ photos: [WatermarkCapturedPhoto]) throws -> Data {
        guard !photos.isEmpty else { throw WatermarkCameraBatchError.emptySelection }
        var renderingError: Error?
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for (index, photo) in photos.enumerated() {
                guard renderingError == nil else { break }
                autoreleasepool {
                    let image: UIImage
                    do { image = try photo.imageForDelivery() }
                    catch { renderingError = error; return }
                    context.beginPage()
                    let title = photo.context.projectName ?? AppLocalization.string("未指定项目")
                    (title as NSString).draw(in: CGRect(x: 28, y: 24, width: 539, height: 42), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
                    let bounds = CGRect(x: 28, y: 76, width: 539, height: 686)
                    image.draw(in: fit(image.size, in: bounds))
                    let footer = "\(Formatters.dateTime.string(from: photo.capturedAt)) · \(index + 1) / \(photos.count)"
                    (footer as NSString).draw(in: CGRect(x: 28, y: 792, width: 539, height: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
                }
            }
        }
        if let renderingError { throw renderingError }
        return data
    }

    static func zip(_ photos: [WatermarkCapturedPhoto], compression: CGFloat) throws -> Data {
        guard !photos.isEmpty else { throw WatermarkCameraBatchError.emptySelection }
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "watermark-photos")
        defer {
            _ = try? FileOps.removeIfExists(at: url, context: .init(event: "watermark.export.cleanup", category: .zipArchive, source: "WatermarkCameraBatchService.zip"))
        }
        var writer = try StreamingZipArchiveWriter(fileURL: url)
        var records: [ExportRecord] = []
        for photo in photos {
            try autoreleasepool {
                let project = safeName(photo.context.projectName ?? AppLocalization.string("未指定项目"))
                let day = Formatters.date.string(from: photo.capturedAt)
                let section = safeName(photo.context.workSection.isEmpty ? AppLocalization.string("现场") : photo.context.workSection)
                let name = "\(project)/\(day)/\(section)_\(photo.id.uuidString).jpg"
                try writer.addFile(path: name, data: jpeg(photo, compression: compression))
                records.append(ExportRecord(photoId: photo.id, capturedAt: photo.capturedAt,
                    projectId: photo.projectId, imagePath: name, context: photo.context))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try writer.addFile(path: "metadata.json", data: encoder.encode(records))
        _ = try writer.finish()
        return try Data(contentsOf: url)
    }

    static func fit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let factor = min(bounds.width / size.width, bounds.height / size.height)
        let output = CGSize(width: size.width * factor, height: size.height * factor)
        return CGRect(x: bounds.midX - output.width / 2, y: bounds.midY - output.height / 2, width: output.width, height: output.height)
    }

    static func safeName(_ value: String) -> String {
        let cleaned = value.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t").union(.controlCharacters)).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "现场" : String(cleaned.prefix(60))
    }

    @MainActor
    static func archive(_ photo: WatermarkCapturedPhoto, in store: DataStore) async throws {
        guard store.loadState == .ready, !store.isApplyingBackup,
              let projectId = photo.projectId, store.projects.contains(where: { $0.id == projectId }) else {
            throw WatermarkCameraBatchError.missingProject
        }
        // A stable ID makes retries safe even if the process ends after the document
        // was saved but before its delivery status was written to the photo draft.
        if let existing = store.projectDocuments.first(where: { $0.id == photo.id }) {
            guard existing.projectId == projectId, ProjectDocumentStorage.exists(fileName: existing.fileName) else {
                throw WatermarkCameraBatchError.imageUnavailable
            }
        } else {
            let filename = try await FileIOTaskRunner.run {
                try ProjectDocumentStorage.saveDataOrThrow(data: jpeg(photo, compression: 0.96), projectId: projectId, fileExtension: "jpg")
            }
            guard store.loadState == .ready, !store.isApplyingBackup,
                  store.projects.contains(where: { $0.id == projectId }) else {
                try await FileIOTaskRunner.run { try DataStoreDeferredFileCleanup.deleteProjectDocumentFilesOrThrow([filename], summary: "watermark.archive.unused") }
                throw WatermarkCameraBatchError.missingProject
            }
            if let existing = store.projectDocuments.first(where: { $0.id == photo.id }) {
                try await FileIOTaskRunner.run { try DataStoreDeferredFileCleanup.deleteProjectDocumentFilesOrThrow([filename], summary: "watermark.archive.unused") }
                guard existing.projectId == projectId, ProjectDocumentStorage.exists(fileName: existing.fileName) else {
                    throw WatermarkCameraBatchError.imageUnavailable
                }
                try await store.flushSaveOrThrow()
                return
            }
            let category: ProjectDocumentCategory
            switch photo.context.template {
            case .receipt: category = .receipt
            case .paymentProof: category = .paymentRequest
            case .constructionLog, .rectification: category = .constructionRecord
            }
            let document = ProjectDocument(
                id: photo.id, projectId: projectId,
                title: "\(photo.context.template.displayName)-\(Formatters.dateTime.string(from: photo.capturedAt))",
                category: category, fileName: filename, fileType: "jpg",
                responsiblePerson: photo.context.photographer, workSection: photo.context.workSection,
                createdAt: BusinessDateValue(legacyText: Formatters.timestamp(photo.capturedAt)),
                note: photo.context.lines(capturedAt: photo.capturedAt).joined(separator: "\n")
            )
            store.appendProjectDocument(document)
        }
        try await store.flushSaveOrThrow()
    }
}
