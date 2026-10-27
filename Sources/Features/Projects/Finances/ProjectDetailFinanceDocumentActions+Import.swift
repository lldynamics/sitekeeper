import Foundation
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ProjectDetailFinanceDocumentActions {
    @MainActor
    static func saveScannedDocument(
        target: ProjectScanTarget,
        data: Data,
        pageCount: Int,
        projectId: UUID,
        store: DataStore
    ) -> String? {
        let fileName: String
        do {
            fileName = try ProjectDocumentStorage.savePDFOrThrow(data: data, projectId: projectId)
        } catch {
            return "扫描文件保存失败：\(error.localizedDescription)"
        }
        appendProjectDocument(fileName: fileName, pageCount: pageCount, target: target, projectId: projectId, store: store)
        return nil
    }

    @MainActor
    static func previewURL(for document: ProjectDocument) -> ProjectDetailActionResult<URL> {
        let url = ProjectDocumentStorage.fileURL(for: document.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure("资料文件不存在，可能已被清理。")
        }
        return .success(url)
    }

    @MainActor
    static func importProjectDocuments(
        _ urls: [URL],
        projectId: UUID,
        linkedFinancialRecordId: UUID? = nil,
        ledgerSettings: ProjectDocumentImportLedgerSettings? = nil,
        store: DataStore
    ) -> [String] {
        guard !urls.isEmpty else { return [] }
        var failures: [String] = []
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let sourceSize = QuickNoteAttachmentStorage.fileSize(at: url)
            if sourceSize > maxImportedDocumentBytes {
                failures.append(tooLargeMessage(for: url, size: sourceSize))
                continue
            }
            let ext = url.pathExtension.lowercased()
            let sourceType = documentSourceType(for: ext)
            let pageCount: Int
            let fileType: String
            let category: ProjectDocumentCategory
            let fileName: String
            if sourceType == "pdf" {
                pageCount = ProjectDetailFinanceDocumentHelper.pdfPageCount(at: url)
                fileType = "pdf"
                category = linkedFinancialRecordId == nil ? .constructionRecord : .invoice
                do {
                    fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: projectId, fileExtension: fileType)
                } catch {
                    failures.append("\(url.lastPathComponent)（保存失败）")
                    continue
                }
            } else if sourceType == "image" {
                pageCount = 1
                fileType = ext.isEmpty ? "jpg" : ext
                category = linkedFinancialRecordId == nil ? .constructionRecord : .receipt
                do {
                    fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: projectId, fileExtension: fileType)
                } catch {
                    failures.append("\(url.lastPathComponent)（保存失败）")
                    continue
                }
            } else {
                pageCount = 1
                fileType = ext.isEmpty ? "dat" : ext
                category = .other
                do {
                    fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: projectId, fileExtension: fileType)
                } catch {
                    failures.append("\(url.lastPathComponent)（保存失败）")
                    continue
                }
            }
            let resolvedSettings = (ledgerSettings ?? ProjectDocumentImportLedgerSettings(category: category)).normalized
            appendProjectDocument(
                fileName: fileName,
                pageCount: pageCount,
                target: ProjectScanTarget(
                    title: url.deletingPathExtension().lastPathComponent,
                    category: resolvedSettings.category,
                    amount: .empty,
                    linkedFinancialRecordId: linkedFinancialRecordId,
                    linkedConstructionMethodIDs: [],
                    submissionStatus: resolvedSettings.submissionStatus,
                    responsiblePerson: resolvedSettings.responsiblePerson,
                    formedAt: resolvedSettings.formedAt,
                    workSection: resolvedSettings.workSection,
                    note: "来源: 文件导入"
                ),
                projectId: projectId,
                store: store,
                fileType: fileType
            )
        }
        return failures
    }

    @MainActor
    static func importAttachmentData(
        _ data: Data,
        fileExtension: String,
        title: String,
        category: ProjectDocumentCategory = .other,
        note: String,
        projectId: UUID,
        linkedFinancialRecordId: UUID?,
        store: DataStore
    ) -> String? {
        switch importAttachmentDocumentData(
            data,
            fileExtension: fileExtension,
            title: title,
            category: category,
            note: note,
            projectId: projectId,
            linkedFinancialRecordId: linkedFinancialRecordId,
            store: store
        ) {
        case .success:
            return nil
        case .failure(let message):
            return message
        }
    }

    @MainActor
    static func importAttachmentDocumentData(
        _ data: Data,
        fileExtension: String,
        title: String,
        category: ProjectDocumentCategory = .other,
        note: String,
        projectId: UUID,
        linkedFinancialRecordId: UUID?,
        store: DataStore
    ) -> ProjectDetailActionResult<ProjectDocument> {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName: String
        do {
            fileName = try ProjectDocumentStorage.saveDataOrThrow(data: data, projectId: projectId, fileExtension: ext.isEmpty ? "dat" : ext)
        } catch {
            return .failure("附件保存失败：\(error.localizedDescription)")
        }
        let document = appendProjectDocument(
            fileName: fileName,
            pageCount: 1,
            target: ProjectScanTarget(
                title: title,
                category: category,
                amount: .empty,
                linkedFinancialRecordId: linkedFinancialRecordId,
                linkedConstructionMethodIDs: [],
                note: note
            ),
            projectId: projectId,
            store: store,
            fileType: ext.isEmpty ? "dat" : ext
        )
        return .success(document)
    }

    static func image(from item: PhotosPickerItem) async -> ProjectDetailActionResult<UIImage> {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return .failure("相册图片读取失败。")
        }
        return .success(image)
    }

    @MainActor
    static func importCapturedImage(
        _ image: UIImage,
        title: String? = nil,
        createdAt: String = Formatters.now(),
        category: ProjectDocumentCategory = .receipt,
        note: String,
        projectId: UUID,
        linkedFinancialRecordId: UUID? = nil,
        store: DataStore
    ) -> String? {
        guard let imageData = ProjectDetailFinanceDocumentHelper.compressedJPEGData(from: image) else {
            return "图片保存失败：图片编码失败"
        }
        let fileName: String
        do {
            fileName = try ProjectDocumentStorage.saveDataOrThrow(data: imageData, projectId: projectId, fileExtension: "jpg")
        } catch {
            return "图片保存失败：\(error.localizedDescription)"
        }
        appendProjectDocument(
            fileName: fileName,
            pageCount: 1,
            target: ProjectScanTarget(
                title: title ?? "图片附件-\(Formatters.date.string(from: Date()))",
                category: category,
                amount: .empty,
                linkedFinancialRecordId: linkedFinancialRecordId,
                linkedConstructionMethodIDs: [],
                note: note
            ),
            projectId: projectId,
            createdAt: createdAt,
            store: store,
            fileType: "jpg"
        )
        return nil
    }

    private static func documentSourceType(for ext: String) -> String {
        if ext == "pdf" { return "pdf" }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .image) {
            return "image"
        }
        return "file"
    }

    private static func tooLargeMessage(for url: URL, size: Int) -> String {
        ImportLimitPolicy.fileTooLargeMessage(fileName: url.lastPathComponent, size: size, limit: maxImportedDocumentBytes)
    }
}
