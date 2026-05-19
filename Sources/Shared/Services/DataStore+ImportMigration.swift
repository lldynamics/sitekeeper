import Foundation

extension DataStore {
    func applyLoadedSnapshot(_ snapshot: BackupSnapshot) {
        let migratedLegacyRecords = Self.migrateLegacyPaymentRecords(
            snapshot.legacyPaymentRecords,
            projects: snapshot.projects
        )
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
        replaceProjectFinancialRecords(Self.mergeFinancialRecords(
            existing: snapshot.projectFinancialRecords,
            incoming: migratedLegacyRecords
        ))
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
        if !snapshot.legacyPaymentRecords.isEmpty {
            Self.recordIssue(
                "datastore.legacy_payment_records_migrated",
                details: [
                    "recordCount": String(snapshot.legacyPaymentRecords.count),
                    "target": "project_financial_records"
                ]
            )
            needsSaveAfterInitialLoad = true
        }
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

    private static func migrateLegacyPaymentRecords(
        _ legacyRecords: [LegacyPaymentRecord],
        projects: [Project]
    ) -> [ProjectFinancialRecord] {
        guard !legacyRecords.isEmpty else { return [] }
        let counterpartyByProjectID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.customerName) }
        )
        return legacyRecords.map { legacy in
            legacy.migratedFinancialRecord(
                counterparty: counterpartyByProjectID[legacy.projectId] ?? ""
            )
        }
    }

    private static func mergeFinancialRecords(
        existing: [ProjectFinancialRecord],
        incoming: [ProjectFinancialRecord]
    ) -> [ProjectFinancialRecord] {
        guard !incoming.isEmpty else { return existing }
        var merged = existing
        var knownIDs = Set(existing.map(\.id))
        for record in incoming where knownIDs.insert(record.id).inserted {
            merged.append(record)
        }
        return merged
    }
}
