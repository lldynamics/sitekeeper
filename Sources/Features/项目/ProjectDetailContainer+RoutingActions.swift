import SwiftUI

extension ProjectDetailContainer {
    func openRecordsModeFromMetric() {
        openMode(.records, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    func openFinanceModeFromQuoteMetric() {
        openFinanceModeFromMetric(filter: .none)
    }

    func openTodoFilterFromMetric() {
        showTodoFilterView = true
    }

    func openFinanceModeFromMetric(filter: ProjectFinanceJumpFilter) {
        routeState.financeJumpFilter = filter
        openMode(.finance, prefersInlineSections: usesSingleCanvasLayoutOnPad)
    }

    func resetFinanceJumpFilter() {
        routeState.financeJumpFilter = .none
    }

    func openMode(_ mode: ProjectDetailMode, prefersInlineSections: Bool) {
        if prefersInlineSections {
            routeState.mode = mode
            requestAnchorScroll(anchor(for: mode))
            return
        }
        routeState.mode = mode
    }

    func requestAnchorScroll(_ anchor: ProjectDetailAnchor) {
        routeState.anchorRequest = ProjectDetailAnchorRequest(anchor: anchor)
    }

    func focusModeInSingleCanvas(_ mode: ProjectDetailMode) {
        guard mode != .overview else { return }
        requestAnchorScroll(anchor(for: mode))
    }

    func anchor(for mode: ProjectDetailMode) -> ProjectDetailAnchor {
        switch mode {
        case .overview:
            .overview
        case .records:
            .records
        case .assets:
            .assets
        case .finance:
            .finance
        case .timeline:
            .timeline
        }
    }

    func usesInlineDetailLayout(for availableWidth: CGFloat) -> Bool {
        _ = availableWidth
        return usesSingleCanvasLayoutOnPad
    }

    func paidAmount(_ project: Project, snapshot: ProjectDetailSnapshot) -> Double {
        ProjectDetailMetrics.paidAmount(
            project: project,
            relatedFinancialRecords: snapshot.relatedFinancialRecords
        )
    }

    func requestExportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        switch ProjectDetailExportWorkflow.packageRequestDecision(
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        ) {
        case .proceed:
            exportProjectPackage(project, snapshot: snapshot)
        case .warn(let warningMessage):
            exportState.pendingPackageProject = project
            exportState.packageSizeWarningMessage = warningMessage
            exportState.showPackageSizeWarning = true
        case .reject(let errorMessage):
            presentImportError(errorMessage)
        }
    }

    func deliveryGuideData(snapshot: ProjectDetailSnapshot) -> ProjectDeliveryGuideData {
        ProjectDeliveryGuideData(
            projectName: snapshot.project.name,
            logCount: snapshot.relatedLogs.count,
            drawingCount: snapshot.relatedDrawings.count,
            drawingWithoutCurrentCount: drawingWithoutCurrentCount(snapshot.relatedDrawings),
            documentCount: snapshot.relatedDocuments.count,
            contactCount: snapshot.relatedContacts.count,
            missingReceiptCount: snapshot.missingReceiptCount,
            unsettledFinancialCount: snapshot.unsettledFinancialCount,
            missingOriginalEntries: ProjectDetailImportExportActions.missingProjectPackageFiles(
                documents: snapshot.relatedDocuments,
                drawings: snapshot.relatedDrawings,
                logs: snapshot.relatedLogs,
                quickNotes: snapshot.relatedQuickNotes
            ),
            estimatedPackageBytes: ProjectDetailImportExportActions.estimatedProjectPackageBytes(
                documents: snapshot.relatedDocuments,
                drawings: snapshot.relatedDrawings,
                logs: snapshot.relatedLogs,
                quickNotes: snapshot.relatedQuickNotes
            )
        )
    }

    func drawingWithoutCurrentCount(_ drawings: [ProjectDrawing]) -> Int {
        guard !drawings.isEmpty else { return 0 }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? drawing.fileName : name
        }
        return grouped.values.filter { group in
            !group.contains(where: \.isCurrentVersion)
        }.count
    }

    func exportProjectPackage(_ project: Project, snapshot: ProjectDetailSnapshot) {
        exportState.projectPackageExportTask?.cancel()
        exportState.isExportingProjectPackage = true
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")

        exportState.projectPackageExportTask = ProjectDetailExportWorkflow.makeProjectPackageExportTask(
            project: project,
            projectId: projectId,
            materials: snapshot.relatedMaterials,
            quotes: snapshot.relatedQuotes,
            labor: snapshot.relatedLabor,
            logs: snapshot.relatedLogs,
            tasks: snapshot.relatedProgress,
            todos: snapshot.relatedTodos,
            drawings: snapshot.relatedDrawings,
            contacts: snapshot.relatedContacts,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            quickNotes: snapshot.relatedQuickNotes,
            paidAmountOverride: paidAmount(project, snapshot: snapshot),
            onProgress: { progress in
                exportState.projectPackageExportProgress = progress
            },
            onCancelled: {
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
            },
            onCompletion: { result in
                exportState.isExportingProjectPackage = false
                exportState.projectPackageExportTask = nil
                switch result {
                case .success(let payload):
                    exportState.exportPayload = payload
                    exportState.showExporter = true
                case .failure(let message):
                    if message != ProjectPackageArchiveError.cancelled.localizedDescription {
                        presentImportError(message)
                    }
                }
            }
        )
    }

    func cancelProjectPackageExport() {
        exportState.projectPackageExportProgress = ProjectPackageExportProgress(
            completedSteps: exportState.projectPackageExportProgress.completedSteps,
            totalSteps: max(exportState.projectPackageExportProgress.totalSteps, 1),
            currentItem: "正在取消..."
        )
        exportState.projectPackageExportTask?.cancel()
    }

    func updateProject(_ updated: Project) {
        guard let idx = projectStore.projects.firstIndex(where: { $0.id == updated.id }) else { return }
        store.projects[idx] = updated
        store.scheduleSave()
    }

    func handleOnAppear(snapshot: ProjectDetailSnapshot) {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            didAutoOpenFinancialAdd: didAutoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            didAutoOpenDocumentScanSetup: didAutoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide,
            didAutoOpenDeliveryGuide: didAutoOpenDeliveryGuide,
            focus: focus,
            didOpenFocusedItem: didOpenFocusedItem,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            contacts: snapshot.relatedContacts
        )
        if routing.shouldOpenFinancialAdd {
            didAutoOpenFinancialAdd = true
            routeState.mode = .finance
            routeState.presentation = .addFinancial
        }
        if routing.shouldOpenDocumentScanSetup {
            didAutoOpenDocumentScanSetup = true
            routeState.mode = .assets
            routeState.presentation = .documentScanSetup
        }
        if routing.shouldOpenDeliveryGuide {
            didAutoOpenDeliveryGuide = true
            routeState.mode = .overview
            routeState.presentation = .deliveryGuide
        }
        if routing.shouldConsumeFocusRequest {
            didOpenFocusedItem = true
            guard let focusedItem = routing.focusedItem else { return }
            routeState.mode = focusedItem.mode
            Task { @MainActor in
                ProjectDetailFocusedItemApplier.apply(
                    focusedItem,
                    setFinancialRecord: { financeState.editingFinancialRecord = $0 },
                    setDocument: { assetState.editingDocument = $0 },
                    setContact: { assetState.editingContact = $0 }
                )
            }
        }
    }
}
