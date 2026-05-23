import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CalculatorResultCard: View {
    @Environment(DataStore.self) private var store

    let title: String
    let result: CalculationResult
    let copyText: String

    @State private var copied = false
    @State private var savedMessage: String?
    @State private var savedDestination: CalculatorSavedProjectDestination?
    @State private var activeDestination: CalculatorSavedProjectDestination?
    @State private var selectedProjectId: UUID?
    @State private var saveMessageToken = UUID()
    @State private var saveErrorMessage = ""
    @State private var showSaveError = false

    init(
        title: String,
        result: CalculationResult,
        copyText: String? = nil
    ) {
        self.title = title
        self.result = result
        self.copyText = copyText ?? result.plainText(title: title)
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
                    Text(calculatorLoc("公式"))
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
        .alert(calculatorLoc("保存失败"), isPresented: $showSaveError) {
            Button(calculatorLoc("知道了"), role: .cancel) {}
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

    private var selectedProject: Project? {
        if let selectedProjectId,
           let project = store.projects.first(where: { $0.id == selectedProjectId }) {
            return project
        }
        return sortedProjects.first
    }

    private var canUseProjectWorkflow: Bool {
        selectedProject != nil && !copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var additionalSaveMenuContent: some View {
        if sortedProjects.isEmpty {
            Button(calculatorLoc("暂无项目")) {}
                .disabled(true)
        } else if let selectedProject {
            Button {
                saveResultToProjectDocument(selectedProject)
            } label: {
                Label(calculatorLoc("保存到项目资料"), systemImage: "doc.badge.plus")
            }
            Button {
                saveResultToQuickNote(selectedProject)
            } label: {
                Label(calculatorLoc("保存到随手记"), systemImage: "note.text")
            }
        } else {
            Button(calculatorLoc("请选择项目")) {}
                .disabled(true)
        }
    }

    @ViewBuilder
    private var projectPickerMenu: some View {
        if sortedProjects.isEmpty {
            Label(calculatorLoc("暂无项目"), systemImage: "building.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Menu {
                ForEach(sortedProjects) { project in
                    Button {
                        selectedProjectId = project.id
                    } label: {
                        if project.id == selectedProject?.id {
                            Label(project.name, systemImage: "checkmark")
                        } else {
                            Text(project.name)
                        }
                    }
                }
            } label: {
                Label(selectedProject?.name ?? calculatorLoc("选择项目"), systemImage: "building.2")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .accessibilityLabel(calculatorLoc("选择项目"))
        }
    }

    @ViewBuilder
    private var resultActionBar: some View {
        Divider()
            .overlay(Color.appStrokeSecondary.opacity(0.6))

        businessWorkflowPanel

        Divider()
            .overlay(Color.appStrokeSecondary.opacity(0.45))

        HStack(spacing: AppSpacing.tight) {
            Button {
                copyToClipboard()
            } label: {
                Label(copied ? calculatorLoc("已复制") : calculatorLoc("复制结果"), systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(copied ? Color.appSuccess : Color.appPrimaryAction)
            .accessibilityLabel(copied ? calculatorLoc("已复制结果") : calculatorLoc("复制结果"))
            .accessibilityHint(calculatorLoc("将计算结果复制到剪贴板"))

            Menu {
                additionalSaveMenuContent
            } label: {
                Label(calculatorLoc("更多保存"), systemImage: "ellipsis.circle")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canUseProjectWorkflow)
            .accessibilityLabel(calculatorLoc("更多保存"))
            .accessibilityHint(calculatorLoc("保存到项目资料或随手记"))
        }
        .controlSize(.small)
    }

    private var businessWorkflowPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(spacing: AppSpacing.tight) {
                Label(calculatorLoc("项目工作流"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                projectPickerMenu
            }

            if sortedProjects.isEmpty {
                Text(calculatorLoc("先创建项目后，可把结果写入材料、报价、日志和历史。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.tight),
                    GridItem(.flexible(), spacing: AppSpacing.tight)
                ],
                alignment: .leading,
                spacing: AppSpacing.tight
            ) {
                workflowActionButton(
                    title: calculatorLoc("加入材料单"),
                    systemImage: "list.bullet.rectangle",
                    accessibilityHint: calculatorLoc("将结果加入当前项目的材料单")
                ) {
                    guard let selectedProject else { return }
                    saveResultToMaterialSheet(selectedProject)
                }
                workflowActionButton(
                    title: calculatorLoc("生成报价项"),
                    systemImage: "doc.text.fill",
                    accessibilityHint: calculatorLoc("将结果生成当前项目的报价项")
                ) {
                    guard let selectedProject else { return }
                    saveResultToQuoteItem(selectedProject)
                }
                workflowActionButton(
                    title: calculatorLoc("写入施工日志"),
                    systemImage: "text.badge.plus",
                    accessibilityHint: calculatorLoc("将结果写入当前项目的施工日志")
                ) {
                    guard let selectedProject else { return }
                    saveResultToDailyLog(selectedProject)
                }
                workflowActionButton(
                    title: calculatorLoc("绑定项目"),
                    systemImage: "link",
                    accessibilityHint: calculatorLoc("将结果绑定到当前项目的计算历史")
                ) {
                    guard let selectedProject else { return }
                    saveResultToProjectHistory(selectedProject)
                }
            }
            .controlSize(.small)
        }
    }

    private func workflowActionButton(
        title: String,
        systemImage: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(Color.appPrimaryAction)
        .disabled(!canUseProjectWorkflow)
        .accessibilityHint(accessibilityHint)
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
                .accessibilityHint(calculatorLoc("打开保存结果所在的项目页面"))
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
        let note = calculatorLocFormat("来源：计算器「%@」结果", title)
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
                calculatorLocFormat("已保存到 %@ 的项目资料", project.name),
                destination: CalculatorSavedProjectDestination(
                    projectId: project.id,
                    mode: .assets,
                    focus: .document(document.id),
                    actionTitle: calculatorLoc("打开资料")
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
            title: calculatorLocFormat("%@ 计算结果", title),
            content: copyText,
            projectId: project.id,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        store.insertQuickNoteAtTop(note)
        store.scheduleSave()
        presentSaveSuccess(
            calculatorLocFormat("已保存到 %@ 的随手记", project.name),
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .timeline,
                focus: nil,
                actionTitle: calculatorLoc("打开项目")
            )
        )
    }

    @MainActor
    private func saveResultToProjectHistory(_ project: Project) {
        store.appendCalculationHistory(
            tool: title,
            input: calculatorLoc("来自结果卡片"),
            result: copyText,
            projectId: project.id
        )
        presentSaveSuccess(
            calculatorLocFormat("已绑定到 %@ 的计算历史", project.name),
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .timeline,
                focus: nil,
                actionTitle: calculatorLoc("打开项目")
            )
        )
    }

    @MainActor
    private func saveResultToMaterialSheet(_ project: Project) {
        let now = Formatters.now()
        let draft = MaterialSheetDraft(
            title: calculatorLocFormat("%@ 计算结果材料单", title),
            projectId: project.id,
            exportProjectName: project.name,
            items: [
                MaterialSheetDraftItem(
                    name: title,
                    unit: calculatorLoc("项"),
                    quantity: "1",
                    note: copyText
                )
            ],
            createdAt: now,
            updatedAt: now
        )
        store.insertMaterialSheetDraftAtTop(draft)
        store.scheduleSave()
        presentSaveSuccess(
            calculatorLocFormat("已加入 %@ 的材料单", project.name),
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .finance,
                focus: nil,
                actionTitle: calculatorLoc("打开成本")
            )
        )
    }

    @MainActor
    private func saveResultToQuoteItem(_ project: Project) {
        let item = QuoteItem(
            name: title,
            unitPrice: "",
            quantity: "1",
            unit: calculatorLoc("项"),
            notes: copyText,
            taxRate: "0",
            discountRate: "0",
            projectId: project.id
        )
        store.appendQuoteItem(item)
        store.scheduleSave()
        presentSaveSuccess(
            calculatorLocFormat("已生成 %@ 的报价项", project.name),
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .finance,
                focus: nil,
                actionTitle: calculatorLoc("打开成本")
            )
        )
    }

    @MainActor
    private func saveResultToDailyLog(_ project: Project) {
        let today = Formatters.date.string(from: Date())
        let block = CalculatorPlainTextExport.dailyLogBlock(title: title, copyText: copyText)
        if let existingIndex = store.dailyLogs.firstIndex(where: { $0.projectId == project.id && $0.date == today }) {
            var existing = store.dailyLogs[existingIndex]
            let current = existing.content.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.content = current.isEmpty ? block : "\(current)\n\n\(block)"
            store.updateDailyLog(existing)
        } else {
            store.insertDailyLogAtTop(
                DailyLog(
                    date: today,
                    weather: autoWeatherNow(),
                    content: block,
                    workers: "0",
                    projectId: project.id
                )
            )
        }
        store.scheduleSave()
        presentSaveSuccess(
            calculatorLocFormat("已保存到 %@ 的施工日志", project.name),
            destination: CalculatorSavedProjectDestination(
                projectId: project.id,
                mode: .records,
                focus: nil,
                actionTitle: calculatorLoc("打开现场")
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
            ForEach(sections, id: \.id) { section in
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
                ForEach(section.items, id: \.id) { item in
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
        .accessibilityLabel(calculatorLocFormat("%@，%@", item.label, item.value))
        .accessibilityValue(accessibilityStatus(item.status))
    }

    private func accessibilityStatus(_ status: CalculationResult.ResultStatus) -> String {
        switch status {
        case .normal:
            return calculatorLoc("普通结果")
        case .pass:
            return calculatorLoc("通过")
        case .warning:
            return calculatorLoc("关注")
        case .fail:
            return calculatorLoc("不通过")
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
