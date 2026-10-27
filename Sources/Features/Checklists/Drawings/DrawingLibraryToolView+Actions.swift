import SwiftUI

extension DrawingLibraryToolView {
    func openDrawing(_ drawing: ProjectDrawing) {
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing, store: store) {
        case .success(let url):
            recordRecentDrawing(drawing.id)
            if drawing.fileType.lowercased() == "pdf" {
                quickLookURL = url
            } else {
                shareDrawingID = drawing.id
                shareURL = url
            }
        case .failure(let message):
            StorageIssueLog.recordEvent(
                "drawing_library.open_source_failed",
                category: .fileStorage,
                details: [
                    "source": "DrawingLibraryToolView.openDrawing",
                    "drawing_id": drawing.id.uuidString,
                    "drawing_name": drawing.name.isEmpty ? drawing.fileName : drawing.name,
                    "error_message": message
                ]
            )
            operationMessage = message
        }
    }

    func beginImportDrawings() {
        guard !store.projects.isEmpty else {
            operationMessage = AppLocalization.string("请先创建项目，再导入图纸。")
            return
        }
        showDrawingImporter = true
    }

    func clearDrawingFilters() {
        searchText = ""
        availabilityFilter = .all
    }

    func handleImportedDrawings(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let projectID = selectedProjectID {
            prepareImportDrawings(urls, projectId: projectID)
            return
        }
        if store.projects.count == 1, let projectID = store.projects.first?.id {
            prepareImportDrawings(urls, projectId: projectID)
            return
        }
        pendingImportURLs = urls
        showImportProjectPicker = true
    }

    func prepareImportDrawings(_ urls: [URL], projectId: UUID) {
        guard !urls.isEmpty else { return }
        pendingImportProjectID = nil
        pendingImportConflictNames.removeAll()
        showImportStrategyDialog = false
        let conflicts = DrawingImportCoordinator.conflictedDrawingNames(for: urls, projectId: projectId, store: store)
        guard !conflicts.isEmpty else {
            pendingImportURLs.removeAll()
            performImportDrawings(urls, projectId: projectId, strategy: .createNewVersion)
            return
        }
        pendingImportURLs = urls
        pendingImportProjectID = projectId
        pendingImportConflictNames = conflicts
        showImportStrategyDialog = true
    }

    func applyImportStrategy(_ strategy: ProjectDrawingImportStrategy) {
        guard let projectId = pendingImportProjectID else { return }
        let urls = pendingImportURLs
        clearImportStrategyState()
        guard !urls.isEmpty else { return }
        performImportDrawings(urls, projectId: projectId, strategy: strategy)
    }

    func clearImportStrategyState() {
        pendingImportURLs.removeAll()
        pendingImportProjectID = nil
        pendingImportConflictNames.removeAll()
        showImportStrategyDialog = false
    }

    func performImportDrawings(_ urls: [URL], projectId: UUID, strategy: ProjectDrawingImportStrategy) {
        let result = DrawingImportCoordinator.importDrawings(
            urls,
            projectId: projectId,
            strategy: strategy,
            store: store,
            replacementCleanupSummary: "drawingLibrary.importReplacement"
        )
        if result.didImport {
            selectedProjectID = projectId
            store.scheduleSave()
        }
        operationMessage = result.operationMessage
    }

    func scanDrawingFileAvailability() {
        let drawings = listModel.scannableDrawings
        guard !drawings.isEmpty else {
            operationMessage = AppLocalization.string("没有可扫描的图纸原件。")
            return
        }

        let now = BusinessDateValue.instant(Date())
        var availableCount = 0
        var missingCount = 0
        var didChange = false

        for drawing in drawings {
            let exists = DrawingStorage.exists(fileName: drawing.fileName)
            let status: ProjectDrawingFileAvailabilityStatus = exists ? .available : .missing
            if exists {
                availableCount += 1
            } else {
                missingCount += 1
            }

            store.mutateProjectDrawing(id: drawing.id) { item in
                if item.fileAvailabilityStatus != status {
                    item.fileAvailabilityStatus = status
                    didChange = true
                }
                if item.fileAvailabilityCheckedAt != now {
                    item.fileAvailabilityCheckedAt = now
                    didChange = true
                }
            }
        }

        if didChange {
            store.scheduleSave()
        }
        if missingCount > 0 {
            availabilityFilter = .missing
        }
        operationMessage = String(
            format: AppLocalization.string("已扫描 %lld 张图纸：可用 %lld，缺失 %lld"),
            Int64(drawings.count),
            Int64(availableCount),
            Int64(missingCount)
        )
    }

    func recordRecentDrawing(_ drawingID: UUID) {
        recentDrawingIDsRaw = DrawingListViewModel.rawRecentDrawingIDs(recording: drawingID, in: recentDrawingIDsRaw)
    }
}
