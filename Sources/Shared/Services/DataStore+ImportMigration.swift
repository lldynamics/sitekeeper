import Foundation

extension DataStore {
    func applyLoadedSnapshot(_ snapshot: BackupSnapshot) {
        replaceMaterialItems(snapshot.materialItems)
        replaceQuoteItems(snapshot.quoteItems)
        replaceLaborRecords(snapshot.laborRecords)
        replaceProjects(snapshot.projects)
        replaceDailyLogs(snapshot.dailyLogs)
        replaceHistoryRecords(snapshot.historyRecords)
        replaceProgressTasks(snapshot.progressTasks)
        replaceSiteTodos(snapshot.siteTodos)
        replaceProjectDrawings(snapshot.projectDrawings)
        replaceProjectContacts(snapshot.projectContacts)
        replaceProjectFinancialRecords(snapshot.projectFinancialRecords)
        replaceProjectDocuments(snapshot.projectDocuments)
        replaceQuickNotes(snapshot.quickNotes)
        replaceProjectWarehouseMovements(snapshot.projectWarehouseMovements)
        replaceTemplates(snapshot.templates)
        replaceMaterialPriceEntries(snapshot.materialPriceEntries)
        replaceMaterialSheetDrafts(snapshot.materialSheetDrafts)
        replaceSupplierProfiles(snapshot.supplierProfiles)
        replaceConstructionMethods(snapshot.constructionMethods)
        favoriteMaterialKeys = snapshot.favoriteMaterialKeys
        recentMaterialKeys = snapshot.recentMaterialKeys
        replaceUserMaterials(snapshot.userMaterials)
        replaceDeletedUserMaterials(snapshot.deletedUserMaterials)
        hiddenPresetKeys = snapshot.hiddenPresetKeys
        refreshSearchIndexVersion()
        dataVersion = UUID()
        publishWidgetData()
    }

    func importSampleData(replacingExisting: Bool) {
#if DEBUG
        guard AppFeatureFlags.allowsSampleDataImport else {
            persistenceErrorMessage = String(localized: "当前发布环境已关闭示例数据导入。")
            return
        }
        if replacingExisting {
            clearAllBusinessData(deleteStoredFiles: true)
        }
        seedDefaults()
        save(includePhotoFiles: false)
#else
        persistenceErrorMessage = String(localized: "当前发布环境已关闭示例数据导入。")
#endif
    }
}
