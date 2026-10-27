import Foundation

@MainActor
extension DataStore {
    private(set) var projects: [Project] {
        get {
            return projectStore.projects
        }
        set {
            projectStore.setProjects(newValue)
        }
    }

    private(set) var dailyLogs: [DailyLog] {
        get {
            return projectStore.dailyLogs
        }
        set {
            projectStore.setDailyLogs(newValue)
        }
    }

    private(set) var historyRecords: [HistoryRecord] {
        get {
            return projectStore.historyRecords
        }
        set {
            projectStore.setHistoryRecords(applyingHistoryRetention(to: newValue))
        }
    }

    private(set) var progressTasks: [ProgressTask] {
        get {
            return projectStore.progressTasks
        }
        set {
            projectStore.setProgressTasks(newValue)
        }
    }

    private(set) var siteTodos: [SiteTodo] {
        get {
            return projectStore.siteTodos
        }
        set {
            projectStore.setSiteTodos(newValue)
        }
    }

    private(set) var projectDrawings: [ProjectDrawing] {
        get {
            return projectStore.projectDrawings
        }
        set {
            projectStore.setProjectDrawings(newValue)
        }
    }

    private(set) var projectContacts: [ProjectContact] {
        get {
            return projectStore.projectContacts
        }
        set {
            projectStore.setProjectContacts(newValue)
        }
    }

    private(set) var projectFinancialRecords: [ProjectFinancialRecord] {
        get {
            return projectStore.projectFinancialRecords
        }
        set {
            projectStore.setProjectFinancialRecords(newValue)
        }
    }

    private(set) var projectDocuments: [ProjectDocument] {
        get {
            return projectStore.projectDocuments
        }
        set {
            projectStore.setProjectDocuments(newValue)
        }
    }

    private(set) var quickNotes: [QuickNote] {
        get {
            return projectStore.quickNotes
        }
        set {
            projectStore.setQuickNotes(newValue)
        }
    }

    private(set) var projectWarehouseMovements: [ProjectWarehouseMovement] {
        get {
            return projectStore.projectWarehouseMovements
        }
        set {
            projectStore.setProjectWarehouseMovements(newValue)
        }
    }
}
