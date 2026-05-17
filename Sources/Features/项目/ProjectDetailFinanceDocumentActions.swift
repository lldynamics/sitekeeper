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

    enum LinkedDocumentCleanupMode {
        case deferred
        case immediate
    }

    struct FinancialRecordDeletionExecution {
        let financialDeletion: DataStoreRemovalResult<ProjectFinancialRecord>
        let removableDocumentFileNames: [String]
        let linkedDocumentCount: Int
    }

    struct DocumentDeletionExecution {
        let documentDeletion: DataStoreRemovalResult<ProjectDocument>
        let removableDocumentFileNames: [String]
    }

    @MainActor
    static func executeDocumentDeletion(
        ids: Set<UUID>,
        store: DataStore,
        documentCleanupMode: LinkedDocumentCleanupMode,
        audit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DocumentDeletionExecution? {
        guard !ids.isEmpty else { return nil }
        let targets = store.projectDocuments.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return nil }

        let removableFileNames = targets.map(\.fileName)
        let deferredFileCleanup: DataStoreDeferredFileCleanup?
        switch documentCleanupMode {
        case .deferred:
            deferredFileCleanup = nil
        case .immediate:
            deferredFileCleanup = DataStoreDeferredFileCleanup.projectDocumentFiles(
                removableFileNames,
                summary: "projectDetail.documentFile"
            )
        }

        let documentDeletion = store.removeProjectDocuments(
            ids: ids,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
        guard !documentDeletion.isEmpty else { return nil }

        var financialRecords = store.projectFinancialRecords
        for index in financialRecords.indices {
            financialRecords[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        store.replaceProjectFinancialRecords(financialRecords)

        var warehouseMovements = store.projectWarehouseMovements
        for index in warehouseMovements.indices {
            warehouseMovements[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        store.replaceProjectWarehouseMovements(warehouseMovements)
        return DocumentDeletionExecution(
            documentDeletion: documentDeletion,
            removableDocumentFileNames: removableFileNames
        )
    }

    @MainActor
    static func executeFinancialRecordDeletion(
        ids: Set<UUID>,
        deleteLinkedDocuments: Bool,
        store: DataStore,
        documentCleanupMode: LinkedDocumentCleanupMode,
        financialAudit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> FinancialRecordDeletionExecution? {
        guard !ids.isEmpty else { return nil }

        let recordsToDelete = store.projectFinancialRecords.filter { ids.contains($0.id) }
        guard !recordsToDelete.isEmpty else { return nil }
        let linkedDocumentIds = Set(recordsToDelete.flatMap(\.linkedDocumentIds))
        let linkedByRecordFieldIds: Set<UUID> = Set(
            store.projectDocuments.compactMap { document in
                guard let linkedId = document.linkedFinancialRecordId, ids.contains(linkedId) else { return nil }
                return document.id
            }
        )
        let targetDocumentIds = linkedDocumentIds.union(linkedByRecordFieldIds)

        var removableFileNames: [String] = []
        if deleteLinkedDocuments {
            if !targetDocumentIds.isEmpty {
                removableFileNames = store.projectDocuments
                    .filter { targetDocumentIds.contains($0.id) }
                    .map(\.fileName)

                let deferredFileCleanup: DataStoreDeferredFileCleanup?
                switch documentCleanupMode {
                case .deferred:
                    deferredFileCleanup = nil
                case .immediate:
                    deferredFileCleanup = DataStoreDeferredFileCleanup.projectDocumentFiles(
                        removableFileNames,
                        summary: "projectDetail.financialLinkedDocumentFiles"
                    )
                }
                store.removeProjectDocuments(
                    ids: targetDocumentIds,
                    deferredFileCleanup: deferredFileCleanup,
                    recordsAuditImmediately: recordsAuditImmediately
                )
                var financialRecords = store.projectFinancialRecords
                for index in financialRecords.indices {
                    financialRecords[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                store.replaceProjectFinancialRecords(financialRecords)

                var warehouseMovements = store.projectWarehouseMovements
                for index in warehouseMovements.indices {
                    warehouseMovements[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                store.replaceProjectWarehouseMovements(warehouseMovements)
            }
        } else if !targetDocumentIds.isEmpty {
            var projectDocuments = store.projectDocuments
            for index in projectDocuments.indices {
                guard targetDocumentIds.contains(projectDocuments[index].id) else { continue }
                projectDocuments[index].linkedFinancialRecordId = nil
            }
            store.replaceProjectDocuments(projectDocuments)
        }

        let financialDeletion = store.removeProjectFinancialRecords(
            ids: ids,
            audit: financialAudit,
            recordsAuditImmediately: recordsAuditImmediately
        )
        guard !financialDeletion.isEmpty else { return nil }
        return FinancialRecordDeletionExecution(
            financialDeletion: financialDeletion,
            removableDocumentFileNames: removableFileNames,
            linkedDocumentCount: targetDocumentIds.count
        )
    }

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
        let detailParts = [document.title, document.fileName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let audit = DataStoreDeletionAuditContext(
            summary: String(localized: "删除票据资料 1 条"),
            detail: detailParts.joined(separator: " · "),
            source: "ProjectDetailFinanceDocumentActions"
        )
        guard executeDocumentDeletion(
            ids: Set([document.id]),
            store: store,
            documentCleanupMode: .immediate,
            audit: audit,
            recordsAuditImmediately: true
        ) != nil else { return }
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
        guard !recordsToDelete.isEmpty else { return }
        let linkedDocumentCount = Set(recordsToDelete.flatMap(\.linkedDocumentIds))
            .union(
                Set(
                    store.projectDocuments.compactMap { document in
                        guard let linkedId = document.linkedFinancialRecordId, ids.contains(linkedId) else { return nil }
                        return document.id
                    }
                )
            )
            .count
        let financialAudit = DataStoreDeletionAuditContext(
            summary: deleteLinkedDocuments ? String(localized: "删除账目（含票据）") : String(localized: "删除账目"),
            detail: String(
                format: String(localized: "账目 %lld 条，关联票据 %lld 条"),
                Int64(recordsToDelete.count),
                Int64(linkedDocumentCount)
            ),
            source: "ProjectDetailFinanceDocumentActions"
        )
        guard executeFinancialRecordDeletion(
            ids: ids,
            deleteLinkedDocuments: deleteLinkedDocuments,
            store: store,
            documentCleanupMode: .immediate,
            financialAudit: financialAudit,
            recordsAuditImmediately: true
        ) != nil else { return }
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
                    amount: "",
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
                amount: "",
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
                amount: "",
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
        } else {
            _ = store.mutateProjectFinancialRecord(id: record.id) { value in
                value.linkedDocumentIds.removeAll { $0 == document.id }
            }
        }
        store.scheduleSave()
    }

    @MainActor
    static func saveDocumentEdit(_ updated: ProjectDocument, store: DataStore) {
        guard let index = store.projectDocuments.firstIndex(where: { $0.id == updated.id }) else { return }
        let previous = store.projectDocuments[index]
        var normalized = updated
        normalized.versionNumber = max(1, normalized.versionNumber)
        if normalized.replacesDocumentId == normalized.id {
            normalized.replacesDocumentId = nil
        }
        if normalized.replacedByDocumentId == normalized.id {
            normalized.replacedByDocumentId = nil
        }
        if let previousVersionId = normalized.replacesDocumentId,
           let previousVersion = store.projectDocuments.first(where: { $0.id == previousVersionId }) {
            if previousVersion.replacesDocumentId == normalized.id {
                normalized.replacesDocumentId = nil
            } else if normalized.versionNumber <= previousVersion.normalizedVersionNumber {
                normalized.versionNumber = min(999, previousVersion.normalizedVersionNumber + 1)
            }
        }
        store.updateProjectDocument(normalized)
        reconcileDocumentVersionLinks(
            document: normalized,
            previousReplacesDocumentId: previous.replacesDocumentId,
            store: store
        )
        relinkDocument(documentId: normalized.id, to: normalized.linkedFinancialRecordId, store: store)
        store.scheduleSave()
    }

    @MainActor
    @discardableResult
    private static func appendProjectDocument(
        fileName: String,
        pageCount: Int,
        target: ProjectScanTarget,
        projectId: UUID,
        createdAt: String = Formatters.now(),
        store: DataStore,
        fileType: String = "pdf"
    ) -> ProjectDocument {
        let document = ProjectDocument(
            projectId: projectId,
            title: target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.category.displayName : target.title,
            category: target.category,
            fileName: fileName,
            fileType: fileType,
            pageCount: pageCount,
            amount: target.amount,
            linkedFinancialRecordId: target.linkedFinancialRecordId,
            linkedConstructionMethodIDs: target.linkedConstructionMethodIDs,
            submissionStatus: target.submissionStatus,
            responsiblePerson: target.responsiblePerson,
            formedAt: target.formedAt,
            archiveNumber: target.archiveNumber,
            workSection: target.workSection,
            createdAt: createdAt,
            note: target.note
        )
        store.appendProjectDocument(document)
        if let recordId = target.linkedFinancialRecordId {
            _ = store.mutateProjectFinancialRecord(id: recordId) { record in
                if !record.linkedDocumentIds.contains(document.id) {
                    record.linkedDocumentIds.append(document.id)
                }
            }
        }
        store.scheduleSave()
        return document
    }

    @MainActor
    private static func relinkDocument(documentId: UUID, to recordId: UUID?, store: DataStore) {
        var financialRecords = store.projectFinancialRecords
        for index in financialRecords.indices {
            financialRecords[index].linkedDocumentIds.removeAll { $0 == documentId }
        }
        let validRecordId: UUID?
        if let recordId,
           let recordIndex = financialRecords.firstIndex(where: { $0.id == recordId }) {
            if !financialRecords[recordIndex].linkedDocumentIds.contains(documentId) {
                financialRecords[recordIndex].linkedDocumentIds.append(documentId)
            }
            validRecordId = recordId
        } else {
            validRecordId = nil
        }
        store.replaceProjectFinancialRecords(financialRecords)
        _ = store.mutateProjectDocument(id: documentId) { document in
            document.linkedFinancialRecordId = validRecordId
        }
    }

    @MainActor
    private static func reconcileDocumentVersionLinks(
        document: ProjectDocument,
        previousReplacesDocumentId: UUID?,
        store: DataStore
    ) {
        if let previousReplacesDocumentId,
           previousReplacesDocumentId != document.replacesDocumentId {
            _ = store.mutateProjectDocument(id: previousReplacesDocumentId) { previousVersion in
                guard previousVersion.replacedByDocumentId == document.id else { return }
                previousVersion.replacedByDocumentId = nil
                if previousVersion.versionState == .superseded {
                    previousVersion.versionState = .current
                }
            }
        }

        guard let previousVersionId = document.replacesDocumentId else { return }
        _ = store.mutateProjectDocument(id: previousVersionId) { previousVersion in
            previousVersion.replacedByDocumentId = document.id
            if previousVersion.versionState == .current {
                previousVersion.versionState = .superseded
            }
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
