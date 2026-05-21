import Foundation

extension DataStore {
    private var allowsSampleDataImportInCurrentProcess: Bool {
        AppFeatureFlags.allowsSampleDataImport || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

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

    @discardableResult
    func importSampleData(replacingExisting: Bool) -> Bool {
        persistenceErrorMessage = nil
        guard allowsSampleDataImportInCurrentProcess else {
            persistenceErrorMessage = String(localized: "当前发布环境已关闭示例数据导入。")
            return false
        }
        guard let snapshot = loadSampleFixtureSnapshot() else {
            persistenceErrorMessage = String(localized: "无法加载测试数据，请检查 SampleDataFixture.json。")
            return false
        }
        if replacingExisting {
            clearAllBusinessData(deleteStoredFiles: true)
        }
        applySampleFixtureSnapshot(snapshot)
        save(includePhotoFiles: false)
        return true
    }
}
