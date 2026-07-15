import Foundation

extension DataStore {
    func loadAsync() {
        initialLoadTask?.cancel()
        let storeURL = self.storeURL
        let persistenceActor = self.persistenceActor
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let snapshot = try await persistenceActor.loadSnapshot() else {
                    initialLoadTask = nil
                    flushDeferredSaveIfNeededAfterInitialLoad()
                    scheduleDataHealthScan(reason: .startup, delay: .zero)
                    return
                }
                guard !Task.isCancelled else { return }
                applyLoadedSnapshot(snapshot)
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
                scheduleDataHealthScan(reason: .startup, delay: .milliseconds(150))
            } catch let decodeError as DataStorePersistenceActor.LoadDecodeError {
                guard !Task.isCancelled else { return }
                let backupName = "sitekeeper_corrupt_\(Formatters.now().replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_")).json"
                let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
                do {
                    try decodeError.rawData.write(to: backupURL, options: .atomic)
                    BackupArchiveSecurity.applyDataProtection(to: backupURL)
                } catch {
                    Self.recordIssue(
                        "datastore.corrupt_backup_write_failed",
                        details: ["file": backupName],
                        error: error
                    )
                }
                persistenceErrorMessage = String(
                    format: String(localized: "本地数据解析失败，已保留异常文件：%@。可从备份页重新导入最近备份。"),
                    backupName
                )
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
            } catch {
                guard !Task.isCancelled else { return }
                persistenceErrorMessage = String(
                    format: String(localized: "读取本地数据失败：%@"),
                    error.localizedDescription
                )
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
            }
        }
    }

    func awaitInitialLoad() async {
        await initialLoadTask?.value
    }

    func flushDeferredSaveIfNeededAfterInitialLoad() {
        guard needsSaveAfterInitialLoad else { return }
        needsSaveAfterInitialLoad = false
        save(includePhotoFiles: false)
    }
}
