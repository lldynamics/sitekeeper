import SwiftUI
import Foundation

extension ConstructionMethodPackImportSheet {
    func load(allowOfflineFallback: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await ConstructionMethodPackImportService.fetch()
            payload = result.payload
            payloadSource = .website
            loadedEndpoint = result.endpoint
            selectedPackIDs = Set(result.payload.packs.map(\.id))
            cachedSnapshot = ConstructionMethodPackOfflineCacheStore.save(endpoint: result.endpoint, payload: result.payload)
        } catch {
            let failedMessage = String(format: String(localized: "无法连接到工程知识网站：%@"), error.localizedDescription)
            let failedStatus = ConstructionMethodPackImportStatus(
                outcome: .failed,
                endpoint: ConstructionMethodPackImportService.configuredPrimaryEndpoint.absoluteString,
                generatedAt: nil,
                message: error.localizedDescription,
                importedCount: 0,
                newCount: 0,
                updateCount: 0,
                timestamp: Date().timeIntervalSince1970
            )
            lastImportStatus = failedStatus
            ConstructionMethodPackImportStatusStore.save(failedStatus)

            if allowOfflineFallback,
               let snapshot = cachedSnapshot ?? ConstructionMethodPackOfflineCacheStore.load() {
                cachedSnapshot = snapshot
                applyOfflineCache(snapshot, fallbackMessage: failedMessage)
            } else {
                payload = nil
                payloadSource = .website
                loadedEndpoint = nil
                selectedPackIDs.removeAll()
                errorMessage = failedMessage
            }
        }
        isLoading = false
    }

    func applyOfflineCache(manual: Bool) {
        guard let snapshot = cachedSnapshot else { return }
        applyOfflineCache(snapshot, fallbackMessage: nil)
        if manual {
            operationNotice = .info(String(localized: "已切换到离线缓存"))
        }
    }

    func applyOfflineCache(_ snapshot: ConstructionMethodPackOfflineCacheSnapshot, fallbackMessage: String?) {
        payload = snapshot.payload
        payloadSource = .offlineCache
        loadedEndpoint = URL(string: snapshot.endpoint)
        selectedPackIDs = Set(snapshot.payload.packs.map(\.id))
        if let fallbackMessage {
            errorMessage = String(format: String(localized: "%@（已启用离线缓存）"), fallbackMessage)
        } else {
            errorMessage = nil
        }
    }

    func clearOfflineCache() {
        ConstructionMethodPackOfflineCacheStore.clear()
        cachedSnapshot = nil
        if payloadSource == .offlineCache {
            payload = nil
            loadedEndpoint = nil
            selectedPackIDs.removeAll()
            payloadSource = .website
        }
        operationNotice = .info(String(localized: "已清除离线缓存"))
    }

    func selectedBinding(for id: String) -> Binding<Bool> {
        Binding {
            selectedPackIDs.contains(id)
        } set: { isSelected in
            if isSelected {
                selectedPackIDs.insert(id)
            } else {
                selectedPackIDs.remove(id)
            }
        }
    }

    func existingMethod(for pack: RemoteConstructionMethodPack) -> ConstructionMethod? {
        existingMethods.first { method in
            method.sourceID == pack.id
                || (method.sourceID.isEmpty && method.title == pack.title && method.trade == pack.trade)
        }
    }

    func importStateText(_ preview: ImportDiffPreview) -> String {
        switch preview.kind {
        case .new:
            return String(localized: "新增")
        case .updated:
            return String(format: String(localized: "更新（%lld项）"), Int64(preview.changes.count))
        case .unchanged:
            return String(localized: "无变化")
        }
    }

    func importStateColor(_ preview: ImportDiffPreview) -> Color {
        switch preview.kind {
        case .new:
            return .appSuccess
        case .updated:
            return .appWarning
        case .unchanged:
            return .secondary
        }
    }

    func importSelected() {
        guard let payload else { return }
        let selectedPacks = payload.packs.filter { selectedPackIDs.contains($0.id) }
        let selectedPreviews = selectedPacks.map(importDiff(for:))
        let newCount = selectedPreviews.filter { $0.kind == .new }.count
        let updateCount = selectedPreviews.filter { $0.kind == .updated }.count
        let skippedCount = selectedPreviews.filter { $0.kind == .unchanged }.count
        let methods = selectedPreviews.compactMap { preview -> ConstructionMethod? in
            guard preview.kind != .unchanged else { return nil }
            return preview.pack.constructionMethod(existing: existingMethod(for: preview.pack))
        }

        guard !methods.isEmpty else {
            operationNotice = .info(String(localized: "所选工艺与当前版本一致，无需导入"))
            return
        }

        let successStatus = ConstructionMethodPackImportStatus(
            outcome: .success,
            endpoint: (loadedEndpoint ?? ConstructionMethodPackImportService.configuredPrimaryEndpoint).absoluteString,
            generatedAt: payload.generatedAt,
            message: String(
                format: String(localized: "导入 %lld 条，新增 %lld 条，更新 %lld 条，跳过 %lld 条"),
                Int64(methods.count),
                Int64(newCount),
                Int64(updateCount),
                Int64(skippedCount)
            ),
            importedCount: methods.count,
            newCount: newCount,
            updateCount: updateCount,
            timestamp: Date().timeIntervalSince1970
        )
        lastImportStatus = successStatus
        ConstructionMethodPackImportStatusStore.save(successStatus)
        onImport(methods, newCount, updateCount)
        dismiss()
    }
}
