import SwiftUI
import UIKit

extension DailyLogView {
    func save() {
        guard canSaveLog else { return }
        let logId = UUID()
        let fileNames: [String]
        do {
            fileNames = try PhotoStorage.saveManyOrThrow(originals: composer.photoDrafts.map(\.data), logId: logId)
        } catch {
            alertMessage = String(format: String(localized: "现场照片保存失败：%@"), error.localizedDescription)
            showAlert = true
            return
        }
        let photos = zip(fileNames, composer.photoDrafts).map { fileName, draft in
            LogPhoto(fileName: fileName, note: draft.note, tag: draft.tag)
        }
        store.insertDailyLogAtTop(DailyLog(
            id: logId,
            date: Formatters.date.string(from: composer.date),
            weather: composer.weather,
            content: composer.content,
            workers: composer.workers,
            photoFileName: fileNames.first,
            photos: photos,
            safety: composer.safety,
            materials: composer.materials,
            tomorrowPlan: composer.tomorrowPlan,
            qualityIssue: composer.qualityIssue,
            rectification: composer.rectification,
            confirmer: composer.confirmer,
            linkedConstructionMethodIDs: sortedLinkedMethodIDs(composer.linkedMethodIDs),
            projectId: composer.projectId
        ))
        store.scheduleSave()
        clearDraft()
    }

    func clearDraft() {
        composer.selectedPhotos = []
        composer.photoDrafts = []
        composer.showLogCamera = false
        composer.cameraPhotoTag = .general
        composer.projectId = initialProjectId
        composer.content = ""
        composer.workers = ""
        composer.safety = ""
        composer.materials = ""
        composer.tomorrowPlan = ""
        composer.qualityIssue = ""
        composer.rectification = ""
        composer.confirmer = ""
        composer.linkedMethodIDs.removeAll()
        composer.weather = autoWeatherNow()
    }

    func startEdit(_ log: DailyLog) {
        editor.logId = log.id
        editor.date = Formatters.date.date(from: log.date) ?? Date()
        editor.weather = log.weather
        editor.content = log.content
        editor.workers = log.workers
        editor.safety = log.safety
        editor.materials = log.materials
        editor.tomorrowPlan = log.tomorrowPlan
        editor.qualityIssue = log.qualityIssue
        editor.rectification = log.rectification
        editor.confirmer = log.confirmer
        editor.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        editor.projectId = log.projectId
        showEdit = true
    }

    func openFocusedLogIfNeeded() {
        guard let focusedLogId, !didOpenFocusedLog,
              let log = store.dailyLogs.first(where: { $0.id == focusedLogId }) else { return }
        didOpenFocusedLog = true
        viewMode = .list
        filterProjectId = log.projectId
        searchText = ""
        Task { @MainActor in
            startEdit(log)
        }
    }

    func saveEditedLog() {
        guard let id = editor.logId,
              let index = store.dailyLogs.firstIndex(where: { $0.id == id }) else { return }
        var log = store.dailyLogs[index]
        log.date = Formatters.date.string(from: editor.date)
        log.weather = editor.weather
        log.content = editor.content
        log.workers = editor.workers
        log.safety = editor.safety
        log.materials = editor.materials
        log.tomorrowPlan = editor.tomorrowPlan
        log.qualityIssue = editor.qualityIssue
        log.rectification = editor.rectification
        log.confirmer = editor.confirmer
        log.linkedConstructionMethodIDs = sortedLinkedMethodIDs(editor.linkedMethodIDs)
        log.projectId = editor.projectId
        store.updateDailyLog(log)
        store.scheduleSave()
    }

    func copyLogToToday(_ log: DailyLog) {
        composer.date = Date()
        composer.weather = log.weather
        composer.content = log.content
        composer.workers = log.workers
        composer.safety = log.safety
        composer.materials = log.materials
        composer.tomorrowPlan = log.tomorrowPlan
        composer.qualityIssue = log.qualityIssue
        composer.rectification = log.rectification
        composer.confirmer = log.confirmer
        composer.linkedMethodIDs = Set(log.linkedConstructionMethodIDs)
        composer.projectId = log.projectId
        composer.selectedPhotos = []
        composer.photoDrafts = []
        showAdd = true
    }

    func applyDailyLogTemplate(_ template: ProjectTemplate) {
        composer.content = template.content
    }
}
