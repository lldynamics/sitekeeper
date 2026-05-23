import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension CalculatorResultCard {
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
    func saveResultToProjectHistory(_ project: Project) {
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
    func saveResultToMaterialSheet(_ project: Project) {
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
    func saveResultToQuoteItem(_ project: Project) {
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
    func saveResultToDailyLog(_ project: Project) {
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
