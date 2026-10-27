import SwiftUI
import UniformTypeIdentifiers

private enum OperationAuditActionFilter: String, CaseIterable, Identifiable {
    case all
    case importAction
    case restore
    case cleanup
    case repair
    case delete

    var id: String { rawValue }

    var action: OperationAuditEntry.Action? {
        switch self {
        case .all:
            return nil
        case .importAction:
            return .import
        case .restore:
            return .restore
        case .cleanup:
            return .cleanup
        case .repair:
            return .repair
        case .delete:
            return .delete
        }
    }

    var displayName: String {
        switch self {
        case .all:
            return AppLocalization.string("全部操作")
        case .importAction:
            return AppLocalization.string("导入")
        case .restore:
            return AppLocalization.string("恢复")
        case .cleanup:
            return AppLocalization.string("清理")
        case .repair:
            return AppLocalization.string("修复")
        case .delete:
            return AppLocalization.string("删除")
        }
    }
}

private enum OperationAuditOutcomeFilter: String, CaseIterable, Identifiable {
    case all
    case started
    case succeeded
    case failed
    case cancelled

    var id: String { rawValue }

    var outcome: OperationAuditEntry.Outcome? {
        switch self {
        case .all:
            return nil
        case .started:
            return .started
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }

    var displayName: String {
        switch self {
        case .all:
            return AppLocalization.string("全部结果")
        case .started:
            return AppLocalization.string("开始")
        case .succeeded:
            return AppLocalization.string("完成")
        case .failed:
            return AppLocalization.string("失败")
        case .cancelled:
            return AppLocalization.string("取消")
        }
    }
}

struct OperationAuditLogView: View {
    @State private var actionFilter: OperationAuditActionFilter = .all
    @State private var outcomeFilter: OperationAuditOutcomeFilter = .all
    @State private var searchText = ""
    @State private var refreshToken = UUID()
    @State private var exportPayload: ExportPayload?
    @State private var showExporter = false
    @State private var showClearConfirm = false
    @State private var operationNotice: OperationToastNotice?

    private let showsNavigationTitle: Bool
    private let bottomContentInset: CGFloat
    private let onMobileScrollOffsetChange: ((CGFloat) -> Void)?

    init(
        showsNavigationTitle: Bool = true,
        bottomContentInset: CGFloat = 0,
        onMobileScrollOffsetChange: ((CGFloat) -> Void)? = nil
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.bottomContentInset = bottomContentInset
        self.onMobileScrollOffsetChange = onMobileScrollOffsetChange
    }

    private var entries: [OperationAuditEntry] {
        _ = refreshToken
        return OperationAuditLog.entries()
    }

    private var filteredEntries: [OperationAuditEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let action = actionFilter.action, entry.action != action {
                return false
            }
            if let outcome = outcomeFilter.outcome, entry.outcome != outcome {
                return false
            }
            guard !query.isEmpty else { return true }
            return [
                actionLabel(entry.action),
                outcomeLabel(entry.outcome),
                entry.summary,
                entry.detail,
                entry.source,
                entry.id.uuidString
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        List {
            if onMobileScrollOffsetChange != nil {
                DataManagementMobileScrollProbeRow(onOffsetChange: onMobileScrollOffsetChange)
            }

            Section {
                LabeledContent(AppLocalization.string("记录数"), value: "\(entries.count)")
                LabeledContent(AppLocalization.string("当前筛选"), value: "\(filteredEntries.count)")
            }

            Section(AppLocalization.string("筛选")) {
                Picker(AppLocalization.string("操作"), selection: $actionFilter) {
                    ForEach(OperationAuditActionFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                Picker(AppLocalization.string("结果"), selection: $outcomeFilter) {
                    ForEach(OperationAuditOutcomeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
            }

            Section(AppLocalization.string("导出操作")) {
                Button {
                    exportFilteredEntries()
                } label: {
                    Label(AppLocalization.string("导出当前筛选 CSV"), systemImage: "doc.text")
                }
                .disabled(filteredEntries.isEmpty)

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(AppLocalization.string("清空操作审计日志"), systemImage: "trash")
                }
                .disabled(entries.isEmpty)
            }

            Section(AppLocalization.string("最近记录")) {
                if entries.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("暂无审计记录"),
                        systemImage: "checkmark.shield",
                        description: Text(AppLocalization.string("高风险操作记录会显示在这里。"))
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        AppLocalization.string("无匹配记录"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text(AppLocalization.string("调整筛选或搜索条件后重试。"))
                    )
                } else {
                    ForEach(filteredEntries) { entry in
                        NavigationLink {
                            OperationAuditEntryDetailView(entry: entry)
                        } label: {
                            auditRow(entry)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomContentInset)
        }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索审计日志"))
        .modifier(OperationAuditInlineTitleModifier(
            isEnabled: showsNavigationTitle,
            title: AppLocalization.string("操作审计日志")
        ))
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportPayload?.data ?? Data()),
            contentType: exportPayload?.contentType ?? .commaSeparatedText,
            defaultFilename: exportPayload?.defaultFilename ?? AppLocalization.string("操作审计日志.csv")
        ) { result in
            handleExportCompletion(result)
        }
        .confirmationDialog(AppLocalization.string("清空审计日志？"), isPresented: $showClearConfirm) {
            Button(AppLocalization.string("清空日志"), role: .destructive) {
                OperationAuditLog.clear()
                refreshToken = UUID()
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("将删除本机保存的审计记录，此操作不会影响业务数据。"))
        }
        .operationToast(notice: $operationNotice)
    }

    private func auditRow(_ entry: OperationAuditEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage(entry.action))
                .foregroundStyle(color(entry.outcome))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(actionLabel(entry.action)) · \(outcomeLabel(entry.outcome))")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func exportFilteredEntries() {
        let headers = [
            AppLocalization.string("时间"),
            AppLocalization.string("操作"),
            AppLocalization.string("结果"),
            AppLocalization.string("摘要"),
            AppLocalization.string("详情"),
            AppLocalization.string("来源"),
            "ID"
        ]
        let rows = filteredEntries.map { entry in
            ReportBuilder.csv([
                Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp)),
                actionLabel(entry.action),
                outcomeLabel(entry.outcome),
                entry.summary,
                entry.detail,
                entry.source,
                entry.id.uuidString
            ])
        }
        let lines = [ReportBuilder.csv(headers)] + rows
        exportPayload = ExportPayload(
            data: Data(lines.joined(separator: "\n").utf8),
            contentType: .commaSeparatedText,
            defaultFilename: AppLocalization.string("操作审计日志.csv")
        )
        showExporter = true
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        let outcome = ExportCompletionHandler.evaluate(result, source: "OperationAuditLogView")
        operationNotice = ExportCompletionHandler.notice(for: outcome) {
            guard exportPayload != nil else { return }
            showExporter = true
        }
    }

    private func actionLabel(_ action: OperationAuditEntry.Action) -> String {
        switch action {
        case .import:
            return AppLocalization.string("导入")
        case .restore:
            return AppLocalization.string("恢复")
        case .cleanup:
            return AppLocalization.string("清理")
        case .repair:
            return AppLocalization.string("修复")
        case .delete:
            return AppLocalization.string("删除")
        }
    }

    private func outcomeLabel(_ outcome: OperationAuditEntry.Outcome) -> String {
        switch outcome {
        case .started:
            return AppLocalization.string("开始")
        case .succeeded:
            return AppLocalization.string("完成")
        case .failed:
            return AppLocalization.string("失败")
        case .cancelled:
            return AppLocalization.string("取消")
        }
    }

    private func systemImage(_ action: OperationAuditEntry.Action) -> String {
        switch action {
        case .import:
            return "square.and.arrow.down"
        case .restore:
            return "arrow.uturn.backward.circle"
        case .cleanup:
            return "trash"
        case .repair:
            return "wrench.and.screwdriver"
        case .delete:
            return "trash.slash"
        }
    }

    private func color(_ outcome: OperationAuditEntry.Outcome) -> Color {
        switch outcome {
        case .started:
            return .appPrimaryAction
        case .succeeded:
            return .appSuccess
        case .failed:
            return .appRisk
        case .cancelled:
            return .appWarning
        }
    }
}

private struct OperationAuditInlineTitleModifier: ViewModifier {
    let isEnabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

private struct OperationAuditEntryDetailView: View {
    let entry: OperationAuditEntry

    var body: some View {
        List {
            Section(AppLocalization.string("摘要")) {
                Text(entry.summary)
                LabeledContent(
                    AppLocalization.string("记录时间"),
                    value: Formatters.dateTime.string(from: Date(timeIntervalSince1970: entry.timestamp))
                )
                LabeledContent(AppLocalization.string("操作"), value: actionLabel(entry.action))
                LabeledContent(AppLocalization.string("结果"), value: outcomeLabel(entry.outcome))
                if !entry.source.isEmpty {
                    LabeledContent(AppLocalization.string("来源"), value: entry.source)
                }
                LabeledContent(AppLocalization.string("操作 ID"), value: entry.id.uuidString)
            }

            if !entry.detail.isEmpty {
                Section(AppLocalization.string("详情")) {
                    Text(entry.detail)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(AppLocalization.string("审计详情"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func actionLabel(_ action: OperationAuditEntry.Action) -> String {
        switch action {
        case .import:
            return AppLocalization.string("导入")
        case .restore:
            return AppLocalization.string("恢复")
        case .cleanup:
            return AppLocalization.string("清理")
        case .repair:
            return AppLocalization.string("修复")
        case .delete:
            return AppLocalization.string("删除")
        }
    }

    private func outcomeLabel(_ outcome: OperationAuditEntry.Outcome) -> String {
        switch outcome {
        case .started:
            return AppLocalization.string("开始")
        case .succeeded:
            return AppLocalization.string("完成")
        case .failed:
            return AppLocalization.string("失败")
        case .cancelled:
            return AppLocalization.string("取消")
        }
    }
}
