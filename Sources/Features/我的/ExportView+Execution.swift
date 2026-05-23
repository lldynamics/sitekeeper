import Foundation

extension ExportView {
    var currencyDisplayMode: ExportCurrencyDisplayMode {
        StringEnumFallback.value(currencyDisplayModeRaw, default: ExportCurrencyDisplayMode.defaultMode)
    }

    var hasSelectedContent: Bool {
        includeMaterials || includeQuotes || includeLabor || includeDailyLogs || includeProgress || includeTodos || includeProjectFinance || includeProjectDocuments || includeProjectContacts || includeProjectDrawings || includeWarehouseMovements || includeQuickNotes || includeOperationAuditLogs
    }

    var options: ExportContentOptions {
        ExportContentOptions(
            includeMaterials: includeMaterials,
            includeQuotes: includeQuotes,
            includeLabor: includeLabor,
            includeDailyLogs: includeDailyLogs,
            includeProgress: includeProgress,
            includeTodos: includeTodos,
            includeProjectFinance: includeProjectFinance,
            includeProjectDocuments: includeProjectDocuments,
            includeProjectContacts: includeProjectContacts,
            includeProjectDrawings: includeProjectDrawings,
            includeWarehouseMovements: includeWarehouseMovements,
            includeQuickNotes: includeQuickNotes,
            includeOperationAuditLogs: includeOperationAuditLogs,
            operationAuditEntries: includeOperationAuditLogs ? filteredOperationAuditEntries : [],
            currencyDisplayMode: currencyDisplayMode
        )
    }

    func buildExport() {
        let snapshot = filteredSnapshotResult(filterProjectId: filterProjectId).snapshot
        let nextPayload: ExportPayload
        switch exportFormat {
        case .csv:
            nextPayload = ExportPayload(data: ReportBuilder.makeCSV(snapshot: snapshot, options: options), contentType: .commaSeparatedText, defaultFilename: previewFilename)
        case .pdf:
            nextPayload = ExportPayload(data: ReportBuilder.makePDF(snapshot: snapshot, options: options), contentType: .pdf, defaultFilename: previewFilename)
        case .excel:
            nextPayload = ExportPayload(data: ReportBuilder.makeExcelHTML(snapshot: snapshot, options: options), contentType: .excelHTML, defaultFilename: previewFilename)
        }
        guard !nextPayload.data.isEmpty else {
            presentExportError(String(localized: "导出内容为空，未生成有效文件。请调整导出范围后重试。"))
            return
        }
        payload = nextPayload
        AppHaptics.impact(.light)
        showExporter = true
    }

    var previewFilename: String {
        let suffix: String = switch exportFormat {
        case .csv: ".csv"
        case .pdf: ".pdf"
        case .excel: ".xls"
        }
        if let projectId = filterProjectId,
           let name = store.projects.first(where: { $0.id == projectId })?.name {
            let safeName = name.replacingOccurrences(of: " ", with: "_")
            return "\(AppBrand.exportFilePrefix)_\(safeName)_\(String(localized: "导出"))\(suffix)"
        }
        return "\(AppBrand.exportFilePrefix)_\(String(localized: "导出"))\(suffix)"
    }

    var filteredOperationAuditEntries: [OperationAuditEntry] {
        let entries = OperationAuditLog.entries()
        guard enableDateFilter else { return entries }
        let start = Calendar.current.startOfDay(for: min(filterStart, filterEnd))
        let endStart = Calendar.current.startOfDay(for: max(filterStart, filterEnd))
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endStart) ?? endStart
        return entries.filter { entry in
            let timestamp = Date(timeIntervalSince1970: entry.timestamp)
            return timestamp >= start && timestamp < end
        }
    }

    func presentExportError(_ message: String) {
        exportErrorMessage = message
        showExportErrorAlert = true
        AppHaptics.error()
    }

    func validateExportedFile(at fileURL: URL) -> Bool {
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                StorageIssueLog.recordEvent(
                    "export.validate_file_not_regular",
                    category: .fileStorage,
                    details: [
                        "source": "ExportView.validateExportedFile",
                        "file_name": fileURL.lastPathComponent
                    ]
                )
                return false
            }
            guard let fileSize = values.fileSize, fileSize > 0 else {
                StorageIssueLog.recordEvent(
                    "export.validate_file_empty",
                    category: .fileStorage,
                    details: [
                        "source": "ExportView.validateExportedFile",
                        "file_name": fileURL.lastPathComponent
                    ]
                )
                return false
            }
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "export.validate_file_metadata_failed",
                category: .fileStorage,
                details: [
                    "source": "ExportView.validateExportedFile",
                    "file_name": fileURL.lastPathComponent
                ],
                error: error
            )
            return false
        }
    }

    func formatDataSafetyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    func filteredSnapshotResult(filterProjectId: UUID? = nil) -> FilteredExportResult {
        var snapshot = store.makeSnapshot(includePhotoFiles: false)
        if let pid = filterProjectId {
            snapshot.materialItems = snapshot.materialItems.filter { $0.projectId == pid }
            snapshot.quoteItems = snapshot.quoteItems.filter { $0.projectId == pid }
            snapshot.laborRecords = snapshot.laborRecords.filter { $0.projectId == pid }
            snapshot.dailyLogs = snapshot.dailyLogs.filter { $0.projectId == pid }
            snapshot.progressTasks = snapshot.progressTasks.filter { $0.projectId == pid }
            snapshot.siteTodos = snapshot.siteTodos.filter { $0.projectId == pid }
            snapshot.projectContacts = snapshot.projectContacts.filter { $0.projectId == pid }
            snapshot.projectFinancialRecords = snapshot.projectFinancialRecords.filter { $0.projectId == pid }
            snapshot.projectDocuments = snapshot.projectDocuments.filter { $0.projectId == pid }
            snapshot.projectDrawings = snapshot.projectDrawings.filter { $0.projectId == pid }
            snapshot.projectWarehouseMovements = snapshot.projectWarehouseMovements.filter { $0.projectId == pid }
            snapshot.quickNotes = snapshot.quickNotes.filter { $0.projectId == pid }
            snapshot.materialSheetDrafts = snapshot.materialSheetDrafts.filter { $0.projectId == pid }
            snapshot.historyRecords = snapshot.historyRecords.filter { $0.projectId == pid }
            snapshot.projects = snapshot.projects.filter { $0.id == pid }
        }

        guard enableDateFilter else { return FilteredExportResult(snapshot: snapshot, invalidDateCount: 0) }
        var invalidDateCount = 0
        snapshot.laborRecords = snapshot.laborRecords.filter {
            isWithinDateRange($0.date, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.dailyLogs = snapshot.dailyLogs.filter {
            isWithinDateRange($0.date, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.progressTasks = snapshot.progressTasks.filter {
            isWithinDateRange($0.startDate, format: Formatters.date, invalidDateCount: &invalidDateCount)
            || isWithinDateRange($0.dueDate, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.historyRecords = snapshot.historyRecords.filter {
            isWithinDateRange($0.date, format: Formatters.dateTime, invalidDateCount: &invalidDateCount)
        }
        snapshot.siteTodos = snapshot.siteTodos.filter {
            isWithinDateRange($0.dueDate, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.projectFinancialRecords = snapshot.projectFinancialRecords.filter {
            isWithinDateRange($0.date, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.projectDocuments = snapshot.projectDocuments.filter {
            isWithinDateRange($0.createdAt, format: Formatters.dateTime, invalidDateCount: &invalidDateCount)
        }
        snapshot.quoteItems = snapshot.quoteItems.filter {
            isWithinDateRange($0.customerConfirmedDate, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.projectDrawings = snapshot.projectDrawings.filter {
            isWithinDateRange($0.importedAt, format: Formatters.dateTime, invalidDateCount: &invalidDateCount)
        }
        snapshot.projectWarehouseMovements = snapshot.projectWarehouseMovements.filter {
            isWithinDateRange($0.date, format: Formatters.date, invalidDateCount: &invalidDateCount)
        }
        snapshot.quickNotes = snapshot.quickNotes.filter {
            isWithinDateRange($0.updatedAt, format: Formatters.dateTime, invalidDateCount: &invalidDateCount)
        }
        return FilteredExportResult(snapshot: snapshot, invalidDateCount: invalidDateCount)
    }

    func isWithinDateRange(_ dateString: String, format: DateFormatter, invalidDateCount: inout Int) -> Bool {
        guard let date = DataValueParser.parseDate(dateString, preferredFormatter: format) else {
            invalidDateCount += 1
            return false
        }
        let start = Calendar.current.startOfDay(for: min(filterStart, filterEnd))
        let endStart = Calendar.current.startOfDay(for: max(filterStart, filterEnd))
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endStart) ?? endStart
        return date >= start && date < end
    }
}
