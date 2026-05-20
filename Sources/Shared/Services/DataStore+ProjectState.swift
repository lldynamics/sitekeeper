import Foundation

@MainActor
extension DataStore {
    private(set) var projects: [Project] {
        get {
            access(keyPath: \.projects)
            return projectStore.projects
        }
        set {
            withMutation(keyPath: \.projects) {
                projectStore.setProjects(newValue)
            }
        }
    }

    private(set) var dailyLogs: [DailyLog] {
        get {
            access(keyPath: \.dailyLogs)
            return projectStore.dailyLogs
        }
        set {
            withMutation(keyPath: \.dailyLogs) {
                projectStore.setDailyLogs(newValue)
            }
        }
    }

    private(set) var historyRecords: [HistoryRecord] {
        get {
            access(keyPath: \.historyRecords)
            return projectStore.historyRecords
        }
        set {
            withMutation(keyPath: \.historyRecords) {
                projectStore.setHistoryRecords(applyingHistoryRetention(to: newValue))
            }
        }
    }

    private(set) var progressTasks: [ProgressTask] {
        get {
            access(keyPath: \.progressTasks)
            return projectStore.progressTasks
        }
        set {
            withMutation(keyPath: \.progressTasks) {
                projectStore.setProgressTasks(newValue)
            }
        }
    }

    private(set) var siteTodos: [SiteTodo] {
        get {
            access(keyPath: \.siteTodos)
            return projectStore.siteTodos
        }
        set {
            withMutation(keyPath: \.siteTodos) {
                projectStore.setSiteTodos(newValue)
            }
        }
    }

    private(set) var projectDrawings: [ProjectDrawing] {
        get {
            access(keyPath: \.projectDrawings)
            return projectStore.projectDrawings
        }
        set {
            withMutation(keyPath: \.projectDrawings) {
                projectStore.setProjectDrawings(newValue)
            }
        }
    }

    private(set) var projectContacts: [ProjectContact] {
        get {
            access(keyPath: \.projectContacts)
            return projectStore.projectContacts
        }
        set {
            withMutation(keyPath: \.projectContacts) {
                projectStore.setProjectContacts(newValue)
            }
        }
    }

    private(set) var projectFinancialRecords: [ProjectFinancialRecord] {
        get {
            access(keyPath: \.projectFinancialRecords)
            return projectStore.projectFinancialRecords
        }
        set {
            withMutation(keyPath: \.projectFinancialRecords) {
                projectStore.setProjectFinancialRecords(newValue)
            }
        }
    }

    private(set) var projectDocuments: [ProjectDocument] {
        get {
            access(keyPath: \.projectDocuments)
            return projectStore.projectDocuments
        }
        set {
            withMutation(keyPath: \.projectDocuments) {
                projectStore.setProjectDocuments(newValue)
            }
        }
    }

    private(set) var quickNotes: [QuickNote] {
        get {
            access(keyPath: \.quickNotes)
            return projectStore.quickNotes
        }
        set {
            withMutation(keyPath: \.quickNotes) {
                projectStore.setQuickNotes(newValue)
            }
        }
    }

    private(set) var projectWarehouseMovements: [ProjectWarehouseMovement] {
        get {
            access(keyPath: \.projectWarehouseMovements)
            return projectStore.projectWarehouseMovements
        }
        set {
            withMutation(keyPath: \.projectWarehouseMovements) {
                projectStore.setProjectWarehouseMovements(newValue)
            }
        }
    }
}
