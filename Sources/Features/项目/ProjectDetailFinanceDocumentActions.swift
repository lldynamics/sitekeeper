import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum ProjectDetailActionResult<Value> {
    case success(Value)
    case failure(String)
}

enum ProjectDetailFinanceDocumentActions {
    private static let maxImportedDocumentBytes = ImportLimitPolicy.maxImportBytes

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
    static func deleteDocument(_ document: ProjectDocument, store: DataStore) {
        ProjectDocumentStorage.delete(fileName: document.fileName)
        store.projectDocuments.removeAll { $0.id == document.id }
        for index in store.projectFinancialRecords.indices {
            store.projectFinancialRecords[index].linkedDocumentIds.removeAll { $0 == document.id }
        }
        for index in store.projectWarehouseMovements.indices {
            store.projectWarehouseMovements[index].linkedDocumentIds.removeAll { $0 == document.id }
        }
        store.scheduleSave()
    }

    @MainActor
    static func deleteFinancialRecord(
        _ record: ProjectFinancialRecord,
        deleteLinkedDocuments: Bool,
        store: DataStore
    ) {
        deleteFinancialRecords(ids: Set([record.id]), deleteLinkedDocuments: deleteLinkedDocuments, store: store)
    }

    @MainActor
    static func deleteFinancialRecords(
        ids: Set<UUID>,
        deleteLinkedDocuments: Bool,
        store: DataStore
    ) {
        guard !ids.isEmpty else { return }
        let recordsToDelete = store.projectFinancialRecords.filter { ids.contains($0.id) }
        let linkedDocumentIds = Set(recordsToDelete.flatMap(\.linkedDocumentIds))
        let linkedByRecordFieldIds: Set<UUID> = Set(
            store.projectDocuments.compactMap { document in
                guard let linkedId = document.linkedFinancialRecordId, ids.contains(linkedId) else { return nil }
                return document.id
            }
        )
        let targetDocumentIds = linkedDocumentIds.union(linkedByRecordFieldIds)

        if deleteLinkedDocuments {
            if !targetDocumentIds.isEmpty {
                for document in store.projectDocuments where targetDocumentIds.contains(document.id) {
                    ProjectDocumentStorage.delete(fileName: document.fileName)
                }
                store.projectDocuments.removeAll { targetDocumentIds.contains($0.id) }
                for index in store.projectFinancialRecords.indices {
                    store.projectFinancialRecords[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                for index in store.projectWarehouseMovements.indices {
                    store.projectWarehouseMovements[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
            }
        } else if !targetDocumentIds.isEmpty {
            for index in store.projectDocuments.indices {
                guard targetDocumentIds.contains(store.projectDocuments[index].id) else { continue }
                store.projectDocuments[index].linkedFinancialRecordId = nil
            }
        }

        store.projectFinancialRecords.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    @MainActor
    static func migrateLegacyPayments(project: Project, legacyPayments: [PaymentRecord], store: DataStore) {
        guard !legacyPayments.isEmpty else { return }
        let migrated = legacyPayments.map { item in
            ProjectFinancialRecord(
                projectId: project.id,
                date: item.date,
                direction: ProjectFinancialDirection.income.rawValue,
                category: ProjectFinancialCategory.collection.rawValue,
                amount: item.amount,
                counterparty: project.customerName,
                invoiceNumber: item.isInvoiced ? "已开票" : "",
                note: [item.method, item.note].filter { !$0.isEmpty }.joined(separator: " · ")
            )
        }
        store.projectFinancialRecords.append(contentsOf: migrated)
        let ids = Set(legacyPayments.map(\.id))
        store.paymentRecords.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    static func linkedDocuments(for record: ProjectFinancialRecord, documents: [ProjectDocument]) -> [ProjectDocument] {
        guard !record.linkedDocumentIds.isEmpty else { return [] }
        let idSet = Set(record.linkedDocumentIds)
        return documents.filter { idSet.contains($0.id) }
    }

    @MainActor
    static func importProjectDocuments(
        _ urls: [URL],
        projectId: UUID,
        linkedFinancialRecordId: UUID? = nil,
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
                category = .invoice
                do {
                    fileName = try ProjectDocumentStorage.saveImportedFileOrThrow(from: url, projectId: projectId, fileExtension: fileType)
                } catch {
                    failures.append("\(url.lastPathComponent)（保存失败）")
                    continue
                }
            } else if sourceType == "image" {
                pageCount = 1
                fileType = ext.isEmpty ? "jpg" : ext
                category = .receipt
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
            appendProjectDocument(
                fileName: fileName,
                pageCount: pageCount,
                target: ProjectScanTarget(
                    title: url.deletingPathExtension().lastPathComponent,
                    category: category,
                    amount: "",
                    linkedFinancialRecordId: linkedFinancialRecordId,
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
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName: String
        do {
            fileName = try ProjectDocumentStorage.saveDataOrThrow(data: data, projectId: projectId, fileExtension: ext.isEmpty ? "dat" : ext)
        } catch {
            return "附件保存失败：\(error.localizedDescription)"
        }
        appendProjectDocument(
            fileName: fileName,
            pageCount: 1,
            target: ProjectScanTarget(
                title: title,
                category: category,
                amount: "",
                linkedFinancialRecordId: linkedFinancialRecordId,
                note: note
            ),
            projectId: projectId,
            store: store,
            fileType: ext.isEmpty ? "dat" : ext
        )
        return nil
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
                amount: "",
                linkedFinancialRecordId: linkedFinancialRecordId,
                note: note
            ),
            projectId: projectId,
            createdAt: createdAt,
            store: store,
            fileType: "jpg"
        )
        return nil
    }

    @MainActor
    static func attachDocument(_ document: ProjectDocument, to record: ProjectFinancialRecord, store: DataStore) {
        guard store.projectDocuments.contains(where: { $0.id == document.id }),
              store.projectFinancialRecords.contains(where: { $0.id == record.id }) else { return }
        relinkDocument(documentId: document.id, to: record.id, store: store)
        store.scheduleSave()
    }

    @MainActor
    static func detachDocument(_ document: ProjectDocument, from record: ProjectFinancialRecord, store: DataStore) {
        guard store.projectDocuments.contains(where: { $0.id == document.id }),
              store.projectFinancialRecords.contains(where: { $0.id == record.id }) else { return }
        if document.linkedFinancialRecordId == record.id {
            relinkDocument(documentId: document.id, to: nil, store: store)
        } else if let index = store.projectFinancialRecords.firstIndex(where: { $0.id == record.id }) {
            store.projectFinancialRecords[index].linkedDocumentIds.removeAll { $0 == document.id }
        }
        store.scheduleSave()
    }

    @MainActor
    static func saveDocumentEdit(_ updated: ProjectDocument, store: DataStore) {
        guard let index = store.projectDocuments.firstIndex(where: { $0.id == updated.id }) else { return }
        store.projectDocuments[index] = updated
        relinkDocument(documentId: updated.id, to: updated.linkedFinancialRecordId, store: store)
        store.scheduleSave()
    }

    @MainActor
    private static func appendProjectDocument(
        fileName: String,
        pageCount: Int,
        target: ProjectScanTarget,
        projectId: UUID,
        createdAt: String = Formatters.now(),
        store: DataStore,
        fileType: String = "pdf"
    ) {
        let document = ProjectDocument(
            projectId: projectId,
            title: target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.category.rawValue : target.title,
            category: target.category.rawValue,
            fileName: fileName,
            fileType: fileType,
            pageCount: pageCount,
            amount: target.amount,
            linkedFinancialRecordId: target.linkedFinancialRecordId,
            createdAt: createdAt,
            note: target.note
        )
        store.projectDocuments.append(document)
        if let recordId = target.linkedFinancialRecordId,
           let index = store.projectFinancialRecords.firstIndex(where: { $0.id == recordId }) {
            if !store.projectFinancialRecords[index].linkedDocumentIds.contains(document.id) {
                store.projectFinancialRecords[index].linkedDocumentIds.append(document.id)
            }
        }
        store.scheduleSave()
    }

    @MainActor
    private static func relinkDocument(documentId: UUID, to recordId: UUID?, store: DataStore) {
        for index in store.projectFinancialRecords.indices {
            store.projectFinancialRecords[index].linkedDocumentIds.removeAll { $0 == documentId }
        }
        let validRecordId: UUID?
        if let recordId,
           let recordIndex = store.projectFinancialRecords.firstIndex(where: { $0.id == recordId }) {
            if !store.projectFinancialRecords[recordIndex].linkedDocumentIds.contains(documentId) {
                store.projectFinancialRecords[recordIndex].linkedDocumentIds.append(documentId)
            }
            validRecordId = recordId
        } else {
            validRecordId = nil
        }
        if let documentIndex = store.projectDocuments.firstIndex(where: { $0.id == documentId }) {
            store.projectDocuments[documentIndex].linkedFinancialRecordId = validRecordId
        }
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
