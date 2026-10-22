import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreTransferable

struct ProjectWarehouseVideoTransfer: Transferable {
    static let maxVideoBytes = ImportLimitPolicy.maxImportBytes

    let fileURL: URL
    let originalName: String
    let byteSize: Int

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let source = received.file
            let sourceSize = QuickNoteAttachmentStorage.fileSize(at: source)
            if sourceSize > maxVideoBytes {
                throw ProjectWarehouseVideoTransferError.tooLarge(sourceSize)
            }
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("warehouse-media", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("warehouse-\(UUID().uuidString).\(ext)")
            _ = try FileOps.removeIfExists(
                at: tempURL,
                context: .init(
                    event: "project_warehouse.prepare_temp_video",
                    category: .fileStorage,
                    source: "ProjectWarehouseVideoTransfer.transferRepresentation"
                )
            )
            try FileManager.default.copyItem(at: source, to: tempURL)
            return ProjectWarehouseVideoTransfer(
                fileURL: tempURL,
                originalName: source.lastPathComponent,
                byteSize: sourceSize
            )
        }
    }
}

enum ProjectWarehouseVideoTransferError: LocalizedError {
    case tooLarge(Int)

    var userMessage: String {
        switch self {
        case .tooLarge(let size):
            return ImportLimitPolicy.genericTooLargeMessage(itemName: String(localized: "视频"), size: size, limit: ProjectWarehouseVideoTransfer.maxVideoBytes)
        }
    }
}

enum ProjectWarehouseAttachmentImportError: LocalizedError {
    case tooLarge(fileName: String, size: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .tooLarge(_, let size, let limit):
            return ImportLimitPolicy.genericTooLargeMessage(itemName: String(localized: "文件"), size: size, limit: limit)
        }
    }
}

struct ProjectWarehouseAttachmentDraft: Identifiable {
    let id = UUID()
    let title: String
    let fileExtension: String
    let note: String
    let payload: Payload

    enum Payload {
        case fileURL(URL, cleanupAfterImport: Bool)
        case image(UIImage)
        case data(Data)
    }

    init(fileURL: URL, title: String? = nil, note: String = String(localized: "来源: 文件导入"), cleanupAfterImport: Bool = false) {
        let ext = fileURL.pathExtension.lowercased()
        let preferredTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = preferredTitle.isEmpty ? fileURL.lastPathComponent : preferredTitle
        self.fileExtension = ext.isEmpty ? "dat" : ext
        self.note = note
        self.payload = .fileURL(fileURL, cleanupAfterImport: cleanupAfterImport)
    }

    init(image: UIImage, title: String) {
        self.title = title
        self.fileExtension = "jpg"
        self.note = String(localized: "来源: 拍照")
        self.payload = .image(image)
    }

    init(data: Data, fileExtension: String, title: String) {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.title = title
        self.fileExtension = ext.isEmpty ? "dat" : ext
        self.note = String(localized: "来源: 相册媒体")
        self.payload = .data(data)
    }

    var displayType: String {
        fileExtension.uppercased()
    }

    var systemImage: String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "webp":
            return "photo"
        case "mov", "mp4", "m4v":
            return "video.fill"
        case "pdf":
            return "doc.richtext"
        case "dwg", "dxf":
            return "ruler"
        case "xls", "xlsx", "csv", "numbers":
            return "tablecells"
        case "doc", "docx", "pages":
            return "doc.text"
        default:
            return "paperclip"
        }
    }
}

struct ProjectWarehouseMovementDetailView: View {
    let movement: ProjectWarehouseMovement
    let documents: [ProjectDocument]
    @State private var previewURL: URL?

    private var movementType: WarehouseMovementType {
        movement.normalizedMovementType
    }

    var body: some View {
        List {
            Section(String(localized: "出入库")) {
                LabeledContent(String(localized: "类型"), value: movementType.displayName)
                LabeledContent(String(localized: "日期"), value: movement.date)
                LabeledContent(String(localized: "材料"), value: movement.materialName)
                if !movement.specification.isEmpty {
                    LabeledContent(String(localized: "规格"), value: movement.specification)
                }
                LabeledContent(String(localized: "数量"), value: "\(movement.quantity) \(movement.unit)")
                if !movement.counterparty.isEmpty {
                    LabeledContent(movementType == .inbound ? String(localized: "供应商/来源") : String(localized: "领用班组/去向"), value: movement.counterparty)
                }
                if !movement.handler.isEmpty {
                    LabeledContent(String(localized: "经手人"), value: movement.handler)
                }
                if !movement.note.isEmpty {
                    Text(movement.note)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "附件")) {
                if documents.isEmpty {
                    Text(String(localized: "暂无附件"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(documents) { document in
                        ProjectWarehouseAttachmentDocumentRow(document: document) {
                            previewURL = ProjectDocumentStorage.fileURL(for: document.fileName)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "出入库详情"))
        .navigationBarTitleDisplayMode(.inline)
        .appFilePreview($previewURL)
    }
}

struct ProjectWarehouseAttachmentImportResult {
    let documents: [ProjectDocument]
    let failures: [String]
}

@MainActor
enum ProjectWarehouseAttachmentImporter {
    nonisolated private static let maxAttachmentImportBytes = ImportLimitPolicy.maxImportBytes

    nonisolated static func validateFileURLForImport(_ url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceSize = QuickNoteAttachmentStorage.fileSize(at: url)
        try validateAttachmentSize(sourceSize, fileName: url.lastPathComponent)
    }

    static func importAttachments(
        _ attachments: [ProjectWarehouseAttachmentDraft],
        movement: ProjectWarehouseMovement,
        store: DataStore
    ) -> ProjectWarehouseAttachmentImportResult {
        var documents: [ProjectDocument] = []
        var failures: [String] = []
        for attachment in attachments {
            do {
                let document = try importAttachment(attachment, movement: movement)
                documents.append(document)
            } catch {
                failures.append(failureMessage(for: attachment, error: error))
            }
            cleanupTemporaryFileIfNeeded(attachment)
        }
        return ProjectWarehouseAttachmentImportResult(documents: documents, failures: failures)
    }

    private static func importAttachment(_ attachment: ProjectWarehouseAttachmentDraft, movement: ProjectWarehouseMovement) throws -> ProjectDocument {
        switch attachment.payload {
        case .fileURL(let url, _):
            return try importFile(url, movement: movement, note: attachment.note)
        case .image(let image):
            return try importImage(image, movement: movement, title: attachment.title, note: attachment.note)
        case .data(let data):
            return try importData(data, fileExtension: attachment.fileExtension, movement: movement, title: attachment.title, note: attachment.note)
        }
    }

    private static func cleanupTemporaryFileIfNeeded(_ attachment: ProjectWarehouseAttachmentDraft) {
        guard case .fileURL(let url, let cleanupAfterImport) = attachment.payload, cleanupAfterImport else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: url,
                context: .init(
                    event: "project_warehouse.cleanup_temp_file",
                    category: .fileStorage,
                    source: "ProjectWarehouseStorageSupport.cleanupTemporaryFileIfNeeded"
                )
            )
        } catch {
            StorageIssueLog.recordEvent(
                "project_warehouse.cleanup_temp_file_failed",
                category: .fileStorage,
                details: ["file": url.lastPathComponent],
                error: error
            )
        }
    }

    private static func importFile(_ url: URL, movement: ProjectWarehouseMovement, note: String) throws -> ProjectDocument {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let sourceSize = QuickNoteAttachmentStorage.fileSize(at: url)
        try validateAttachmentSize(sourceSize, fileName: url.lastPathComponent)

        let ext = url.pathExtension.lowercased()
        let fileType: String
        let pageCount: Int
        let fileName: String
        if ext == "pdf" {
            fileType = "pdf"
            pageCount = ProjectDetailFinanceDocumentHelper.pdfPageCount(at: url)
            fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: movement.projectId, fileExtension: fileType)
        } else if isImageExtension(ext) {
            fileType = ext.isEmpty ? "jpg" : ext
            pageCount = 1
            fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: movement.projectId, fileExtension: fileType)
        } else {
            fileType = ext.isEmpty ? "dat" : ext
            pageCount = 1
            fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: movement.projectId, fileExtension: fileType)
        }

        return makeDocument(
            movement: movement,
            title: url.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            fileType: fileType,
            pageCount: pageCount,
            note: note
        )
    }

    private static func importImage(_ image: UIImage, movement: ProjectWarehouseMovement, title: String, note: String) throws -> ProjectDocument {
        guard let imageData = ProjectDetailFinanceDocumentHelper.compressedJPEGData(from: image) else {
            throw FileStorageError.writeFailed(title)
        }
        try validateAttachmentSize(imageData.count, fileName: title)
        let fileName = try ProjectDocumentStorage.saveDataOrThrow(data: imageData, projectId: movement.projectId, fileExtension: "jpg")
        return makeDocument(movement: movement, title: title, fileName: fileName, fileType: "jpg", pageCount: 1, note: note)
    }

    private static func importData(_ data: Data, fileExtension: String, movement: ProjectWarehouseMovement, title: String, note: String) throws -> ProjectDocument {
        try validateAttachmentSize(data.count, fileName: title)
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileType = ext.isEmpty ? "dat" : ext
        let fileName = try ProjectDocumentStorage.saveDataOrThrow(data: data, projectId: movement.projectId, fileExtension: fileType)
        return makeDocument(movement: movement, title: title, fileName: fileName, fileType: fileType, pageCount: 1, note: note)
    }

    nonisolated private static func validateAttachmentSize(_ size: Int, fileName: String) throws {
        if size > maxAttachmentImportBytes {
            throw ProjectWarehouseAttachmentImportError.tooLarge(
                fileName: fileName,
                size: size,
                limit: maxAttachmentImportBytes
            )
        }
    }

    private static func failureMessage(for attachment: ProjectWarehouseAttachmentDraft, error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(attachment.title)（\(description)）"
        }
        return String(format: String(localized: "%@（导入失败）"), attachment.title)
    }

    private static func makeDocument(
        movement: ProjectWarehouseMovement,
        title: String,
        fileName: String,
        fileType: String,
        pageCount: Int,
        note: String
    ) -> ProjectDocument {
        let movementTitle = [movement.normalizedMovementType.displayName, movement.materialName].filter { !$0.isEmpty }.joined(separator: "-")
        let documentTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(format: String(localized: "%@-附件"), movementTitle) : title
        let detailNote = [
            String(format: String(localized: "仓库%@"), movement.normalizedMovementType.displayName),
            movement.date,
            movement.materialName,
            movement.specification,
            note
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        return ProjectDocument(
            projectId: movement.projectId,
            title: documentTitle,
            category: .other,
            fileName: fileName,
            fileType: fileType,
            pageCount: pageCount,
            createdAt: Formatters.now(),
            note: detailNote
        )
    }

    private static func isImageExtension(_ ext: String) -> Bool {
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .image)
        }
        return ["jpg", "jpeg", "png", "heic", "webp"].contains(ext)
    }
}

struct WarehouseStockLine: Identifiable {
    let id: String
    let materialName: String
    let specification: String
    let unit: String
    let quantity: Double
}

@MainActor
enum WarehouseStockCalculator {
    static func stockLines(for projectId: UUID, movements: [ProjectWarehouseMovement]) -> [WarehouseStockLine] {
        let related = movements.filter { $0.projectId == projectId }
        var groups: [String: (name: String, spec: String, unit: String, quantity: QuantityValue)] = [:]
        for movement in related {
            let name = movement.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let spec = movement.specification.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = movement.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = MaterialIdentity.key(name: name, specification: spec, unit: unit)
            let type = movement.normalizedMovementType
            var current = groups[key] ?? (name, spec, unit, .zero)
            let quantity = movement.quantityValue
            switch type {
            case .inbound:
                current.quantity = current.quantity + quantity
            case .outbound:
                current.quantity = QuantityValue(
                    DecimalMath.subtract(current.quantity.decimal, quantity.decimal)
                )
            }
            groups[key] = current
        }
        return groups.map { key, value in
            WarehouseStockLine(
                id: key,
                materialName: value.name,
                specification: value.spec,
                unit: value.unit,
                quantity: value.quantity.doubleValue
            )
        }
        .sorted { lhs, rhs in
            if lhs.quantity < 0 && rhs.quantity >= 0 { return true }
            if lhs.quantity >= 0 && rhs.quantity < 0 { return false }
            return lhs.materialName.localizedStandardCompare(rhs.materialName) == .orderedAscending
        }
    }

    static func quantityText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
