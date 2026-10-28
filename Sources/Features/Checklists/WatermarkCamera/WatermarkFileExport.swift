import SwiftUI
import UIKit

struct WatermarkPreparedExport: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let cleanupURL: URL
}

/// Export from a file URL; no whole-archive Data or eager FileWrapper in the view.
struct WatermarkFileExportPicker: UIViewControllerRepresentable {
    let file: WatermarkPreparedExport
    let completion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file.url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Bool) -> Void
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(!urls.isEmpty) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(false) }
    }
}

extension WatermarkCameraBatchService {
    enum FileFormat: String, Sendable { case jpeg = "jpg", pdf, zip }

    static func exportFile(_ photos: [WatermarkCapturedPhoto], format: FileFormat, compression: CGFloat,
                           name: String, progress: @Sendable (Int, Int) -> Void) throws -> WatermarkPreparedExport {
        guard !photos.isEmpty else { throw WatermarkCameraBatchError.emptySelection }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watermark-export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safeName(name)).appendingPathExtension(format.rawValue)
        do {
            try Task.checkCancellation()
            switch format {
            case .jpeg:
                try jpeg(photos[0], compression: compression).write(to: url, options: .atomic)
                progress(1, 1)
            case .zip:
                var writer = try StreamingZipArchiveWriter(fileURL: url)
                var records: [ExportRecord] = []
                for (index, photo) in photos.enumerated() {
                    try Task.checkCancellation()
                    try autoreleasepool {
                        let path = "\(safeName(photo.context.projectName ?? AppLocalization.string("未指定项目")))/\(Formatters.date.string(from: photo.capturedAt))/\(safeName(photo.context.workSection))_\(photo.id.uuidString).jpg"
                        try writer.addFile(path: path, data: jpeg(photo, compression: compression))
                        records.append(ExportRecord(photoId: photo.id, capturedAt: photo.capturedAt, projectId: photo.projectId, imagePath: path, context: photo.context))
                    }
                    progress(index + 1, photos.count)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try writer.addFile(path: "metadata.json", data: encoder.encode(records))
                _ = try writer.finish()
            case .pdf:
                var failure: Error?
                let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
                try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
                    for (index, photo) in photos.enumerated() {
                        guard failure == nil else { break }
                        do {
                            try Task.checkCancellation()
                            try autoreleasepool {
                                let image = try photo.imageForDelivery()
                                context.beginPage()
                                ((photo.context.projectName ?? AppLocalization.string("未指定项目")) as NSString).draw(in: CGRect(x: 28, y: 24, width: 539, height: 42), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17)])
                                image.draw(in: fit(image.size, in: CGRect(x: 28, y: 76, width: 539, height: 686)))
                                let footer = "\(Formatters.dateTime.string(from: photo.capturedAt)) · \(index + 1) / \(photos.count)"
                                (footer as NSString).draw(in: CGRect(x: 28, y: 792, width: 539, height: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
                            }
                            progress(index + 1, photos.count)
                        } catch { failure = error }
                    }
                }
                if let failure { throw failure }
            }
            try Task.checkCancellation()
            return WatermarkPreparedExport(url: url, cleanupURL: directory)
        } catch {
            cleanupExport(at: directory)
            throw error
        }
    }

    static func cleanupExport(at url: URL) {
        _ = try? FileOps.removeIfExists(at: url, context: .init(event: "watermark.export.cleanup", category: .fileStorage, source: "WatermarkCameraBatchService.cleanupExport"))
    }
}
