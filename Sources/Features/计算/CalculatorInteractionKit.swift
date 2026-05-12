import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CalculatorInputParser {
    static func double(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    static func int(_ value: String) -> Int? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return Int(normalized)
    }
}

struct CalculatorValidationHint: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.appRisk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message)
                .accessibilityHint("输入校验提示")
        }
    }
}

struct CalculatorPresetChips: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            selection = option
                            AppHaptics.impact(.light, intensity: 0.65)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selection == option ? Color.appPrimaryAction : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundStyle(selection == option ? .white : .primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(title) \(option)")
                        .accessibilityValue(selection == option ? "已选中" : "未选中")
                        .accessibilityHint("双击切换")
                    }
                }
            }
        }
    }
}

struct CalculationResult {
    let headline: String
    let formula: String?
    let sections: [ResultSection]

    struct ResultSection {
        let title: String
        let items: [ResultItem]
    }

    struct ResultItem {
        let label: String
        let value: String
        let status: ResultStatus
    }

    enum ResultStatus: Equatable {
        case normal
        case pass
        case warning
        case fail

        var valueColor: Color {
            switch self {
            case .normal:
                return .primary
            case .pass:
                return .appSuccess
            case .warning:
                return .appPrimaryAction
            case .fail:
                return .appRisk
            }
        }

        var rowBackgroundColor: Color {
            switch self {
            case .normal:
                return Color.clear
            case .pass:
                return .appSuccessSurfaceSubtle
            case .warning:
                return .appPrimarySurface
            case .fail:
                return .appRiskSurface
            }
        }
    }

    var primaryStatus: ResultStatus {
        if sections.contains(where: { $0.items.contains(where: { $0.status == .fail }) }) {
            return .fail
        }
        if sections.contains(where: { $0.items.contains(where: { $0.status == .warning }) }) {
            return .warning
        }
        if sections.contains(where: { $0.items.contains(where: { $0.status == .pass }) }) {
            return .pass
        }
        return .normal
    }

    static func item(
        _ label: String,
        _ value: String,
        status: ResultStatus = .normal
    ) -> ResultItem {
        ResultItem(label: label, value: value, status: status)
    }

    static func singleSection(
        headline: String,
        title: String = "明细",
        formula: String? = nil,
        items: [ResultItem]
    ) -> CalculationResult {
        CalculationResult(
            headline: headline,
            formula: formula,
            sections: [ResultSection(title: title, items: items)]
        )
    }

    static func error(_ message: String) -> CalculationResult {
        singleSection(
            headline: message,
            title: "错误",
            items: [item("提示", message, status: .fail)]
        )
    }
}

struct CalculatorResultCard: View {
    @Environment(DataStore.self) private var store

    let title: String
    let result: CalculationResult
    let copyText: String

    @State private var copied = false
    @State private var savedMessage: String?
    @State private var savedDestination: CalculatorSavedProjectDestination?
    @State private var activeDestination: CalculatorSavedProjectDestination?
    @State private var saveMessageToken = UUID()
    @State private var saveErrorMessage = ""
    @State private var showSaveError = false

    init(
        title: String,
        result: CalculationResult,
        copyText: String
    ) {
        self.title = title
        self.result = result
        self.copyText = copyText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            HStack(spacing: AppSpacing.tight) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
            }

            if let savedMessage {
                saveSuccessBanner(message: savedMessage)
            }

            if !result.headline.isEmpty {
                Text(result.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(result.primaryStatus.valueColor)
            }

            if let formula = result.formula, !formula.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Text("公式")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(formula)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }

            CalculatorResultSectionsView(sections: result.sections)

            resultActionBar
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(result.primaryStatus.cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(result.primaryStatus.cardStrokeColor, lineWidth: 1)
        )
        .alert("保存失败", isPresented: $showSaveError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .navigationDestination(item: $activeDestination) { destination in
            ProjectDetailView(
                projectId: destination.projectId,
                initialMode: destination.mode,
                focus: destination.focus
            )
        }
    }

    private var sortedProjects: [Project] {
        store.projects.sorted { lhs, rhs in
            lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private var projectSaveMenuContent: some View {
        if sortedProjects.isEmpty {
            Button("暂无项目") {}
                .disabled(true)
        } else {
            Menu("保存到项目资料") {
                ForEach(sortedProjects) { project in
                    Button(project.name) {
                        saveResultToProjectDocument(project)
                    }
                }
            }
            Menu("保存到随手记") {
                ForEach(sortedProjects) { project in
                    Button(project.name) {
                        saveResultToQuickNote(project)
                    }
                }
            }
            Menu("保存到施工日志") {
                ForEach(sortedProjects) { project in
                    Button(project.name) {
                        saveResultToDailyLog(project)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultActionBar: some View {
        Divider()
            .overlay(Color.appStrokeSecondary.opacity(0.6))

        HStack(spacing: AppSpacing.tight) {
            Menu {
                projectSaveMenuContent
            } label: {
                Label("保存到项目", systemImage: "folder.badge.plus")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appPrimaryAction)
            .disabled(store.projects.isEmpty || copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("保存到项目")
            .accessibilityHint("将计算结果写入项目资料、随手记或施工日志")

            Button {
                copyToClipboard()
            } label: {
                Label(copied ? "已复制" : "复制结果", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(copied ? Color.appSuccess : Color.appPrimaryAction)
            .accessibilityLabel(copied ? "已复制结果" : "复制结果")
            .accessibilityHint("将计算结果复制到剪贴板")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func saveSuccessBanner(message: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.appSuccess)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let destination = savedDestination {
                Button(destination.actionTitle) {
                    activeDestination = destination
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Color.appSuccess)
                .accessibilityHint("打开保存结果所在的项目页面")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appSuccessSurfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appStrokeSuccess, lineWidth: 1)
        )
        .transition(.opacity)
    }

    @MainActor
    private func copyToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = copyText
        AppHaptics.success()
        #endif
        withAnimation(.easeOut(duration: 0.18)) {
            copied = true
        }
        Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(1.2)) else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }

    @MainActor
    private func saveResultToProjectDocument(_ project: Project) {
        let note = "来源：计算器「\(title)」结果"
        let generatedTitle = "\(title)-\(Formatters.date.string(from: Date()))"
        let payload = Data(copyText.utf8)
        switch ProjectDetailFinanceDocumentActions.importAttachmentDocumentData(
            payload,
            fileExtension: "txt",
            title: generatedTitle,
            category: .other,
            note: note,
            projectId: project.id,
            linkedFinancialRecordId: nil,
            store: store
        ) {
        case .success(let document):
            presentSaveSuccess(
                "已保存到 \(project.name) 的项目资料",
                destination: CalculatorSavedProjectDestination(
                    projectId: project.id,
                    mode: .assets,
                    focus: .document(document.id),
                    actionTitle: "打开资料"
                )
            )
        case .failure(let message):
            presentSaveError(message)
            return
        }
    }

    @MainActor
    private func saveResultToQuickNote(_ project: Project) {
        let timestamp = Formatters.now()
        let note = QuickNote(
            title: "\(title) 计算结果",
            content: copyText,
            projectId: project.id,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        store.quickNotes.insert(note, at: 0)
        store.scheduleSave()
        presentSaveSuccess(
            "已保存到 \(project.name) 的随手记",
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .timeline,
                focus: nil,
                actionTitle: "打开项目"
            )
        )
    }

    @MainActor
    private func saveResultToDailyLog(_ project: Project) {
        let today = Formatters.date.string(from: Date())
        let block = """
        【计算结果】\(title)
        \(copyText)
        """
        if let existingIndex = store.dailyLogs.firstIndex(where: { $0.projectId == project.id && $0.date == today }) {
            let current = store.dailyLogs[existingIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
            store.dailyLogs[existingIndex].content = current.isEmpty ? block : "\(current)\n\n\(block)"
        } else {
            store.dailyLogs.insert(
                DailyLog(
                    date: today,
                    weather: autoWeatherNow(),
                    content: block,
                    workers: "0",
                    projectId: project.id
                ),
                at: 0
            )
        }
        store.scheduleSave()
        presentSaveSuccess(
            "已保存到 \(project.name) 的施工日志",
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .records,
                focus: nil,
                actionTitle: "打开现场"
            )
        )
    }

    @MainActor
    private func presentSaveSuccess(_ message: String, destination: CalculatorSavedProjectDestination) {
        AppHaptics.success()
        let token = UUID()
        saveMessageToken = token
        withAnimation(.easeOut(duration: 0.18)) {
            savedMessage = message
            savedDestination = destination
        }
        Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(4)) else { return }
            guard saveMessageToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                savedMessage = nil
                savedDestination = nil
            }
        }
    }

    @MainActor
    private func presentSaveError(_ message: String) {
        saveErrorMessage = message
        showSaveError = true
        AppHaptics.error()
    }

}

private struct CalculatorResultSectionsView: View {
    let sections: [CalculationResult.ResultSection]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                CalculatorResultSectionView(section: section)
            }
        }
    }
}

private struct CalculatorResultSectionView: View {
    let section: CalculationResult.ResultSection

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            if !section.title.isEmpty {
                Text(section.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    CalculatorResultItemRow(item: item)
                }
            }
        }
    }
}

private struct CalculatorResultItemRow: View {
    let item: CalculationResult.ResultItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
            Text(item.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if item.status != .normal {
                    Circle()
                        .fill(item.status.valueColor)
                        .frame(width: 6, height: 6)
                }
                Text(item.value)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(item.status.valueColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.status.rowBackgroundColor)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label)，\(item.value)")
        .accessibilityValue(accessibilityStatus(item.status))
    }

    private func accessibilityStatus(_ status: CalculationResult.ResultStatus) -> String {
        switch status {
        case .normal:
            return "普通结果"
        case .pass:
            return "通过"
        case .warning:
            return "关注"
        case .fail:
            return "不通过"
        }
    }
}

private struct CalculatorSavedProjectDestination: Identifiable, Hashable {
    let id = UUID()
    let projectId: UUID
    let mode: ProjectDetailMode
    let focus: ProjectDetailFocus?
    let actionTitle: String

    static func == (lhs: CalculatorSavedProjectDestination, rhs: CalculatorSavedProjectDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private extension CalculationResult.ResultStatus {
    var cardBackgroundColor: Color {
        switch self {
        case .normal:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .pass:
            return .appSuccessSurfaceSubtle
        case .warning:
            return .appPrimarySurface
        case .fail:
            return .appRiskSurface
        }
    }

    var cardStrokeColor: Color {
        switch self {
        case .normal:
            return .appStrokeSecondary
        case .pass:
            return .appStrokeSuccess
        case .warning:
            return .appStrokeWarning
        case .fail:
            return .appStrokeError
        }
    }
}
