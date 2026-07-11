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
                ProjectConstructionMethodLoopEmptyStateView()
            } else {
                recommendedMethodRows
            }

            if !recommendedMethods.isEmpty {
                selectionControls

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
}

private extension ProjectConstructionMethodLoopSectionView {
    var selectedMethods: [ConstructionMethod] {
        recommendedMethods.filter { selectedMethodIDs.contains($0.id) }
    }

    var generationPreviewText: String {
        ProjectConstructionMethodLoopRecommendationSupport.generationPreviewText(
            openTodoCount: openTodoCount,
            selectedMethodCount: selectedMethods.count
        )
    }

    var tradeOptions: [String] {
        ProjectConstructionMethodLoopRecommendationSupport.tradeOptions(
            methods: methods,
            allTradesToken: Self.allTradesToken
        )
    }

    var recommendedMethods: [ConstructionMethod] {
        ProjectConstructionMethodLoopRecommendationSupport.recommendedMethods(
            methods: methods,
            stage: stage,
            tradeFilter: tradeFilter,
            onlyPublished: onlyPublished,
            allTradesToken: Self.allTradesToken
        )
    }

    var recommendedMethodRows: some View {
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
                            Text(
                                ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.trade).isEmpty
                                    ? String(localized: "未分类")
                                    : method.trade
                            )
                            Text(
                                ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.versionName).isEmpty
                                    ? "V1"
                                    : method.versionName
                            )
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

    var selectionControls: some View {
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
    }

    func seedSelectionIfNeeded() {
        guard selectedMethodIDs.isEmpty else { return }
        selectedMethodIDs = Set(recommendedMethods.prefix(4).map(\.id))
    }

    func syncSelection(resetWhenEmpty: Bool) {
        let visibleIDs = Set(recommendedMethods.map(\.id))
        selectedMethodIDs = selectedMethodIDs.intersection(visibleIDs)
        if resetWhenEmpty, selectedMethodIDs.isEmpty {
            selectedMethodIDs = Set(recommendedMethods.prefix(4).map(\.id))
        }
    }

    func toggleMethodSelection(_ id: UUID) {
        if selectedMethodIDs.contains(id) {
            selectedMethodIDs.remove(id)
        } else {
            selectedMethodIDs.insert(id)
        }
    }

    func recommendReason(_ method: ConstructionMethod) -> String {
        ProjectConstructionMethodLoopRecommendationSupport.recommendReason(
            for: method,
            stage: stage
        )
    }

    @MainActor
    func generateLoopBundle() {
        let methodsToGenerate = selectedMethods
        guard !methodsToGenerate.isEmpty else {
            operationNotice = .info(String(localized: "请先选择至少一条工艺"))
            return
        }

        let todos = ProjectConstructionMethodLoopTaskBuilder.makeTodos(
            from: methodsToGenerate,
            stage: stage,
            project: project
        )
        if !todos.isEmpty {
            store.replaceSiteTodos(todos + store.siteTodos)
        }

        do {
            let documents = try ProjectConstructionMethodLoopChecklistBuilder.makeGeneratedDocuments(
                from: methodsToGenerate,
                stage: stage,
                project: project,
                tradeFilter: tradeFilter,
                allTradesToken: Self.allTradesToken
            )
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

    func tradeDisplayName(_ trade: String) -> String {
        ProjectConstructionMethodLoopRecommendationSupport.tradeDisplayName(
            trade,
            allTradesToken: Self.allTradesToken
        )
    }
}
