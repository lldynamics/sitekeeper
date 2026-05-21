import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct ExportView: View {
    fileprivate struct FilteredExportResult {
        var snapshot: BackupSnapshot
        var invalidDateCount: Int
    }

    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var includeOperationAuditLogs = false
    @State private var filterProjectId: UUID?
    @State private var enableDateFilter = false
    @State private var filterStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var filterEnd = Date()
    @State private var payload: ExportPayload?
    @State private var showExporter = false
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage = ""
    @AppStorage(UserPreferenceKeys.exportCurrencyDisplayMode) private var currencyDisplayModeRaw = ExportCurrencyDisplayMode.defaultMode.rawValue
    private let showsNavigationTitle: Bool

    init(showsNavigationTitle: Bool = true) {
        self.showsNavigationTitle = showsNavigationTitle
    }

    private var previewResult: FilteredExportResult {
        filteredSnapshotResult(filterProjectId: filterProjectId)
    }

    private var selectedProjectName: String {
        guard let filterProjectId,
              let project = store.projects.first(where: { $0.id == filterProjectId }) else {
            return String(localized: "全部项目")
        }
        return project.name
    }

    private var exportRangeSummary: String {
        if enableDateFilter {
            let start = formatDataSafetyDate(min(filterStart, filterEnd))
            let end = formatDataSafetyDate(max(filterStart, filterEnd))
            return "\(selectedProjectName) · \(start) - \(end)"
        }
        return selectedProjectName
    }

    private var enabledExportModuleCount: Int {
        [
            includeMaterials,
            includeQuotes,
            includeLabor,
            includeDailyLogs,
            includeProgress,
            includeTodos,
            includeProjectFinance,
            includeProjectDocuments,
            includeProjectContacts,
            includeProjectDrawings,
            includeWarehouseMovements,
            includeQuickNotes,
            includeOperationAuditLogs,
        ].filter { $0 }.count
    }

    private var exportStatusItems: [DataSafetyStatusItem] {
        var items: [DataSafetyStatusItem] = [
            DataSafetyStatusItem(
                title: String(localized: "当前范围"),
                value: exportRangeSummary,
                tone: .primary
            ),
            DataSafetyStatusItem(
                title: String(localized: "导出内容"),
                value: String(format: String(localized: "%lld 个模块"), Int64(enabledExportModuleCount)),
                tone: enabledExportModuleCount == 0 ? .warning : .doc
            ),
            DataSafetyStatusItem(
                title: String(localized: "输出文件"),
                value: previewFilename,
                tone: .neutral
            ),
        ]

        if enableDateFilter {
            items.append(
                DataSafetyStatusItem(
                    title: String(localized: "日期格式异常"),
                    value: String(format: String(localized: "%lld 条"), Int64(previewResult.invalidDateCount)),
                    tone: previewResult.invalidDateCount == 0 ? .success : .warning
                )
            )
        }

        return items
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var exportSurface: some View {
        Group {
            if usesWideLayout {
                HStack(alignment: .top, spacing: 14) {
                    exportSidebar
                        .frame(minWidth: 280, maxWidth: 340)
                    exportDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Form {
                    exportFormatSection
                    exportContentSection
                    exportScopeSection
                    exportPreviewSection
                    exportButtonSection
                }
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: payload?.data ?? Data()),
            contentType: payload?.contentType ?? .data,
            defaultFilename: payload?.defaultFilename ?? "\(AppBrand.exportFilePrefix)_\(String(localized: "导出"))"
        ) { result in
            switch result {
            case .success(let exportedURL):
                guard validateExportedFile(at: exportedURL) else {
                    presentExportError(String(localized: "导出文件为空或写入不完整，请重试。"))
                    return
                }
                AppHaptics.success()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    presentExportError("\(String(localized: "导出失败"))：\(error.localizedDescription)")
                }
            }
        }
    }

    private var currencyDisplayMode: ExportCurrencyDisplayMode {
        StringEnumFallback.value(currencyDisplayModeRaw, default: ExportCurrencyDisplayMode.defaultMode)
    }

    var body: some View {
        Group {
            if showsNavigationTitle {
                exportSurface
                    .navigationTitle(String(localized: "数据安全中心"))
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                exportSurface
            }
        }
        .alert(String(localized: "导出失败"), isPresented: $showExportErrorAlert) {
            Button(String(localized: "知道了"), role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    // MARK: - iPad 双栏布局

    private var exportSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "导出交付"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                    Text(String(localized: "从安全中心筛选交付范围、格式和字段，再生成导出文件。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(DataSafetySidebarPanelModifier())

                exportFormatSection
                exportContentSection
            }
            .padding(.vertical, 2)
        }
    }

    private var exportDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DataSafetyStatusStrip(items: exportStatusItems)
                exportScopeSection
                exportPreviewSection
                exportButtonSection
            }
            .padding(4)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 提取的 Section 视图

    private func iPadPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(DataSafetySidebarPanelModifier())
    }

    private struct DataSafetySidebarPanelModifier: ViewModifier {
        func body(content: Content) -> some View {
            AppPanel(
                tone: .grouped,
                cornerRadius: 12,
                padding: 12,
                stroke: Color.appStrokeSecondary.opacity(0.45)
            ) {
                content
            }
        }
    }

    private var exportFormatSection: some View {
        Group {
            if usesWideLayout {
                iPadPanel(String(localized: "1. 选择格式")) {
                    exportFormatContent
                }
            } else {
                Section(String(localized: "导出格式")) {
                    exportFormatContent
                }
            }
        }
    }

    private var exportContentSection: some View {
        Group {
            if usesWideLayout {
                iPadPanel(String(localized: "2. 选择内容")) {
                    exportContentRows
                }
            } else {
                Section(String(localized: "导出内容")) {
                    exportContentRows
                }
            }
        }
    }

    private var exportScopeSection: some View {
        Group {
            if usesWideLayout {
                iPadPanel(String(localized: "3. 选择范围")) {
                    exportScopeRows
                }
            } else {
                Section(String(localized: "导出范围")) {
                    exportScopeRows
                }
            }
        }
    }

    private var exportPreviewSection: some View {
        Group {
            if usesWideLayout {
                iPadPanel(String(localized: "4. 预览输出")) {
                    exportPreviewRows
                }
            } else {
                Section(String(localized: "格式预览")) {
                    exportPreviewRows
                }
            }
        }
    }

    private var exportButtonSection: some View {
        Group {
            if usesWideLayout {
                iPadPanel(String(localized: "5. 生成交付文件")) {
                    exportButtonRow
                }
            } else {
                Section {
                    exportButtonRow
                }
            }
        }
    }

    @ViewBuilder
    private var exportFormatContent: some View {
        Picker(String(localized: "格式"), selection: $exportFormat) {
            ForEach(ExportFormat.allCases, id: \.self) { f in
                Text(f.displayName).tag(f)
            }
        }
        .pickerStyle(.segmented)

        Picker(String(localized: "金额显示"), selection: $currencyDisplayModeRaw) {
            ForEach(ExportCurrencyDisplayMode.allCases) { mode in
                Text(mode.displayName).tag(mode.rawValue)
            }
        }

        Text(
            String(
                format: String(localized: "预览：%@。CSV 会同时保留 amount_raw 数字列，amount_display 按这里显示。"),
                currencyDisplayMode.format(1234.5)
            )
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var exportContentRows: some View {
        Group {
            Toggle(String(localized: "材料清单"), isOn: $includeMaterials)
            Toggle(String(localized: "报价明细"), isOn: $includeQuotes)
            Toggle(String(localized: "人工记录"), isOn: $includeLabor)
            Toggle(String(localized: "施工日志"), isOn: $includeDailyLogs)
            Toggle(String(localized: "施工进度"), isOn: $includeProgress)
            Toggle(String(localized: "现场待办"), isOn: $includeTodos)
            Toggle(String(localized: "项目财务流水"), isOn: $includeProjectFinance)
            Toggle(String(localized: "项目票据资料"), isOn: $includeProjectDocuments)
            Toggle(String(localized: "项目联系人"), isOn: $includeProjectContacts)
            Toggle(String(localized: "图纸索引"), isOn: $includeProjectDrawings)
            Toggle(String(localized: "仓库流水"), isOn: $includeWarehouseMovements)
            Toggle(String(localized: "随手记"), isOn: $includeQuickNotes)
            Toggle(String(localized: "操作审计日志"), isOn: $includeOperationAuditLogs)
            if includeOperationAuditLogs {
                Text(String(localized: "审计日志仅随本次数据导出写入文件，不会进入默认备份。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportScopeRows: some View {
        Group {
            Picker(String(localized: "项目"), selection: $filterProjectId) {
                Text(String(localized: "全部项目")).tag(nil as UUID?)
                ForEach(store.projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            Toggle(String(localized: "启用日期范围"), isOn: $enableDateFilter)
            if enableDateFilter {
                DatePicker(String(localized: "开始"), selection: $filterStart, displayedComponents: .date)
                DatePicker(String(localized: "结束"), selection: $filterEnd, displayedComponents: .date)
            }
        }
    }

    private var exportPreviewRows: some View {
        let snapshot = previewResult.snapshot
        return Group {
            LabeledContent(String(localized: "材料条数"), value: includeMaterials ? "\(snapshot.materialItems.count)" : "-")
            LabeledContent(String(localized: "报价条数"), value: includeQuotes ? "\(snapshot.quoteItems.count)" : "-")
            LabeledContent(String(localized: "人工条数"), value: includeLabor ? "\(snapshot.laborRecords.count)" : "-")
            LabeledContent(String(localized: "日志条数"), value: includeDailyLogs ? "\(snapshot.dailyLogs.count)" : "-")
            LabeledContent(String(localized: "进度条数"), value: includeProgress ? "\(snapshot.progressTasks.count)" : "-")
            LabeledContent(String(localized: "待办条数"), value: includeTodos ? "\(snapshot.siteTodos.count)" : "-")
            LabeledContent(String(localized: "财务条数"), value: includeProjectFinance ? "\(snapshot.projectFinancialRecords.count)" : "-")
            LabeledContent(String(localized: "票据条数"), value: includeProjectDocuments ? "\(snapshot.projectDocuments.count)" : "-")
            LabeledContent(String(localized: "联系人数"), value: includeProjectContacts ? "\(snapshot.projectContacts.count)" : "-")
            LabeledContent(String(localized: "图纸条数"), value: includeProjectDrawings ? "\(snapshot.projectDrawings.count)" : "-")
            LabeledContent(String(localized: "仓库流水条数"), value: includeWarehouseMovements ? "\(snapshot.projectWarehouseMovements.count)" : "-")
            LabeledContent(String(localized: "随手记条数"), value: includeQuickNotes ? "\(snapshot.quickNotes.count)" : "-")
            LabeledContent(String(localized: "审计日志条数"), value: includeOperationAuditLogs ? "\(filteredOperationAuditEntries.count)" : "-")
            LabeledContent(String(localized: "日期格式异常"), value: enableDateFilter ? "\(previewResult.invalidDateCount)" : "-")
            LabeledContent(String(localized: "文件名"), value: previewFilename)
            if enableDateFilter, previewResult.invalidDateCount > 0 {
                Text(
                    String(
                        format: String(localized: "有 %lld 条记录日期格式异常，已按\"不命中日期筛选\"处理。"),
                        Int64(previewResult.invalidDateCount)
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.appWarning)
            }
        }
    }

    private var exportButtonRow: some View {
        Button {
            buildExport()
        } label: {
            Label(String(localized: "导出文件"), systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .disabled(!hasSelectedContent)
    }

    // MARK: - 导出逻辑

    private var hasSelectedContent: Bool {
        includeMaterials || includeQuotes || includeLabor || includeDailyLogs || includeProgress || includeTodos || includeProjectFinance || includeProjectDocuments || includeProjectContacts || includeProjectDrawings || includeWarehouseMovements || includeQuickNotes || includeOperationAuditLogs
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
            includeOperationAuditLogs: includeOperationAuditLogs,
            operationAuditEntries: includeOperationAuditLogs ? filteredOperationAuditEntries : [],
            currencyDisplayMode: currencyDisplayMode
        )
    }

    private func buildExport() {
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

    private var previewFilename: String {
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

    private var filteredOperationAuditEntries: [OperationAuditEntry] {
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

    private func presentExportError(_ message: String) {
        exportErrorMessage = message
        showExportErrorAlert = true
        AppHaptics.error()
    }

    private func validateExportedFile(at fileURL: URL) -> Bool {
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                StorageIssueLog.record("导出文件校验失败：目标不是普通文件，\(fileURL.lastPathComponent)")
                return false
            }
            guard let fileSize = values.fileSize, fileSize > 0 else {
                StorageIssueLog.record("导出文件校验失败：文件为空，\(fileURL.lastPathComponent)")
                return false
            }
            return true
        } catch {
            StorageIssueLog.record("导出文件校验失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            return false
        }
    }

    private func formatDataSafetyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func filteredSnapshotResult(filterProjectId: UUID? = nil) -> FilteredExportResult {
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

    private func isWithinDateRange(_ dateString: String, format: DateFormatter, invalidDateCount: inout Int) -> Bool {
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
    static var readableContentTypes: [UTType] { [.data, .plainText, .commaSeparatedText, .pdf, .excelHTML, .zipArchive, .jpeg, .png] }
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
