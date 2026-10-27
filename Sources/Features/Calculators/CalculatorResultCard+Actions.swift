import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension CalculatorResultCard {
    @MainActor
    func requestProjectDraft(_ kind: CalculatorProjectDraftRequest.Kind, project: Project) {
        pendingProjectDraft = CalculatorProjectDraftRequest(kind: kind, projectId: project.id)
    }

    @MainActor
    func confirmProjectDraft(_ request: CalculatorProjectDraftRequest) {
        let outcome = CalculatorProjectDraftCommitter.commit(
            request, pending: &pendingProjectDraft, title: title, copyText: copyText, store: store
        )
        switch outcome {
        case .ignored:
            return
        case .missingProject:
            selectedProjectId = nil
            presentSaveError(calculatorLoc("已选择的工程已不存在，请重新选择。"))
        case .saved(let project):
            let message = request.kind == .materialSheet
                ? calculatorLocFormat("已加入 %@ 的材料单", project.name)
                : calculatorLocFormat("已生成 %@ 的报价项", project.name)
            presentSaveSuccess(
                message,
                destination: CalculatorSavedProjectDestination(
                    projectId: project.id, mode: .finance, focus: nil, actionTitle: calculatorLoc("打开成本")
                )
            )
        }
    }

    @MainActor
    func copyToClipboard() {
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
    func saveResultToProjectDocument(_ project: Project) {
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
    func saveResultToQuickNote(_ project: Project) {
        let timestamp = Formatters.now()
        let note = QuickNote(
            title: calculatorLocFormat("%@ 计算结果", title),
            content: copyText,
            projectId: project.id,
            createdAt: BusinessDateValue(legacyText: timestamp),
            updatedAt: BusinessDateValue(legacyText: timestamp)
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
    func saveResultToHistory() {
        guard !savedToHistory, result.primaryStatus != .fail else { return }
        appendHistory(projectId: nil)
        savedToHistory = true
        AppHaptics.success()
    }

    @MainActor
    private func appendHistory(projectId: UUID?) {
        store.appendCalculationHistory(
            tool: result.historyDraft?.tool ?? title,
            input: result.historyDraft?.input ?? calculatorLoc("来自结果卡片"),
            result: projectId == nil ? (result.historyDraft?.result ?? copyText) : copyText,
            projectId: projectId
        )
    }

    @MainActor
    func saveResultToProjectHistory(_ project: Project) {
        appendHistory(projectId: project.id)
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
    func saveResultToDailyLog(_ project: Project) {
        let today = CalendarDay(date: Date())
        let block = CalculatorPlainTextExport.dailyLogBlock(title: title, copyText: copyText)
        if let existingIndex = store.dailyLogs.firstIndex(where: { $0.projectId == project.id && $0.date.calendarDay() == today }) {
            var existing = store.dailyLogs[existingIndex]
            let current = existing.content.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.content = current.isEmpty ? block : "\(current)\n\n\(block)"
            store.updateDailyLog(existing)
        } else {
            store.insertDailyLogAtTop(
                DailyLog(
                    date: .day(today),
                    weather: "",
                    content: block,
                    workers: NumericInputSupport.quantity("0"),
                    projectId: project.id
                )
            )
        }
        store.scheduleSave()
        presentSaveSuccess(
            calculatorLocFormat("已保存到 %@ 的施工日志", project.name) + (store.dailyLogs.first(where: { $0.projectId == project.id && $0.date.calendarDay() == today })?.weather.isEmpty == true ? " · " + calculatorLoc("天气待填写") : ""),
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

// One consumed confirmation owns one write. The view and tests use the same path.
@MainActor
enum CalculatorProjectDraftCommitter {
    enum Outcome {
        case ignored
        case missingProject
        case saved(Project)
    }

    static func commit(
        _ request: CalculatorProjectDraftRequest,
        pending: inout CalculatorProjectDraftRequest?,
        title: String,
        copyText: String,
        store: DataStore
    ) -> Outcome {
        guard pending?.id == request.id else { return .ignored }
        pending = nil
        guard let project = store.projects.first(where: { $0.id == request.projectId }) else {
            return .missingProject
        }
        switch request.kind {
        case .materialSheet:
            let now = Formatters.now()
            store.insertMaterialSheetDraftAtTop(MaterialSheetDraft(
                title: calculatorLocFormat("%@ 计算结果材料单", title),
                projectId: project.id,
                exportProjectName: project.name,
                items: [MaterialSheetDraftItem(
                    name: title, unit: calculatorLoc("项"),
                    quantity: NumericInputSupport.quantity("1"), note: copyText
                )],
                createdAt: BusinessDateValue(legacyText: now),
                updatedAt: BusinessDateValue(legacyText: now)
            ))
        case .quoteItem:
            store.appendQuoteItem(QuoteItem(
                name: title, unitPrice: NumericInputSupport.money(""),
                quantity: NumericInputSupport.quantity("1"), unit: calculatorLoc("项"), notes: copyText,
                taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("0"),
                projectId: project.id
            ))
        }
        store.scheduleSave()
        return .saved(project)
    }
}
