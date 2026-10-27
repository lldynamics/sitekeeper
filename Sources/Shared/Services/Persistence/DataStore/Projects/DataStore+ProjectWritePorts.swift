import Foundation

@MainActor
extension DataStore {
    func replaceProjectDrawings(_ drawings: [ProjectDrawing]) {
        projectStore.setProjectDrawings(drawings)
    }

    func replaceProgressTasks(_ tasks: [ProgressTask]) {
        projectStore.setProgressTasks(tasks)
    }

    func replaceProjects(_ values: [Project]) {
        projectStore.setProjects(values)
    }

    func replaceDailyLogs(_ logs: [DailyLog]) {
        projectStore.setDailyLogs(logs)
    }

    func replaceSiteTodos(_ todos: [SiteTodo]) {
        projectStore.setSiteTodos(todos)
    }

    func replaceProjectContacts(_ contacts: [ProjectContact]) {
        projectStore.setProjectContacts(contacts)
    }

    func replaceProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        projectStore.setProjectFinancialRecords(records)
    }

    func replaceProjectDocuments(_ documents: [ProjectDocument]) {
        projectStore.setProjectDocuments(documents)
    }

    func replaceQuickNotes(_ notes: [QuickNote]) {
        projectStore.setQuickNotes(notes)
    }

    func replaceProjectWarehouseMovements(_ movements: [ProjectWarehouseMovement]) {
        projectStore.setProjectWarehouseMovements(movements)
    }

    func replaceHistoryRecords(_ records: [HistoryRecord]) {
        projectStore.setHistoryRecords(applyingHistoryRetention(to: records))
    }
}
