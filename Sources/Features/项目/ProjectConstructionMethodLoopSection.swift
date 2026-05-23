import Foundation
import SwiftUI

struct ProjectConstructionMethodLoopSectionView: View {
    @Environment(DataStore.self) private var store

    let project: Project
    let progressTasks: [ProgressTask]
    let methods: [ConstructionMethod]
    let openTodoCount: Int

    @State private var stage: ProjectDocumentRecommendationStage
    @State private var tradeFilter: String = Self.allTradesToken
    @State private var selectedMethodIDs: Set<UUID> = []
    @State private var onlyPublished = true
    @State private var operationNotice: OperationToastNotice?

    private static let allTradesToken = "__all_construction_method_trades__"

    init(
        project: Project,
        progressTasks: [ProgressTask],
        methods: [ConstructionMethod],
        openTodoCount: Int
    ) {
        self.project = project
        self.progressTasks = progressTasks
        self.methods = methods
        self.openTodoCount = openTodoCount
        _stage = State(initialValue: ProjectDocumentCategory.recommendedStage(for: project, progressTasks: progressTasks))
    }

    var body: some View {
        Section(String(localized: "工艺闭环")) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "按项目阶段和专业推荐工艺，并生成执行闭环。"))
                        .font(.footnote)
                    Text(generationPreviewText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker(String(localized: "阶段"), selection: $stage) {
                ForEach(ProjectDocumentRecommendationStage.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker(String(localized: "专业"), selection: $tradeFilter) {
                ForEach(tradeOptions, id: \.self) { trade in
                    Text(tradeDisplayName(trade)).tag(trade)
                }
            }

            Toggle(String(localized: "仅显示已发布工艺"), isOn: $onlyPublished)

            if recommendedMethods.isEmpty {
                ProjectInlineEmptyState(
                    String(localized: "当前筛选没有匹配工艺"),
                    systemImage: "square.stack.3d.down.right.slash",
                    detail: String(localized: "可先去施工工艺库导入/新建，再回来一键生成闭环。")
                )
            } else {
                ForEach(recommendedMethods.prefix(12)) { method in
                    Button {
                        toggleMethodSelection(method.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(methodDisplayTitle(method))
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 8) {
                                    Text(method.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未分类") : method.trade)
                                    Text(method.versionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "V1" : method.versionName)
                                    Text(method.publishStatus.displayName)
                                        .foregroundStyle(method.publishStatus == .published ? Color.appSuccess : Color.appWarning)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                                Text(recommendReason(method))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            Image(systemName: selectedMethodIDs.contains(method.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedMethodIDs.contains(method.id) ? Color.appSuccess : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if !recommendedMethods.isEmpty {
                HStack {
                    Button(String(localized: "全选推荐")) {
                        selectedMethodIDs = Set(recommendedMethods.map(\.id))
                    }
                    Button(String(localized: "清空")) {
                        selectedMethodIDs.removeAll()
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: String(localized: "已选 %lld 条"), Int64(selectedMethods.count)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: generateLoopBundle) {
                    Label(String(localized: "一键生成待办、质检清单、交底资料"), systemImage: "bolt.fill")
                }
                .buttonStyle(.appProminent())
                .disabled(selectedMethods.isEmpty)
            }
        }
        .operationToast(notice: $operationNotice)
        .onAppear {
            seedSelectionIfNeeded()
        }
        .onChange(of: stage) { _, _ in
            syncSelection(resetWhenEmpty: true)
        }
        .onChange(of: tradeFilter) { _, _ in
            syncSelection(resetWhenEmpty: true)
        }
        .onChange(of: onlyPublished) { _, _ in
            syncSelection(resetWhenEmpty: true)
        }
    }

    private var selectedMethods: [ConstructionMethod] {
        recommendedMethods.filter { selectedMethodIDs.contains($0.id) }
    }

    private var generationPreviewText: String {
        let openTodoText = String(format: String(localized: "当前未完成待办 %lld 条"), Int64(openTodoCount))
        if selectedMethods.isEmpty {
            return "\(openTodoText) · \(String(localized: "请选择工艺后生成"))"
        }
        return String(
            format: String(localized: "将生成 %1$lld 条待办 + 2 份资料（%@）"),
            Int64(selectedMethods.count),
            openTodoText
        )
    }

    private var tradeOptions: [String] {
        let values = Set(methods.map { normalizeText($0.trade) }.filter { !$0.isEmpty })
        return [Self.allTradesToken] + values.sorted()
    }

    private var recommendedMethods: [ConstructionMethod] {
        let candidates = filteredMethods
        let scored = candidates.map { MethodScore(method: $0, score: score(for: $0)) }
        let hasMatchedStageKeywords = scored.contains(where: { $0.score > 0 })
        let visibleScores = hasMatchedStageKeywords ? scored.filter { $0.score > 0 } : scored
        return visibleScores
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.method.publishStatus != rhs.method.publishStatus {
                    return lhs.method.publishStatus == .published
                }
                return methodDisplayTitle(lhs.method)
                    .localizedStandardCompare(methodDisplayTitle(rhs.method)) == .orderedAscending
            }
            .map(\.method)
    }

    private var filteredMethods: [ConstructionMethod] {
        methods.filter { method in
            guard method.publishStatus != .deprecated else { return false }
            if onlyPublished && method.publishStatus != .published {
                return false
            }
            if tradeFilter == Self.allTradesToken {
                return true
            }
            let trade = normalizeText(method.trade)
            return trade.isEmpty || trade == tradeFilter
        }
    }

    private func seedSelectionIfNeeded() {
        guard selectedMethodIDs.isEmpty else { return }
        selectedMethodIDs = Set(recommendedMethods.prefix(4).map(\.id))
    }

    private func syncSelection(resetWhenEmpty: Bool) {
        let visibleIDs = Set(recommendedMethods.map(\.id))
        selectedMethodIDs = selectedMethodIDs.intersection(visibleIDs)
        if resetWhenEmpty, selectedMethodIDs.isEmpty {
            selectedMethodIDs = Set(recommendedMethods.prefix(4).map(\.id))
        }
    }

    private func toggleMethodSelection(_ id: UUID) {
        if selectedMethodIDs.contains(id) {
            selectedMethodIDs.remove(id)
        } else {
            selectedMethodIDs.insert(id)
        }
    }

    private func score(for method: ConstructionMethod) -> Int {
        let corpus = recommendationCorpus(for: method)
        let keywordScore = stageKeywords(for: stage).reduce(into: 0) { total, token in
            if corpus.contains(token) {
                total += 2
            }
        }
        let detailScore = [
            method.procedureSteps.isEmpty ? 0 : 1,
            method.qualityChecklist.isEmpty ? 0 : 1,
            method.safetyChecklist.isEmpty ? 0 : 1
        ].reduce(0, +)
        let statusScore = method.publishStatus == .published ? 1 : 0
        return keywordScore + detailScore + statusScore
    }

    private func recommendationCorpus(for method: ConstructionMethod) -> String {
        [
            method.title,
            method.trade,
            method.tutorialBody,
            method.procedureSteps.joined(separator: " "),
            method.qualityChecklist.joined(separator: " "),
            method.safetyChecklist.joined(separator: " ")
        ]
        .joined(separator: "\n")
        .lowercased()
    }

    private func recommendReason(_ method: ConstructionMethod) -> String {
        let scoreValue = score(for: method)
        if scoreValue > 0 {
            return String(format: String(localized: "%@阶段匹配度 %lld"), stage.displayName, Int64(scoreValue))
        }
        return String(localized: "基础推荐（可手动勾选后生成闭环）")
    }

    private func stageKeywords(for stage: ProjectDocumentRecommendationStage) -> [String] {
        switch stage {
        case .preConstruction:
            return ["开工", "准备", "交底", "样板", "放线", "方案", "技术"]
        case .construction:
            return ["施工", "安装", "浇筑", "砌筑", "防水", "抹灰", "巡检", "隐蔽"]
        case .acceptance:
            return ["验收", "调试", "检测", "竣工", "复核", "整改", "归档", "移交"]
        }
    }

    @MainActor
    private func generateLoopBundle() {
        let methodsToGenerate = selectedMethods
        guard !methodsToGenerate.isEmpty else {
            operationNotice = .info(String(localized: "请先选择至少一条工艺"))
            return
        }

        let todos = makeTodos(from: methodsToGenerate)
        if !todos.isEmpty {
            store.replaceSiteTodos(todos + store.siteTodos)
        }

        do {
            let documents = try makeGeneratedDocuments(from: methodsToGenerate)
            if !documents.isEmpty {
                store.appendProjectDocuments(documents)
            }
            store.scheduleSave()
            AppHaptics.success()
            operationNotice = .info(
                String(
                    format: String(localized: "已生成 %1$lld 条待办、%2$lld 份资料"),
                    Int64(todos.count),
                    Int64(documents.count)
                )
            )
        } catch {
            AppHaptics.error()
            operationNotice = .info(String(format: String(localized: "生成失败：%@"), error.localizedDescription))
        }
    }

    private func makeTodos(from methods: [ConstructionMethod]) -> [SiteTodo] {
        let dueDate = recommendedDueDate(for: stage)
        return methods.map { method in
            let titlePrefix = stage == .acceptance ? String(localized: "验收复核") : String(localized: "工艺执行检查")
            let checkItems = method.qualityChecklist.isEmpty
                ? [String(localized: "现场核对关键工序执行情况")]
                : method.qualityChecklist
            let note = [
                String(format: String(localized: "阶段：%@"), stage.displayName),
                String(format: String(localized: "工艺：%@"), methodDisplayTitle(method)),
                String(localized: "质量检查："),
                numberedLines(checkItems)
            ]
            .joined(separator: "\n")
            return SiteTodo(
                title: "\(titlePrefix)：\(methodDisplayTitle(method))",
                owner: project.managerName,
                dueDate: dueDate,
                priority: stage == .acceptance ? .high : .medium,
                issueType: .quality,
                note: note,
                linkedConstructionMethodIDs: [method.id],
                projectId: project.id
            )
        }
    }

    private func makeGeneratedDocuments(from methods: [ConstructionMethod]) throws -> [ProjectDocument] {
        let now = Date()
        let dateText = Formatters.date.string(from: now)
        let createdAt = Formatters.now()
        let selectedMethodIDs = methods.map(\.id)
        let tradeName = tradeDisplayName(tradeFilter)
        let workSection = tradeFilter == Self.allTradesToken ? "" : tradeFilter
        let owner = normalizeText(project.managerName)
        let responsible = owner.isEmpty ? String(localized: "现场操作") : owner

        let checklistFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data(qualityChecklistDocumentText(methods, generatedAt: createdAt).utf8),
            projectId: project.id,
            fileExtension: "txt"
        )
        let handoverFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data(handoverDocumentText(methods, generatedAt: createdAt).utf8),
            projectId: project.id,
            fileExtension: "txt"
        )

        let checklistDocument = ProjectDocument(
            projectId: project.id,
            title: "\(stage.displayName)-\(tradeName)-质检清单-\(dateText)",
            category: .constructionRecord,
            fileName: checklistFileName,
            fileType: "txt",
            pageCount: 1,
            linkedConstructionMethodIDs: selectedMethodIDs,
            submissionStatus: .pending,
            responsiblePerson: responsible,
            formedAt: dateText,
            workSection: workSection,
            createdAt: createdAt,
            note: String(localized: "由工艺闭环自动生成：质检清单")
        )

        let handoverDocument = ProjectDocument(
            projectId: project.id,
            title: "\(stage.displayName)-\(tradeName)-工艺交底-\(dateText)",
            category: .constructionTechnical,
            fileName: handoverFileName,
            fileType: "txt",
            pageCount: 1,
            linkedConstructionMethodIDs: selectedMethodIDs,
            submissionStatus: .pending,
            responsiblePerson: responsible,
            formedAt: dateText,
            workSection: workSection,
            createdAt: createdAt,
            note: String(localized: "由工艺闭环自动生成：交底资料")
        )

        return [checklistDocument, handoverDocument]
    }

    private func qualityChecklistDocumentText(_ methods: [ConstructionMethod], generatedAt: String) -> String {
        var lines: [String] = [
            "工艺质检清单",
            "项目：\(project.name)",
            "阶段：\(stage.displayName)",
            "专业：\(tradeDisplayName(tradeFilter))",
            "生成时间：\(generatedAt)",
            ""
        ]
        for (index, method) in methods.enumerated() {
            lines.append("\(index + 1). \(methodDisplayTitle(method))")
            let checkItems = method.qualityChecklist.isEmpty
                ? [String(localized: "现场核对关键工序执行情况")]
                : method.qualityChecklist
            for item in checkItems {
                lines.append("   [ ] \(item)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func handoverDocumentText(_ methods: [ConstructionMethod], generatedAt: String) -> String {
        var lines: [String] = [
            "工艺交底资料",
            "项目：\(project.name)",
            "阶段：\(stage.displayName)",
            "专业：\(tradeDisplayName(tradeFilter))",
            "生成时间：\(generatedAt)",
            ""
        ]
        for (index, method) in methods.enumerated() {
            lines.append("\(index + 1). \(methodDisplayTitle(method))")
            let trade = normalizeText(method.trade)
            if !trade.isEmpty {
                lines.append("   专业：\(trade)")
            }
            let version = normalizeText(method.versionName)
            lines.append("   版本：\(version.isEmpty ? "V1" : version)")
            if !method.procedureSteps.isEmpty {
                lines.append("   施工步骤：")
                for item in method.procedureSteps {
                    lines.append("   - \(item)")
                }
            }
            if !method.qualityChecklist.isEmpty {
                lines.append("   质量要点：")
                for item in method.qualityChecklist {
                    lines.append("   - \(item)")
                }
            }
            if !method.safetyChecklist.isEmpty {
                lines.append("   安全注意：")
                for item in method.safetyChecklist {
                    lines.append("   - \(item)")
                }
            }
            let tutorial = normalizeText(method.tutorialBody)
            if !tutorial.isEmpty {
                lines.append("   教程说明：\(tutorial)")
            }
            let sourceURL = normalizeText(method.sourceURL)
            if !sourceURL.isEmpty {
                lines.append("   来源：\(sourceURL)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func recommendedDueDate(for stage: ProjectDocumentRecommendationStage) -> String {
        let offset: Int
        switch stage {
        case .preConstruction:
            offset = 1
        case .construction:
            offset = 0
        case .acceptance:
            offset = 2
        }
        let due = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        return Formatters.date.string(from: due)
    }

    private func tradeDisplayName(_ trade: String) -> String {
        trade == Self.allTradesToken ? String(localized: "全部专业") : trade
    }

    private func normalizeText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MethodScore {
    let method: ConstructionMethod
    let score: Int
}
