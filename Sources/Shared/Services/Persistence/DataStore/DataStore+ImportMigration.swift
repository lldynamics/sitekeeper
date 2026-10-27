import Foundation

extension DataStore {
    private var allowsSampleDataImportInCurrentProcess: Bool {
#if DEBUG
        AppFeatureFlags.allowsSampleDataImport || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#else
        false
#endif
    }

    func applyLoadedSnapshot(_ snapshot: BackupSnapshot) {
        let wasApplyingSnapshot = isApplyingSnapshot
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = wasApplyingSnapshot }
        legacyDateProvenance = snapshot.legacyDateProvenance
        projectStore.withBatchUpdates {
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
        }
        refreshSearchIndexVersion()
        dataVersion = UUID()
        publishWidgetData()
    }

    @discardableResult
    func importSampleData(replacingExisting: Bool) -> Bool {
        persistenceErrorMessage = nil
        guard allowsSampleDataImportInCurrentProcess else {
            persistenceErrorMessage = AppLocalization.string("当前发布环境已关闭示例数据导入。")
            return false
        }
#if DEBUG
        guard let snapshot = loadSampleFixtureSnapshot() else {
            persistenceErrorMessage = AppLocalization.string("无法加载测试数据，请检查 SampleDataFixture.json。")
            return false
        }
        if replacingExisting {
            guard clearAllBusinessData(deleteStoredFiles: true) else { return false }
        }
        applySampleFixtureSnapshot(snapshot)
        save(includePhotoFiles: false)
        return true
#else
        return false
#endif
    }
}
