import Foundation
import UniformTypeIdentifiers

extension DataHealthView {
    func repairReferenceIssues() {
        let beforeCount = referenceIssueCount
        OperationAuditLog.record(
            action: .repair,
            outcome: .started,
            summary: l("修复引用与关联（不删原件）"),
            detail: String(format: l("%d 项"), beforeCount),
            source: "DataHealthView"
        )
        var repairedLogs = store.dailyLogs
        for index in repairedLogs.indices {
            if let fileName = repairedLogs[index].photoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedLogs[index].photoFileName = nil
            }
            repairedLogs[index].photos.removeAll { !PhotoStorage.exists(fileName: $0.fileName) }
        }
        store.replaceDailyLogs(repairedLogs)

        let missingDocumentIds = Set(
            store.projectDocuments
                .filter { !ProjectDocumentStorage.exists(fileName: $0.fileName) }
                .map(\.id)
        )
        if !missingDocumentIds.isEmpty {
            var projectDocuments = store.projectDocuments
            projectDocuments.removeAll { missingDocumentIds.contains($0.id) }
            store.replaceProjectDocuments(projectDocuments)
        }

        var repairedQuickNotes = store.quickNotes
        for index in repairedQuickNotes.indices {
            repairedQuickNotes[index].attachments.removeAll {
                !QuickNoteAttachmentStorage.exists(fileName: $0.fileName)
            }
        }
        store.replaceQuickNotes(repairedQuickNotes)

        var repairedTodos = store.siteTodos
        for index in repairedTodos.indices {
            if let fileName = repairedTodos[index].rectificationBeforePhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationBeforePhotoFileName = nil
            }
            if let fileName = repairedTodos[index].rectificationAfterPhotoFileName,
               !PhotoStorage.exists(fileName: fileName) {
                repairedTodos[index].rectificationAfterPhotoFileName = nil
            }
        }
        store.replaceSiteTodos(repairedTodos)

        let validDocumentIds = Set(store.projectDocuments.map(\.id))
        var financialRecords = store.projectFinancialRecords
        for index in financialRecords.indices {
            financialRecords[index].linkedDocumentIds.removeAll { !validDocumentIds.contains($0) }
        }
        store.replaceProjectFinancialRecords(financialRecords)

        var warehouseMovements = store.projectWarehouseMovements
        for index in warehouseMovements.indices {
            warehouseMovements[index].linkedDocumentIds.removeAll { !validDocumentIds.contains($0) }
        }
        store.replaceProjectWarehouseMovements(warehouseMovements)

        let validRecordIds = Set(store.projectFinancialRecords.map(\.id))
        var projectDocumentsForLinks = store.projectDocuments
        for index in projectDocumentsForLinks.indices {
            if let linkedId = projectDocumentsForLinks[index].linkedFinancialRecordId,
               !validRecordIds.contains(linkedId) {
                projectDocumentsForLinks[index].linkedFinancialRecordId = nil
            }
        }
        store.replaceProjectDocuments(projectDocumentsForLinks)

        let validProjectIds = Set(store.projects.map(\.id))
        var materialItems = store.materialItems
        for index in materialItems.indices where invalidOptionalProjectId(materialItems[index].projectId, validProjectIds: validProjectIds) {
            materialItems[index].projectId = nil
        }
        store.replaceMaterialItems(materialItems)

        var quoteItems = store.quoteItems
        for index in quoteItems.indices where invalidOptionalProjectId(quoteItems[index].projectId, validProjectIds: validProjectIds) {
            quoteItems[index].projectId = nil
        }
        store.replaceQuoteItems(quoteItems)

        var laborRecords = store.laborRecords
        for index in laborRecords.indices where invalidOptionalProjectId(laborRecords[index].projectId, validProjectIds: validProjectIds) {
            laborRecords[index].projectId = nil
        }
        store.replaceLaborRecords(laborRecords)

        var logs = store.dailyLogs
        for index in logs.indices where invalidOptionalProjectId(logs[index].projectId, validProjectIds: validProjectIds) {
            logs[index].projectId = nil
        }
        store.replaceDailyLogs(logs)

        var todos = store.siteTodos
        for index in todos.indices where invalidOptionalProjectId(todos[index].projectId, validProjectIds: validProjectIds) {
            todos[index].projectId = nil
        }
        store.replaceSiteTodos(todos)
        var quickNotes = store.quickNotes
        for index in quickNotes.indices where invalidOptionalProjectId(quickNotes[index].projectId, validProjectIds: validProjectIds) {
            quickNotes[index].projectId = nil
        }
        store.replaceQuickNotes(quickNotes)
        var lightingCircuitPlans = store.lightingCircuitPlans
        for index in lightingCircuitPlans.indices where invalidOptionalProjectId(
            lightingCircuitPlans[index].projectId,
            validProjectIds: validProjectIds
        ) {
            lightingCircuitPlans[index].projectId = nil
        }
        store.replaceLightingCircuitPlans(lightingCircuitPlans)

        store.scheduleSave()
        let afterCount = referenceIssueCount
        let fixedCount = max(beforeCount - afterCount, 0)
        OperationAuditLog.record(
            action: .repair,
            outcome: .succeeded,
            summary: l("修复"),
            detail: "\(String(format: l("%d 项"), fixedCount)) → \(String(format: l("%d 项"), afterCount))",
            source: "DataHealthView"
        )
    }

    func clearMediaThumbnailCaches() {
        PhotoStorage.clearThumbnailCache()
        QuickNoteAttachmentStorage.clearThumbnailCache()
        storageIssuesVersion = UUID()
    }

    func cleanupOrphanFiles() {
        let beforeCount = orphanFileIssueCount
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .started,
            summary: l("清理孤立原文件"),
            detail: String(format: l("%d 项"), beforeCount),
            source: "DataHealthView"
        )
        DataStoreDeferredFileCleanup.combined(
            summary: "dataHealth.cleanupOrphanFiles",
            cleanups: [
                DataStoreDeferredFileCleanup.photoFiles(
                    orphanPhotoFiles,
                    summary: "dataHealth.orphanPhotos"
                ),
                DataStoreDeferredFileCleanup.drawingFiles(
                    orphanDrawingFiles,
                    summary: "dataHealth.orphanDrawings"
                ),
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    orphanDocumentFiles,
                    summary: "dataHealth.orphanProjectDocuments"
                ),
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    orphanQuickNoteAttachmentFiles,
                    summary: "dataHealth.orphanQuickNoteAttachments"
                )
            ]
        )
        .perform()
        store.scheduleSave()
        let afterCount = orphanFileIssueCount
        let cleanedCount = max(beforeCount - afterCount, 0)
        OperationAuditLog.record(
            action: .cleanup,
            outcome: .succeeded,
            summary: l("清理"),
            detail: "\(String(format: l("%d 项"), cleanedCount)) → \(String(format: l("%d 项"), afterCount))",
            source: "DataHealthView"
        )
    }

    func exportHealthReport() {
        let sections: [(String, [String])] = [
            (l("缺失照片文件"), missingPhotoFileIssues.map(\.exportText)),
            (l("缺失票据文件"), missingDocumentFileIssues.map(\.exportText)),
            (l("缺失随手记附件"), missingQuickNoteAttachmentIssues.map(\.exportText)),
            (l("孤立照片文件"), orphanPhotoFileIssues.map(\.exportText)),
            (l("孤立图纸文件"), orphanDrawingFileIssues.map(\.exportText)),
            (l("孤立票据文件"), orphanDocumentFileIssues.map(\.exportText)),
            (l("孤立随手记附件"), orphanQuickNoteAttachmentIssues.map(\.exportText)),
            (l("孤立附件映射"), orphanAttachmentMappingIssues.map(\.exportText)),
            (l("仓库悬空附件映射"), orphanWarehouseAttachmentMappingIssues.map(\.exportText)),
            (l("资料悬空关联"), danglingDocumentLinkIssues.map(\.exportText)),
            (l("无效项目关联（可自动修复）"), autoFixableInvalidProjectRefIssues.map(\.exportText)),
            (l("无效项目关联（需手动处理）"), manualInvalidProjectRefIssues.map(\.exportText)),
            (l("存储错误记录"), storageIssueRows.map(\.exportText))
        ]
        var lines = [
            lf("%@ 数据健康报告", AppBrand.displayName),
            lf("生成时间: %@", Formatters.now()),
            lf("问题总数: %d", totalIssues),
            ""
        ]
        for (title, items) in sections {
            lines.append("[\(title)] \(items.count)")
            if items.isEmpty {
                lines.append(l("未发现问题"))
            } else {
                lines.append(contentsOf: items)
            }
            lines.append("")
        }
        exportPayload = ExportPayload(
            data: Data(lines.joined(separator: "\n").utf8),
            contentType: .plainText,
            defaultFilename: l("数据健康报告.txt")
        )
        showExporter = true
    }

    private func invalidOptionalProjectId(_ id: UUID?, validProjectIds: Set<UUID>) -> Bool {
        guard let id else { return false }
        return !validProjectIds.contains(id)
    }
}
