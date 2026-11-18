import Foundation

extension DataStore {
    func loadAsync() {
        initialLoadTask?.cancel()
        cancelScheduledSave()
        persistTask?.cancel()
        setLoadState(.loading)
        let persistenceActor = self.persistenceActor
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await persistenceActor.loadSnapshot()
                guard !Task.isCancelled else { return }
                if let snapshot { applyLoadedSnapshot(snapshot) }
                setLoadState(.ready)
                lastPersistedMutationRevision = mutationRevision
                persistenceErrorMessage = nil
                initialLoadTask = nil
                publishWidgetData()
                flushDeferredSaveIfNeededAfterInitialLoad()
                scheduleDataHealthScan(reason: .startup, delay: .milliseconds(150))
            } catch {
                guard !Task.isCancelled else { return }
                setLoadState(.failed)
                initialLoadTask = nil
                needsSaveAfterInitialLoad = false
                cancelScheduledSave()
                if let recoveryError = error as? BackupArchiveRestoreJournal.RecoveryPendingError {
                    persistenceErrorMessage = recoveryError.localizedDescription
                } else if let decodeError = error as? DataStorePersistenceActor.LoadDecodeError {
                    preserveUnreadableData(decodeError.rawData, underlyingError: decodeError.underlyingError)
                } else {
                    persistenceErrorMessage = String(
                        format: AppLocalization.string("读取本地数据失败，已暂停保存，原文件未改动：%@。请重试读取或从备份恢复。"),
                        storeURL.path + " · " + error.localizedDescription
                    )
                }
            }
        }
    }

    func preserveUnreadableData(
        _ data: Data,
        underlyingError: (any Error)? = nil,
        writeBackup: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        let backupName = "sitekeeper_corrupt_\(UUID().uuidString).json"
        let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
        if let underlyingError {
            var details = ["file": storeURL.lastPathComponent]
            if let identifierError = underlyingError as? BackupSnapshotIdentifierError {
                details["collection"] = identifierError.collection
            }
            Self.recordIssue("datastore.load_decode_failed", details: details, error: underlyingError)
        }
        let reasonSuffix = (underlyingError as? BackupSnapshotIdentifierError)?.errorDescription.map { " " + $0 } ?? ""
        do {
            try writeBackup(data, backupURL)
            BackupArchiveSecurity.applyDataProtection(to: backupURL)
            persistenceErrorMessage = String(
                format: AppLocalization.string("本地数据解析失败，已暂停保存并保留异常文件：%@。请重试读取或从备份恢复。"),
                backupURL.path
            ) + reasonSuffix
        } catch {
            Self.recordIssue("datastore.corrupt_backup_write_failed", details: ["file": backupName], error: error)
            persistenceErrorMessage = String(
                format: AppLocalization.string("本地数据解析失败，异常副本未能写入，已暂停保存，原文件未改动：%@。请从备份恢复。"),
                storeURL.path + " · " + error.localizedDescription
            ) + reasonSuffix
        }
    }

    func awaitInitialLoad() async {
        await initialLoadTask?.value
    }

    func flushDeferredSaveIfNeededAfterInitialLoad() {
        guard loadState == .ready, needsSaveAfterInitialLoad else { return }
        needsSaveAfterInitialLoad = false
        save(includePhotoFiles: false)
    }
}
