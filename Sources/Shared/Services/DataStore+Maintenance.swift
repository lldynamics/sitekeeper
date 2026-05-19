import Foundation

extension DataStore {
    func clearAllBusinessData(deleteStoredFiles: Bool = true) {
        cancelScheduledSave()
        if deleteStoredFiles {
            DataStoreDeferredFileCleanup.combined(
                summary: "dataStore.clearAllBusinessData",
                cleanups: [
                    DataStoreDeferredFileCleanup.photoFiles(
                        PhotoStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.photos"
                    ),
                    DataStoreDeferredFileCleanup.drawingFiles(
                        DrawingStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.drawings"
                    ),
                    DataStoreDeferredFileCleanup.projectDocumentFiles(
                        ProjectDocumentStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.projectDocuments"
                    ),
                    DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                        QuickNoteAttachmentStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.quickNoteAttachments"
                    )
                ]
            )
            .perform()
            StorageIssueLog.clear()
        }
        clearAllData()
        save(includePhotoFiles: false)
    }

    func clearAllBusinessDataAsync(
        deleteStoredFiles: Bool = true,
        onProgress: (@MainActor (String) -> Void)? = nil
    ) async {
        cancelScheduledSave()
        if deleteStoredFiles {
            let photoNames = PhotoStorage.allStoredFileNames()
            let drawingNames = DrawingStorage.allStoredFileNames()
            let documentNames = ProjectDocumentStorage.allStoredFileNames()
            let attachmentNames = QuickNoteAttachmentStorage.allStoredFileNames()

            onProgress?(String(localized: "正在并行删除照片/图纸/资料/附件"))
            async let deletePhotos: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.photoFiles(
                    photoNames,
                    summary: "dataStore.clearAllAsync.photos"
                )?.perform()
            }.value
            async let deleteDrawings: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.drawingFiles(
                    drawingNames,
                    summary: "dataStore.clearAllAsync.drawings"
                )?.perform()
            }.value
            async let deleteDocuments: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    documentNames,
                    summary: "dataStore.clearAllAsync.projectDocuments"
                )?.perform()
            }.value
            async let deleteAttachments: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    attachmentNames,
                    summary: "dataStore.clearAllAsync.quickNoteAttachments"
                )?.perform()
            }.value
            _ = await (deletePhotos, deleteDrawings, deleteDocuments, deleteAttachments)

            onProgress?(String(localized: "正在清理日志"))
            await Task.detached(priority: .utility) {
                StorageIssueLog.clear()
            }.value
        }

        onProgress?(String(localized: "正在写入空数据"))
        clearAllData()
        save(includePhotoFiles: false)
        onProgress?(String(localized: "清空完成"))
    }

    func refreshSearchIndexVersion() {
        searchIndexVersion &+= 1
    }

    private func clearAllData() {
        replaceMaterialItems([])
        replaceQuoteItems([])
        replaceLaborRecords([])
        replaceProjects([])
        replaceDailyLogs([])
        replaceHistoryRecords([])
        replaceProgressTasks([])
        replaceSiteTodos([])
        replaceProjectDrawings([])
        replaceProjectContacts([])
        replaceProjectFinancialRecords([])
        replaceProjectDocuments([])
        replaceQuickNotes([])
        replaceProjectWarehouseMovements([])
        replaceTemplates([])
        replaceMaterialPriceEntries([])
        replaceMaterialSheetDrafts([])
        replaceSupplierProfiles([])
        replaceConstructionMethods([])
        favoriteMaterialKeys = []
        recentMaterialKeys = []
        replaceUserMaterials([])
        replaceDeletedUserMaterials([])
        hiddenPresetKeys = []
        refreshSearchIndexVersion()
        dataVersion = UUID()
        publishWidgetData()
    }
}
