import SwiftUI
import Foundation

private struct ExportSidebarPanelModifier: ViewModifier {
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

extension ExportView {
    var previewResult: FilteredExportResult {
        filteredSnapshotResult(filterProjectId: filterProjectId)
    }

    var selectedProjectName: String {
        guard let filterProjectId,
              let project = store.projects.first(where: { $0.id == filterProjectId }) else {
            return String(localized: "全部项目")
        }
        return project.name
    }

    var exportRangeSummary: String {
        if enableDateFilter {
            let start = formatDataSafetyDate(min(filterStart, filterEnd))
            let end = formatDataSafetyDate(max(filterStart, filterEnd))
            return "\(selectedProjectName) · \(start) - \(end)"
        }
        return selectedProjectName
    }

    var enabledExportModuleCount: Int {
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

    var exportStatusItems: [DataSafetyStatusItem] {
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

    var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var exportSurface: some View {
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomContentInset)
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

    var exportSidebar: some View {
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
                .modifier(ExportSidebarPanelModifier())

                exportFormatSection
                exportContentSection
            }
            .padding(.vertical, 2)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
    }

    var exportDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DataSafetyStatusStrip(items: exportStatusItems)
                exportScopeSection
                exportPreviewSection
                exportButtonSection
            }
            .padding(4)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    func iPadPanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ExportSidebarPanelModifier())
    }

    var exportFormatSection: some View {
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

    var exportContentSection: some View {
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

    var exportScopeSection: some View {
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

    var exportPreviewSection: some View {
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

    var exportButtonSection: some View {
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
    var exportFormatContent: some View {
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

    var exportContentRows: some View {
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

    var exportScopeRows: some View {
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

    var exportPreviewRows: some View {
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

    var exportButtonRow: some View {
        Button {
            buildExport()
        } label: {
            Label(String(localized: "导出文件"), systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .disabled(!hasSelectedContent)
    }
}
