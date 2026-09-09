import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    func handleExportCompletion(_ result: Result<URL, Error>) {
        let outcome = ExportCompletionHandler.evaluate(result, source: "DailyLogView.photoWall")
        operationNotice = ExportCompletionHandler.notice(for: outcome) {
            guard exportPayload != nil else { return }
            showExporter = true
        }
    }

    func filteredPhotoWallItems() -> [PhotoWallItem] {
        let allItems = filtered.flatMap { log in
            log.photoAttachments.map { PhotoWallItem(logId: log.id, logDate: log.date, projectId: log.projectId, photo: $0) }
        }
        guard let photoTagFilter else { return allItems }
        return allItems.filter { $0.photo.tag == photoTagFilter }
    }

    func photoSelectionKey(_ item: PhotoWallItem) -> String {
        "\(item.logId.uuidString)-\(item.photo.fileName)"
    }

    func togglePhotoSelection(_ item: PhotoWallItem) {
        let key = photoSelectionKey(item)
        if selectedPhotoKeys.contains(key) {
            selectedPhotoKeys.remove(key)
        } else {
            selectedPhotoKeys.insert(key)
        }
    }

    func applyBatchTagToSelectedPhotos() {
        guard !selectedPhotoKeys.isEmpty else { return }
        var dailyLogs = store.dailyLogs
        for logIndex in dailyLogs.indices {
            for photoIndex in dailyLogs[logIndex].photos.indices {
                let photo = dailyLogs[logIndex].photos[photoIndex]
                let key = "\(dailyLogs[logIndex].id.uuidString)-\(photo.fileName)"
                if selectedPhotoKeys.contains(key) {
                    dailyLogs[logIndex].photos[photoIndex].tag = batchPhotoTag
                }
            }
            if let legacy = dailyLogs[logIndex].photoFileName {
                let key = "\(dailyLogs[logIndex].id.uuidString)-\(legacy)"
                if selectedPhotoKeys.contains(key) {
                    if let idx = dailyLogs[logIndex].photos.firstIndex(where: { $0.fileName == legacy }) {
                        dailyLogs[logIndex].photos[idx].tag = batchPhotoTag
                    } else {
                        dailyLogs[logIndex].photos.append(LogPhoto(fileName: legacy, tag: batchPhotoTag))
                    }
                }
            }
        }
        store.replaceDailyLogs(dailyLogs)
        store.scheduleSave()
        selectedPhotoKeys.removeAll()
    }

    func hasRectificationPair(logId: UUID) -> Bool {
        guard let log = store.dailyLogs.first(where: { $0.id == logId }) else { return false }
        let tags = Set(log.photoAttachments.map(\.tag))
        return tags.contains(.rectificationBefore) && tags.contains(.rectificationAfter)
    }

    func exportPhotoWallPDF(items: [PhotoWallItem]) {
        let projectName: String
        if let filterProjectId, let project = store.projects.first(where: { $0.id == filterProjectId }) {
            projectName = project.name
        } else {
            projectName = String(localized: "全部项目")
        }
        let payloads = items.map { item in
            ReportPhotoItem(
                date: item.logDate,
                projectName: item.projectId.flatMap { pid in store.projects.first(where: { $0.id == pid })?.name } ?? String(localized: "未归属"),
                tag: item.photo.tag.displayName,
                note: item.photo.note,
                fileName: item.photo.fileName
            )
        }
        photoWallExportTask?.cancel()
        photoWallExportTask = Task {
            let data = await ReportBuilder.makePhotoWallPDFAsync(
                title: String(format: String(localized: "%@-现场照片页"), projectName),
                items: payloads
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                exportPayload = ExportPayload(
                    data: data,
                    contentType: .pdf,
                    defaultFilename: String(format: String(localized: "%@_现场照片页.pdf"), projectName)
                )
                showExporter = true
                photoWallExportTask = nil
            }
        }
    }
}
