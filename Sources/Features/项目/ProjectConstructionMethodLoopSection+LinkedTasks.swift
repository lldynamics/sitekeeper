import Foundation

enum ProjectConstructionMethodLoopTaskBuilder {
    static func makeTodos(
        from methods: [ConstructionMethod],
        stage: ProjectDocumentRecommendationStage,
        project: Project
    ) -> [SiteTodo] {
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

    private static func recommendedDueDate(for stage: ProjectDocumentRecommendationStage) -> String {
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
}
