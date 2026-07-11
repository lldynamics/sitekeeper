import Foundation

enum ProjectConstructionMethodLoopRecommendationSupport {
    static func generationPreviewText(openTodoCount: Int, selectedMethodCount: Int) -> String {
        let openTodoText = String(format: String(localized: "当前未完成待办 %lld 条"), Int64(openTodoCount))
        if selectedMethodCount == 0 {
            return "\(openTodoText) · \(String(localized: "请选择工艺后生成"))"
        }
        return String(
            format: String(localized: "将生成 %1$lld 条待办 + 2 份资料（%@）"),
            Int64(selectedMethodCount),
            openTodoText
        )
    }

    static func tradeOptions(methods: [ConstructionMethod], allTradesToken: String) -> [String] {
        let values = Set(methods.map { normalizeText($0.trade) }.filter { !$0.isEmpty })
        return [allTradesToken] + values.sorted()
    }

    static func tradeDisplayName(_ trade: String, allTradesToken: String) -> String {
        trade == allTradesToken ? String(localized: "全部专业") : trade
    }

    static func recommendedMethods(
        methods: [ConstructionMethod],
        stage: ProjectDocumentRecommendationStage,
        tradeFilter: String,
        onlyPublished: Bool,
        allTradesToken: String
    ) -> [ConstructionMethod] {
        let candidates = filteredMethods(
            methods: methods,
            tradeFilter: tradeFilter,
            onlyPublished: onlyPublished,
            allTradesToken: allTradesToken
        )
        let scored = candidates.map { ProjectConstructionMethodLoopMethodScore(method: $0, score: score(for: $0, stage: stage)) }
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

    static func recommendReason(for method: ConstructionMethod, stage: ProjectDocumentRecommendationStage) -> String {
        let scoreValue = score(for: method, stage: stage)
        if scoreValue > 0 {
            return String(format: String(localized: "%@阶段匹配度 %lld"), stage.displayName, Int64(scoreValue))
        }
        return String(localized: "基础推荐（可手动勾选后生成闭环）")
    }

    static func normalizeText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func filteredMethods(
        methods: [ConstructionMethod],
        tradeFilter: String,
        onlyPublished: Bool,
        allTradesToken: String
    ) -> [ConstructionMethod] {
        methods.filter { method in
            guard method.publishStatus != .deprecated else { return false }
            if onlyPublished && method.publishStatus != .published {
                return false
            }
            if tradeFilter == allTradesToken {
                return true
            }
            let trade = normalizeText(method.trade)
            return trade.isEmpty || trade == tradeFilter
        }
    }

    private static func score(for method: ConstructionMethod, stage: ProjectDocumentRecommendationStage) -> Int {
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

    private static func recommendationCorpus(for method: ConstructionMethod) -> String {
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

    private static func stageKeywords(for stage: ProjectDocumentRecommendationStage) -> [String] {
        switch stage {
        case .preConstruction:
            return ["开工", "准备", "交底", "样板", "放线", "方案", "技术"]
        case .construction:
            return ["施工", "安装", "浇筑", "砌筑", "防水", "抹灰", "巡检", "隐蔽"]
        case .acceptance:
            return ["验收", "调试", "检测", "竣工", "复核", "整改", "归档", "移交"]
        }
    }
}

private struct ProjectConstructionMethodLoopMethodScore {
    let method: ConstructionMethod
    let score: Int
}
