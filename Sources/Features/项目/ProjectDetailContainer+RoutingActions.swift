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
        let logExpectation = deliveryLogExpectation(project: snapshot.project, logs: snapshot.relatedLogs)
        return ProjectDeliveryGuideData(
            projectName: snapshot.project.name,
            logCount: snapshot.relatedLogs.count,
            expectedLogDateCount: logExpectation.expectedCount,
            missingLogDateCount: logExpectation.missingCount,
            missingLogDateSamples: logExpectation.samples,
            drawingCount: snapshot.relatedDrawings.count,
            drawingGroupsWithoutCurrent: drawingGroupsWithoutCurrentVersion(snapshot.relatedDrawings),
            documentCount: snapshot.relatedDocuments.count,
            contactCount: snapshot.relatedContacts.count,
            missingReceiptCount: snapshot.missingReceiptCount,
            unsettledFinancialCount: snapshot.unsettledFinancialCount,
            unsettledFinancialAmount: unsettledFinancialAmount(snapshot: snapshot),
            openTodoCount: snapshot.openTodoCount,
            backupState: ProjectDeliveryBackupState.current(),
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
        drawingGroupsWithoutCurrentVersion(drawings).count
    }

    func drawingGroupsWithoutCurrentVersion(_ drawings: [ProjectDrawing]) -> [String] {
        guard !drawings.isEmpty else { return [] }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let nameKey = ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawing.name)
            return nameKey.isEmpty ? drawing.fileName : nameKey
        }
        return grouped.values.compactMap { group in
            guard !group.contains(where: \.isCurrentVersion) else { return nil }
            let sorted = group.sorted { lhs, rhs in
                if lhs.importedAt == rhs.importedAt {
                    return lhs.fileName < rhs.fileName
                }
                return lhs.importedAt > rhs.importedAt
            }
            guard let drawing = sorted.first else { return nil }
            let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? drawing.fileName : name
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func deliveryLogExpectation(project: Project, logs: [DailyLog]) -> (expectedCount: Int, missingCount: Int, samples: [String]) {
        guard let start = Formatters.date.date(from: project.startDate) else {
            return logs.isEmpty ? (0, 1, []) : (0, 0, [])
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let configuredEnd = Formatters.date.date(from: project.expectedEndDate) ?? today
        let effectiveEnd = min(calendar.startOfDay(for: configuredEnd), today)
        let normalizedStart = calendar.startOfDay(for: start)
        guard normalizedStart <= effectiveEnd else {
            return logs.isEmpty ? (0, 1, []) : (0, 0, [])
        }

        let loggedDates = Set(logs.compactMap { normalizedLogDateKey($0.date) })
        var expectedDates: [String] = []
        var cursor = normalizedStart
        while cursor <= effectiveEnd {
            expectedDates.append(Formatters.date.string(from: cursor))
            guard expectedDates.count < 370 else { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let missingDates = expectedDates.filter { !loggedDates.contains($0) }
        return (
            expectedDates.count,
            missingDates.count,
            Array(missingDates.prefix(5))
        )
    }

    func normalizedLogDateKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = Formatters.parseDateOrDateTime(trimmed) {
            return Formatters.date.string(from: date)
        }
        return trimmed
    }

    func unsettledFinancialAmount(snapshot: ProjectDetailSnapshot) -> Double {
        snapshot.relatedFinancialRecords
            .filter { record in
                record.normalizedStatus == .active
                    && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
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
