import Foundation

@MainActor
extension DataStore {
    func makeCloudBackupSnapshot(options: CloudBackupContentOptions) -> BackupSnapshot {
        makeSnapshot(includePhotoFiles: false)
            .applyingCloudBackupContentOptions(options.normalized())
    }
}

extension BackupSnapshot {
    func applyingCloudBackupContentOptions(_ options: CloudBackupContentOptions) -> BackupSnapshot {
        let normalizedOptions = options.normalized()
        var snapshot = self

        if !normalizedOptions.includeBusinessRecords {
            snapshot.materialItems = []
            snapshot.quoteItems = []
            snapshot.laborRecords = []
            snapshot.historyRecords = []
        }

        if !normalizedOptions.includeProjectRecords {
            snapshot.projects = []
            snapshot.dailyLogs = []
            snapshot.progressTasks = []
            snapshot.siteTodos = []
            snapshot.projectContacts = []
            snapshot.projectFinancialRecords = []
            snapshot.projectWarehouseMovements = []
        }

        if !normalizedOptions.includeProjectFilesAndNotes {
            snapshot.projectDrawings = []
            snapshot.projectDocuments = []
            snapshot.quickNotes = []
        }

        if !normalizedOptions.includeKnowledgeBase {
            snapshot.templates = []
            snapshot.materialPriceEntries = []
            snapshot.supplierProfiles = []
            snapshot.constructionMethods = []
            snapshot.favoriteMaterialKeys = []
            snapshot.recentMaterialKeys = []
        }

        var excludedDateCollections = Set<String>()
        if !normalizedOptions.includeBusinessRecords {
            excludedDateCollections.formUnion(["materialItems", "quoteItems", "laborRecords", "historyRecords"])
        }
        if !normalizedOptions.includeProjectRecords {
            excludedDateCollections.formUnion(["projects", "dailyLogs", "progressTasks", "siteTodos",
                                              "projectFinancialRecords", "projectWarehouseMovements"])
        }
        if !normalizedOptions.includeProjectFilesAndNotes {
            excludedDateCollections.formUnion(["projectDrawings", "projectDocuments", "quickNotes"])
        }
        if !normalizedOptions.includeKnowledgeBase {
            excludedDateCollections.formUnion(["materialPriceEntries", "supplierProfiles", "constructionMethods"])
        }
        snapshot.legacyDateProvenance.removeAll {
            excludedDateCollections.contains(String($0.path.split(separator: "/").first ?? ""))
        }
        snapshot.removeExcludedReferenceLinks()

        if !normalizedOptions.includeAttachments {
            snapshot.dailyLogs = snapshot.dailyLogs.map { log in
                var value = log
                value.photoFileName = nil
                value.photos = []
                return value
            }
            snapshot.siteTodos = snapshot.siteTodos.map { todo in
                var value = todo
                value.rectificationBeforePhotoFileName = nil
                value.rectificationAfterPhotoFileName = nil
                return value
            }
            snapshot.quickNotes = snapshot.quickNotes.map { note in
                var value = note
                value.attachments = []
                return value
            }
            snapshot.constructionMethods = snapshot.constructionMethods.map { method in
                var value = method
                value.attachments = []
                value.tutorialAttachments = []
                return value
            }
            // 图纸与项目资料的 fileName 会被归档写入器用来读取原件。关闭附件时，
            // 不能只清空 BackupFile 数组，否则仍会把这些原件上传到云端。
            snapshot.projectDrawings = snapshot.projectDrawings.map { drawing in
                var value = drawing
                value.fileName = ""
                return value
            }
            snapshot.projectDocuments = snapshot.projectDocuments.map { document in
                var value = document
                value.fileName = ""
                return value
            }
            snapshot.photoFiles = []
            snapshot.drawingFiles = []
            snapshot.documentFiles = []
            snapshot.quickNoteAttachmentFiles = []
            return snapshot
        }

        let photoNames = Set(
            snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty }
        )
        let drawingNames = Set(snapshot.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let documentNames = Set(snapshot.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let quickNoteAttachmentNames = snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let constructionAttachmentNames = snapshot.constructionMethods.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let tutorialAttachmentNames = snapshot.constructionMethods.flatMap { $0.tutorialAttachments.map(\.fileName) }.filter { !$0.isEmpty }
        let attachmentNames = Set(quickNoteAttachmentNames + constructionAttachmentNames + tutorialAttachmentNames)

        snapshot.photoFiles = snapshot.photoFiles.filter { photoNames.contains($0.fileName) }
        snapshot.drawingFiles = snapshot.drawingFiles.filter { drawingNames.contains($0.fileName) }
        snapshot.documentFiles = snapshot.documentFiles.filter { documentNames.contains($0.fileName) }
        snapshot.quickNoteAttachmentFiles = snapshot.quickNoteAttachmentFiles.filter { attachmentNames.contains($0.fileName) }
        return snapshot
    }

    private mutating func removeExcludedReferenceLinks() {
        let projectIDs = Set(projects.map(\.id))
        let constructionMethodIDs = Set(constructionMethods.map(\.id))
        let documentProjectIDs = Dictionary(uniqueKeysWithValues: projectDocuments.map { ($0.id, $0.projectId) })
        let financialRecordProjectIDs = Dictionary(uniqueKeysWithValues: projectFinancialRecords.map { ($0.id, $0.projectId) })

        func validProject(_ id: UUID?) -> UUID? {
            guard let id, projectIDs.contains(id) else { return nil }
            return id
        }

        materialItems = materialItems.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        quoteItems = quoteItems.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        laborRecords = laborRecords.map { item in
            var value = item
            value.projectId = validProject(value.projectId)
            return value
        }
        historyRecords = historyRecords.map { record in
            var value = record
            value.projectId = validProject(value.projectId)
            return value
        }
        quickNotes = quickNotes.map { note in
            var value = note
            value.projectId = validProject(value.projectId)
            return value
        }
        materialSheetDrafts = materialSheetDrafts.map { draft in
            var value = draft
            value.projectId = validProject(value.projectId)
            return value
        }
        dailyLogs = dailyLogs.map { log in
            var value = log
            value.projectId = validProject(value.projectId)
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            return value
        }
        siteTodos = siteTodos.map { todo in
            var value = todo
            value.projectId = validProject(value.projectId)
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            return value
        }
        projectContacts = projectContacts.map { contact in
            var value = contact
            value.relatedProjectIds = value.relatedProjectIds.filter(projectIDs.contains)
            return value
        }
        projectFinancialRecords = projectFinancialRecords.map { record in
            var value = record
            value.linkedDocumentIds = value.linkedDocumentIds.filter { documentProjectIDs[$0] == value.projectId }
            return value
        }
        projectWarehouseMovements = projectWarehouseMovements.map { movement in
            var value = movement
            value.linkedDocumentIds = value.linkedDocumentIds.filter { documentProjectIDs[$0] == value.projectId }
            return value
        }
        projectDocuments = projectDocuments.map { document in
            var value = document
            if let linkedFinancialRecordId = value.linkedFinancialRecordId,
               financialRecordProjectIDs[linkedFinancialRecordId] != value.projectId {
                value.linkedFinancialRecordId = nil
            }
            value.linkedConstructionMethodIDs = value.linkedConstructionMethodIDs.filter(constructionMethodIDs.contains)
            value.replacesDocumentId = value.replacesDocumentId.flatMap {
                documentProjectIDs[$0] == value.projectId ? $0 : nil
            }
            value.replacedByDocumentId = value.replacedByDocumentId.flatMap {
                documentProjectIDs[$0] == value.projectId ? $0 : nil
            }
            return value
        }
    }
}

extension BackupSnapshot {
    var hasAnyBackupContent: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
        !siteTodos.isEmpty ||
        !projectDrawings.isEmpty ||
        !projectContacts.isEmpty ||
        !projectFinancialRecords.isEmpty ||
        !projectDocuments.isEmpty ||
        !quickNotes.isEmpty ||
        !projectWarehouseMovements.isEmpty ||
        !templates.isEmpty ||
        !materialPriceEntries.isEmpty ||
        !supplierProfiles.isEmpty ||
        !constructionMethods.isEmpty ||
        !favoriteMaterialKeys.isEmpty ||
        !recentMaterialKeys.isEmpty ||
        !userMaterials.isEmpty ||
        !deletedUserMaterials.isEmpty ||
        !hiddenPresetKeys.isEmpty
    }
}
