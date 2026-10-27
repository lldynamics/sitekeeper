import SwiftUI

extension ProjectDetailContainer {
    func handleDeliveryRepairAction(_ action: ProjectDeliveryRepairAction, snapshot: ProjectDetailSnapshot) {
        switch action {
        case .attachReceipts:
            openMode(.finance, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            routeState.financeJumpFilter = .missingReceipt
            guard let record = firstMissingReceiptRecord(snapshot: snapshot) else {
                operationNotice = .info(AppLocalization.string("没有需要补票据的账目。"))
                return
            }
            presentAfterDeliveryGuideDismiss {
                financeState.attachmentManagingRecord = record
            }
        case .importDrawings:
            openMode(.assets, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            presentAfterDeliveryGuideDismiss {
                assetState.showDrawingImporter = true
            }
        case .resolveTodos:
            openMode(.records, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            presentAfterDeliveryGuideDismiss {
                showTodoFilterView = true
            }
        case .resolveDrawingIssues:
            openMode(.assets, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            routeState.drawingFilter = .withIssue
        case .createBackup:
            presentAfterDeliveryGuideDismiss {
                dataManagementDestination = ProjectDetailDataManagementDestination(route: .backup)
            }
        case .restoreMissingOriginals:
            openMode(.assets, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            presentAfterDeliveryGuideDismiss {
                if missingOriginalEntriesPreferDrawingImport(snapshot: snapshot) {
                    assetState.showDrawingImporter = true
                } else {
                    assetState.showDocumentFileImporter = true
                }
            }
        case .markCurrentDrawingVersion:
            openMode(.assets, prefersInlineSections: usesSingleCanvasLayoutOnPad)
            guard let drawing = latestDrawingFromFirstGroupWithoutCurrentVersion(snapshot.relatedDrawings) else {
                operationNotice = .info(AppLocalization.string("没有需要标记当前版的图纸组。"))
                return
            }
            setDrawingAsCurrentVersion(drawing)
            operationNotice = .info(
                String(
                    format: AppLocalization.string("已将“%@”标为当前版。"),
                    drawing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? drawing.fileName : drawing.name
                )
            )
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
            openDrawingIssueCount: openDrawingIssueCount(
                drawings: snapshot.relatedDrawings,
                todos: snapshot.relatedTodos
            ),
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

    func openDrawingIssueCount(drawings: [ProjectDrawing], todos: [SiteTodo]) -> Int {
        let todosByID = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        return drawings.filter { drawing in
            let linkedOpenTodoExists = drawing.linkedTodoIDs
                .compactMap { todosByID[$0] }
                .contains { !$0.isDone }
            let hasOpenDrawingStatus = drawing.issueStatus == .open
                || drawing.issueStatus == .inProgress
                || (drawing.issueStatus != .closed && !drawing.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return linkedOpenTodoExists || hasOpenDrawingStatus
        }.count
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

    func normalizedLogDateKey(_ value: BusinessDateValue) -> String? {
        value.calendarDay()?.storageText
    }

    func unsettledFinancialAmount(snapshot: ProjectDetailSnapshot) -> MoneyValue {
        snapshot.relatedFinancialRecords
            .filter { record in
                record.normalizedStatus == .active
                    && !record.dueDate.isEmpty
            }
            .reduce(MoneyValue.zero) { $0 + $1.amount }
    }

    private func presentAfterDeliveryGuideDismiss(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }

    private func firstMissingReceiptRecord(snapshot: ProjectDetailSnapshot) -> ProjectFinancialRecord? {
        snapshot.relatedFinancialRecords
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.date > rhs.date
            }
            .first { record in
                record.requiresAttachment && linkedDocuments(for: record).isEmpty
            }
    }

    private func missingOriginalEntriesPreferDrawingImport(snapshot: ProjectDetailSnapshot) -> Bool {
        let entries = ProjectDetailImportExportActions.missingProjectPackageFiles(
            documents: snapshot.relatedDocuments,
            drawings: snapshot.relatedDrawings,
            logs: snapshot.relatedLogs,
            quickNotes: snapshot.relatedQuickNotes
        )
        return entries.contains { entry in
            entry.localizedStandardContains(AppLocalization.string("图纸")) || entry.localizedCaseInsensitiveContains("drawing")
        }
    }

    private func latestDrawingFromFirstGroupWithoutCurrentVersion(_ drawings: [ProjectDrawing]) -> ProjectDrawing? {
        guard !drawings.isEmpty else { return nil }
        let grouped = Dictionary(grouping: drawings) { drawing in
            let nameKey = ProjectDetailDrawingHelper.normalizedDrawingNameKey(drawing.name)
            return nameKey.isEmpty ? drawing.fileName : nameKey
        }
        let unresolvedGroups = grouped.values
            .filter { !$0.contains(where: \.isCurrentVersion) }
            .sorted { lhs, rhs in
                let left = drawingGroupDisplayName(lhs)
                let right = drawingGroupDisplayName(rhs)
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        guard let firstGroup = unresolvedGroups.first else { return nil }
        return firstGroup.sorted { lhs, rhs in
            let leftVersion = ProjectDetailDrawingHelper.versionNumber(lhs.version) ?? -1
            let rightVersion = ProjectDetailDrawingHelper.versionNumber(rhs.version) ?? -1
            if leftVersion == rightVersion {
                return lhs.importedAt > rhs.importedAt
            }
            return leftVersion > rightVersion
        }.first
    }

    private func drawingGroupDisplayName(_ drawings: [ProjectDrawing]) -> String {
        guard let drawing = drawings.first else { return "" }
        let name = drawing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? drawing.fileName : name
    }
}
