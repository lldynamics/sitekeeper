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

        snapshot.removeExcludedCollections(normalizedOptions)

        snapshot.removeExcludedDateProvenance(normalizedOptions)
        snapshot.removeExcludedReferenceLinks()

        if !normalizedOptions.includeAttachments {
            snapshot.removeAttachmentReferences()
            return snapshot
        }

        snapshot.filterEmbeddedFilesToReferences()
        return snapshot
    }

    private mutating func removeExcludedCollections(_ options: CloudBackupContentOptions) {
        if !options.includeBusinessRecords {
            materialItems = []
            quoteItems = []
            laborRecords = []
            historyRecords = []
        }

        if !options.includeProjectRecords {
            projects = []
            dailyLogs = []
            progressTasks = []
            siteTodos = []
            projectContacts = []
            projectFinancialRecords = []
            projectWarehouseMovements = []
        }

        if !options.includeProjectFilesAndNotes {
            projectDrawings = []
            projectDocuments = []
            quickNotes = []
        }

        if !options.includeKnowledgeBase {
            templates = []
            materialPriceEntries = []
            supplierProfiles = []
            constructionMethods = []
            favoriteMaterialKeys = []
            recentMaterialKeys = []
        }
    }

    private mutating func removeExcludedDateProvenance(_ options: CloudBackupContentOptions) {
        var excludedDateCollections = Set<String>()
        if !options.includeBusinessRecords {
            excludedDateCollections.formUnion(["materialItems", "quoteItems", "laborRecords", "historyRecords"])
        }
        if !options.includeProjectRecords {
            excludedDateCollections.formUnion(["projects", "dailyLogs", "progressTasks", "siteTodos",
                                              "projectFinancialRecords", "projectWarehouseMovements"])
        }
        if !options.includeProjectFilesAndNotes {
            excludedDateCollections.formUnion(["projectDrawings", "projectDocuments", "quickNotes"])
        }
        if !options.includeKnowledgeBase {
            excludedDateCollections.formUnion(["materialPriceEntries", "supplierProfiles", "constructionMethods"])
        }
        legacyDateProvenance.removeAll {
            excludedDateCollections.contains(String($0.path.split(separator: "/").first ?? ""))
        }
    }

    private mutating func removeAttachmentReferences() {
        dailyLogs = dailyLogs.map { log in
            var value = log
            value.photoFileName = nil
            value.photos = []
            return value
        }
        siteTodos = siteTodos.map { todo in
            var value = todo
            value.rectificationBeforePhotoFileName = nil
            value.rectificationAfterPhotoFileName = nil
            return value
        }
        quickNotes = quickNotes.map { note in
            var value = note
            value.attachments = []
            return value
        }
        constructionMethods = constructionMethods.map { method in
            var value = method
            value.attachments = []
            value.tutorialAttachments = []
            return value
        }
        // 图纸与项目资料的 fileName 会被归档写入器用来读取原件。关闭附件时，
        // 不能只清空 BackupFile 数组，否则仍会把这些原件上传到云端。
        projectDrawings = projectDrawings.map { drawing in
            var value = drawing
            value.fileName = ""
            return value
        }
        projectDocuments = projectDocuments.map { document in
            var value = document
            value.fileName = ""
            return value
        }
        photoFiles = []
        drawingFiles = []
        documentFiles = []
        quickNoteAttachmentFiles = []
    }

    private mutating func filterEmbeddedFilesToReferences() {
        let photoNames = Set(
            dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty }
                + siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty }
                + siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty }
        )
        let drawingNames = Set(projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let documentNames = Set(projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let quickNoteAttachmentNames = quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let constructionAttachmentNames = constructionMethods.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty }
        let tutorialAttachmentNames = constructionMethods.flatMap { $0.tutorialAttachments.map(\.fileName) }.filter { !$0.isEmpty }
        let attachmentNames = Set(quickNoteAttachmentNames + constructionAttachmentNames + tutorialAttachmentNames)

        photoFiles = photoFiles.filter { photoNames.contains($0.fileName) }
        drawingFiles = drawingFiles.filter { drawingNames.contains($0.fileName) }
        documentFiles = documentFiles.filter { documentNames.contains($0.fileName) }
        quickNoteAttachmentFiles = quickNoteAttachmentFiles.filter { attachmentNames.contains($0.fileName) }
    }

    private mutating func removeExcludedProjectLinks(projectIDs: Set<UUID>) {
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
    }

    private mutating func removeExcludedKnowledgeLinks(projectIDs: Set<UUID>, constructionMethodIDs: Set<UUID>) {
        func validProject(_ id: UUID?) -> UUID? {
            guard let id, projectIDs.contains(id) else { return nil }
            return id
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
    }

    private mutating func removeExcludedReferenceLinks() {
        let projectIDs = Set(projects.map(\.id))
        let constructionMethodIDs = Set(constructionMethods.map(\.id))
        let documentProjectIDs = Dictionary(uniqueKeysWithValues: projectDocuments.map { ($0.id, $0.projectId) })
        let financialRecordProjectIDs = Dictionary(uniqueKeysWithValues: projectFinancialRecords.map { ($0.id, $0.projectId) })

        removeExcludedProjectLinks(projectIDs: projectIDs)
        removeExcludedKnowledgeLinks(projectIDs: projectIDs, constructionMethodIDs: constructionMethodIDs)
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
