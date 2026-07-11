import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension DataStore {
    func publishWidgetData() {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return }
        let activeProjects = projects.filter {
            $0.status == .active || $0.status == .paused
        }
        let activeProjectIDs = Set(activeProjects.map(\.id))
        let stockLines = activeProjects.flatMap {
            WarehouseStockCalculator.stockLines(for: $0.id, movements: projectWarehouseMovements)
        }
        let activeFinancialRecords = projectFinancialRecords.filter {
            activeProjectIDs.contains($0.projectId) && $0.normalizedStatus == .active
        }
        let missingReceiptCount = activeFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
        let priceSpikeCount = activeProjects.reduce(0) { count, project in
            count + financeStore.materialPriceSpikeCount(for: project.id)
        }
        let preferenceStore = UserPreferencesStore.shared
        let reminderDays = preferenceStore.backupReminderDays
        let latestBackupDate = preferenceStore.latestSuccessfulBackupDate
        let backupOverdueCount: Int = {
            guard let latestBackupDate else { return 1 }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: latestBackupDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
            return days >= reminderDays ? 1 : 0
        }()
        let widgetData = WidgetDataBuilder.build(
            projects: activeProjects.map {
                WidgetBuilderProjectInput(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status.rawValue,
                    isActive: true
                )
            },
            todos: siteTodos.map { WidgetBuilderTodoInput(projectId: $0.projectId, isDone: $0.isDone, dueDate: $0.dueDate) },
            tasks: progressTasks.map { WidgetBuilderTaskInput(projectId: $0.projectId, completion: $0.completion) },
            stockLines: stockLines.map { WidgetBuilderStockInput(quantity: $0.quantity) },
            missingReceiptCount: missingReceiptCount,
            priceSpikeCount: priceSpikeCount,
            backupOverdueCount: backupOverdueCount,
            backupLastSuccessAt: latestBackupDate?.timeIntervalSince1970 ?? 0,
            backupReminderDays: reminderDays
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(widgetData)
        } catch {
            Self.recordIssue(
                "datastore.widget_payload_encode_failed",
                details: ["target": WidgetSharedDefaults.dataKey],
                error: error
            )
            return
        }
        defaults.set(data, forKey: WidgetSharedDefaults.dataKey)
        defaults.set(widgetData.lastUpdatedAt, forKey: WidgetSharedDefaults.updatedAtKey)
        reloadWidgetTimelines()
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedDefaults.widgetKind)
#endif
    }
}
