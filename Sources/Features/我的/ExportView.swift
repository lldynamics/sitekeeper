import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    fileprivate struct FilteredExportResult {
        var snapshot: BackupSnapshot
        var invalidDateCount: Int
    }

    @Environment(DataStore.self) private var store
    @State private var exportFormat: ExportFormat = .csv
    @State private var includeMaterials = true
    @State private var includeQuotes = true
    @State private var includeLabor = true
    @State private var includeDailyLogs = true
    @State private var includeProgress = true
    @State private var includeTodos = true
    @State private var includeProjectFinance = true
    @State private var includeProjectDocuments = true
    @State private var includeProjectContacts = true
    @State private var includeProjectDrawings = true
    @State private var includeWarehouseMovements = true
    @State private var includeQuickNotes = true
    @State private var includeLightingCircuits = true
    @State private var includePaymentRecords = true
    @State private var filterProjectId: UUID?
    @State private var enableDateFilter = false
    @State private var filterStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var filterEnd = Date()
    @State private var payload: ExportPayload?
    @State private var showExporter = false

    private var previewResult: FilteredExportResult {
        filteredSnapshotResult(filterProjectId: filterProjectId)
    }

    var body: some View {
        Form {
            Section("导出格式") {
                Picker("格式", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("导出内容") {
                Toggle("材料清单", isOn: $includeMaterials)
                Toggle("报价明细", isOn: $includeQuotes)
                Toggle("人工记录", isOn: $includeLabor)
                Toggle("施工日志", isOn: $includeDailyLogs)
                Toggle("施工进度", isOn: $includeProgress)
                Toggle("现场待办", isOn: $includeTodos)
                Toggle("项目财务流水", isOn: $includeProjectFinance)
                Toggle("项目票据资料", isOn: $includeProjectDocuments)
                Toggle("项目联系人", isOn: $includeProjectContacts)
                Toggle("图纸索引", isOn: $includeProjectDrawings)
                Toggle("仓库流水", isOn: $includeWarehouseMovements)
                Toggle("随手记", isOn: $includeQuickNotes)
                Toggle("照明回路", isOn: $includeLightingCircuits)
                Toggle("付款记录", isOn: $includePaymentRecords)
            }

            Section("导出范围") {
                Picker("项目", selection: $filterProjectId) {
                    Text("全部项目").tag(nil as UUID?)
                    ForEach(store.projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
                Toggle("启用日期范围", isOn: $enableDateFilter)
                if enableDateFilter {
                    DatePicker("开始", selection: $filterStart, displayedComponents: .date)
                    DatePicker("结束", selection: $filterEnd, displayedComponents: .date)
                }
            }

            Section("格式预览") {
                let snapshot = previewResult.snapshot
                LabeledContent("材料条数", value: includeMaterials ? "\(snapshot.materialItems.count)" : "-")
                LabeledContent("报价条数", value: includeQuotes ? "\(snapshot.quoteItems.count)" : "-")
                LabeledContent("人工条数", value: includeLabor ? "\(snapshot.laborRecords.count)" : "-")
                LabeledContent("日志条数", value: includeDailyLogs ? "\(snapshot.dailyLogs.count)" : "-")
                LabeledContent("进度条数", value: includeProgress ? "\(snapshot.progressTasks.count)" : "-")
                LabeledContent("待办条数", value: includeTodos ? "\(snapshot.siteTodos.count)" : "-")
                LabeledContent("财务条数", value: includeProjectFinance ? "\(snapshot.projectFinancialRecords.count)" : "-")
                LabeledContent("票据条数", value: includeProjectDocuments ? "\(snapshot.projectDocuments.count)" : "-")
                LabeledContent("联系人数", value: includeProjectContacts ? "\(snapshot.projectContacts.count)" : "-")
                LabeledContent("图纸条数", value: includeProjectDrawings ? "\(snapshot.projectDrawings.count)" : "-")
                LabeledContent("仓库流水条数", value: includeWarehouseMovements ? "\(snapshot.projectWarehouseMovements.count)" : "-")
                LabeledContent("随手记条数", value: includeQuickNotes ? "\(snapshot.quickNotes.count)" : "-")
                LabeledContent("回路方案数", value: includeLightingCircuits ? "\(snapshot.lightingCircuitPlans.count)" : "-")
                LabeledContent("付款记录条数", value: includePaymentRecords ? "\(snapshot.paymentRecords.count)" : "-")
                LabeledContent("日期格式异常", value: enableDateFilter ? "\(previewResult.invalidDateCount)" : "-")
                LabeledContent("文件名", value: previewFilename)
                if enableDateFilter, previewResult.invalidDateCount > 0 {
                    Text(String(localized: "有 \(previewResult.invalidDateCount) 条记录日期格式异常，已按\"不命中日期筛选\"处理。"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    buildExport()
                } label: {
                    Label("导出文件", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasSelectedContent)
            }
        }
        .navigationTitle("导出数据")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: payload?.data ?? Data()),
            contentType: payload?.contentType ?? .data,
            defaultFilename: payload?.defaultFilename ?? "\(AppBrand.exportFilePrefix)_导出"
        ) { _ in }
    }

    private var hasSelectedContent: Bool {
        includeMaterials || includeQuotes || includeLabor || includeDailyLogs || includeProgress || includeTodos || includeProjectFinance || includeProjectDocuments || includeProjectContacts || includeProjectDrawings || includeWarehouseMovements || includeQuickNotes || includeLightingCircuits || includePaymentRecords
    }

    private var options: ExportContentOptions {
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
            includeLightingCircuits: includeLightingCircuits,
            includePaymentRecords: includePaymentRecords
        )
    }

    private func buildExport() {
        let snapshot = filteredSnapshotResult(filterProjectId: filterProjectId).snapshot
        switch exportFormat {
        case .csv:
            payload = ExportPayload(data: ReportBuilder.makeCSV(snapshot: snapshot, options: options), contentType: .commaSeparatedText, defaultFilename: previewFilename)
        case .pdf:
            payload = ExportPayload(data: ReportBuilder.makePDF(snapshot: snapshot, options: options), contentType: .pdf, defaultFilename: previewFilename)
        case .excel:
            payload = ExportPayload(data: ReportBuilder.makeExcelHTML(snapshot: snapshot, options: options), contentType: .excelHTML, defaultFilename: previewFilename)
        }
        showExporter = true
    }

    private var previewFilename: String {
        let suffix: String = switch exportFormat {
        case .csv: ".csv"
        case .pdf: ".pdf"
        case .excel: ".xls"
        }
        if let projectId = filterProjectId,
           let name = store.projects.first(where: { $0.id == projectId })?.name {
            let safeName = name.replacingOccurrences(of: " ", with: "_")
            return "\(AppBrand.exportFilePrefix)_\(safeName)_导出\(suffix)"
        }
        return "\(AppBrand.exportFilePrefix)_导出\(suffix)"
    }

    private func filteredSnapshotResult(filterProjectId: UUID? = nil) -> FilteredExportResult {
        var snapshot = store.makeSnapshot(includePhotoFiles: false)
        if let pid = filterProjectId {
            snapshot.materialItems = snapshot.materialItems.filter { $0.projectId == pid }
            snapshot.quoteItems = snapshot.quoteItems.filter { $0.projectId == pid }
            snapshot.laborRecords = snapshot.laborRecords.filter { $0.projectId == pid }
            snapshot.dailyLogs = snapshot.dailyLogs.filter { $0.projectId == pid }
            snapshot.progressTasks = snapshot.progressTasks.filter { $0.projectId == pid }
            snapshot.lightingCircuitPlans = snapshot.lightingCircuitPlans.filter { $0.projectId == pid }
            snapshot.siteTodos = snapshot.siteTodos.filter { $0.projectId == pid }
            snapshot.projectContacts = snapshot.projectContacts.filter { $0.projectId == pid }
            snapshot.projectFinancialRecords = snapshot.projectFinancialRecords.filter { $0.projectId == pid }
            snapshot.projectDocuments = snapshot.projectDocuments.filter { $0.projectId == pid }
            snapshot.paymentRecords = snapshot.paymentRecords.filter { $0.projectId == pid }
            snapshot.projectDrawings = snapshot.projectDrawings.filter { $0.projectId == pid }
            snapshot.projectWarehouseMovements = snapshot.projectWarehouseMovements.filter { $0.projectId == pid }
            snapshot.quickNotes = snapshot.quickNotes.filter { $0.projectId == pid }
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
        snapshot.paymentRecords = snapshot.paymentRecords.filter {
            isWithinDateRange($0.date, format: Formatters.date, invalidDateCount: &invalidDateCount)
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
        snapshot.lightingCircuitPlans = snapshot.lightingCircuitPlans.filter {
            isWithinDateRange($0.updatedAt, format: Formatters.dateTime, invalidDateCount: &invalidDateCount)
        }
        return FilteredExportResult(snapshot: snapshot, invalidDateCount: invalidDateCount)
    }

    private func isWithinDateRange(_ dateString: String, format: DateFormatter, invalidDateCount: inout Int) -> Bool {
        guard let date = format.date(from: dateString) else {
            invalidDateCount += 1
            return false
        }
        let start = Calendar.current.startOfDay(for: min(filterStart, filterEnd))
        let endStart = Calendar.current.startOfDay(for: max(filterStart, filterEnd))
        let end = Calendar.current.date(byAdding: .day, value: 1, to: endStart) ?? endStart
        return date >= start && date < end
    }
}

enum ExportFormat: String, CaseIterable {
    case csv
    case pdf
    case excel

    var displayName: String {
        switch self {
        case .csv: "CSV"
        case .pdf: "PDF"
        case .excel: "Excel"
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .plainText, .commaSeparatedText, .pdf, .excelHTML, .zipArchive, .jpeg] }
    var data: Data
    var sourceFileURL: URL?

    init(data: Data, sourceFileURL: URL? = nil) {
        self.data = data
        self.sourceFileURL = sourceFileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        sourceFileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceFileURL,
           FileManager.default.fileExists(atPath: sourceFileURL.path) {
            return try FileWrapper(url: sourceFileURL, options: .immediate)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
