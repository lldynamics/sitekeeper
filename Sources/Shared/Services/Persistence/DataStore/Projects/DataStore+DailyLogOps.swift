import Foundation

@MainActor
extension DataStore {
    func appendDailyLog(_ log: DailyLog) {
        replaceDailyLogs(dailyLogs + [log])
    }

    func insertDailyLogAtTop(_ log: DailyLog) {
        var logs = dailyLogs
        logs.insert(log, at: 0)
        replaceDailyLogs(logs)
    }

    @discardableResult
    func updateDailyLog(_ log: DailyLog) -> Bool {
        var current = dailyLogs
        guard let index = current.firstIndex(where: { $0.id == log.id }) else { return false }
        current[index] = log
        replaceDailyLogs(current)
        return true
    }

    @discardableResult
    func updateDailyLogPhoto(
        logId: UUID,
        photoId: UUID,
        legacyFileName: String,
        note: String,
        tag: PhotoTag
    ) -> Bool {
        var current = dailyLogs
        guard let logIndex = current.firstIndex(where: { $0.id == logId }) else { return false }
        var log = current[logIndex]
        if let photoIndex = log.photos.firstIndex(where: { $0.id == photoId }) {
            log.photos[photoIndex].note = note
            log.photos[photoIndex].tag = tag
        } else if let legacy = log.photoFileName, legacy == legacyFileName {
            log.photos.append(LogPhoto(fileName: legacy, note: note, tag: tag))
        } else {
            return false
        }
        current[logIndex] = log
        replaceDailyLogs(current)
        return true
    }

    @discardableResult
    func removeDailyLogPhoto(
        logId: UUID,
        photoId: UUID,
        legacyFileName: String
    ) -> String? {
        var current = dailyLogs
        guard let logIndex = current.firstIndex(where: { $0.id == logId }) else { return nil }
        var log = current[logIndex]
        var deletedFileName: String?
        if let index = log.photos.firstIndex(where: { $0.id == photoId }) {
            let fileName = log.photos[index].fileName
            deletedFileName = fileName
            log.photos.remove(at: index)
            if log.photoFileName == fileName {
                log.photoFileName = log.photos.first?.fileName
            }
        } else if let legacy = log.photoFileName, legacy == legacyFileName {
            deletedFileName = legacy
            log.photoFileName = nil
        }
        guard let deletedFileName else { return nil }
        current[logIndex] = log
        replaceDailyLogs(current)
        return deletedFileName
    }

    func mergeDailyLogsByID(_ logs: [DailyLog]) {
        replaceDailyLogs(mergedProjectActivityElementsByID(dailyLogs, with: logs))
    }

    func restoreDailyLogs(from deletion: DataStoreRemovalResult<DailyLog>) {
        replaceDailyLogs(deletion.restoredItems(current: dailyLogs, id: \.id))
    }

    @discardableResult
    func removeDailyLogs(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<DailyLog> {
        removeProjectActivityElements(
            from: dailyLogs,
            ids: ids,
            id: \.id,
            replace: replaceDailyLogs,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
