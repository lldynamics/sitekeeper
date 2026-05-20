import Foundation

@MainActor
extension DataStore {
    func replaceProjectDrawings(_ drawings: [ProjectDrawing]) {
        withMutation(keyPath: \.projectDrawings) {
            projectStore.setProjectDrawings(drawings)
        }
    }

    func replaceProgressTasks(_ tasks: [ProgressTask]) {
        withMutation(keyPath: \.progressTasks) {
            projectStore.setProgressTasks(tasks)
        }
    }

    func replaceProjects(_ values: [Project]) {
        withMutation(keyPath: \.projects) {
            projectStore.setProjects(values)
        }
    }

    func replaceDailyLogs(_ logs: [DailyLog]) {
        withMutation(keyPath: \.dailyLogs) {
            projectStore.setDailyLogs(logs)
        }
    }

    func replaceSiteTodos(_ todos: [SiteTodo]) {
        withMutation(keyPath: \.siteTodos) {
            projectStore.setSiteTodos(todos)
        }
    }

    func replaceProjectContacts(_ contacts: [ProjectContact]) {
        withMutation(keyPath: \.projectContacts) {
            projectStore.setProjectContacts(contacts)
        }
    }

    func replaceProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        withMutation(keyPath: \.projectFinancialRecords) {
            projectStore.setProjectFinancialRecords(records)
        }
    }

    func replaceProjectDocuments(_ documents: [ProjectDocument]) {
        withMutation(keyPath: \.projectDocuments) {
            projectStore.setProjectDocuments(documents)
        }
    }

    func replaceQuickNotes(_ notes: [QuickNote]) {
        withMutation(keyPath: \.quickNotes) {
            projectStore.setQuickNotes(notes)
        }
    }

    func replaceProjectWarehouseMovements(_ movements: [ProjectWarehouseMovement]) {
        withMutation(keyPath: \.projectWarehouseMovements) {
            projectStore.setProjectWarehouseMovements(movements)
        }
    }

    func replaceHistoryRecords(_ records: [HistoryRecord]) {
        withMutation(keyPath: \.historyRecords) {
            projectStore.setHistoryRecords(applyingHistoryRetention(to: records))
        }
    }
}
