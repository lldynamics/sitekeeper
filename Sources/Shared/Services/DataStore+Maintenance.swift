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
        guard !Task.isCancelled else { return }
        if deleteStoredFiles {
            let photoNames = PhotoStorage.allStoredFileNames()
            let drawingNames = DrawingStorage.allStoredFileNames()
            let documentNames = ProjectDocumentStorage.allStoredFileNames()
            let attachmentNames = QuickNoteAttachmentStorage.allStoredFileNames()

            onProgress?(String(localized: "正在并行删除照片/图纸/资料/附件"))
            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    DataStoreDeferredFileCleanup.photoFiles(
                        photoNames,
                        summary: "dataStore.clearAllAsync.photos"
                    )?.perform()
                }
                group.addTask(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    DataStoreDeferredFileCleanup.drawingFiles(
                        drawingNames,
                        summary: "dataStore.clearAllAsync.drawings"
                    )?.perform()
                }
                group.addTask(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    DataStoreDeferredFileCleanup.projectDocumentFiles(
                        documentNames,
                        summary: "dataStore.clearAllAsync.projectDocuments"
                    )?.perform()
                }
                group.addTask(priority: .userInitiated) {
                    guard !Task.isCancelled else { return }
                    DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                        attachmentNames,
                        summary: "dataStore.clearAllAsync.quickNoteAttachments"
                    )?.perform()
                }
                await group.waitForAll()
            }

            onProgress?(String(localized: "正在清理日志"))
            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: .utility) {
                    guard !Task.isCancelled else { return }
                    StorageIssueLog.clear()
                }
                await group.waitForAll()
            }
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
