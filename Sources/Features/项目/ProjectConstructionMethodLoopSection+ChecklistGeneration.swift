import Foundation

enum ProjectConstructionMethodLoopChecklistBuilder {
    static func makeGeneratedDocuments(
        from methods: [ConstructionMethod],
        stage: ProjectDocumentRecommendationStage,
        project: Project,
        tradeFilter: String,
        allTradesToken: String
    ) throws -> [ProjectDocument] {
        let now = Date()
        let dateText = Formatters.date.string(from: now)
        let createdAt = Formatters.now()
        let selectedMethodIDs = methods.map(\.id)
        let tradeName = ProjectConstructionMethodLoopRecommendationSupport.tradeDisplayName(
            tradeFilter,
            allTradesToken: allTradesToken
        )
        let workSection = tradeFilter == allTradesToken ? "" : tradeFilter
        let owner = ProjectConstructionMethodLoopRecommendationSupport.normalizeText(project.managerName)
        let responsible = owner.isEmpty ? String(localized: "现场操作") : owner

        let checklistFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data(qualityChecklistDocumentText(methods, generatedAt: createdAt, stage: stage, project: project, tradeFilter: tradeFilter, allTradesToken: allTradesToken).utf8),
            projectId: project.id,
            fileExtension: "txt"
        )
        let handoverFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data(handoverDocumentText(methods, generatedAt: createdAt, stage: stage, project: project, tradeFilter: tradeFilter, allTradesToken: allTradesToken).utf8),
            projectId: project.id,
            fileExtension: "txt"
        )

        let checklistDocument = ProjectDocument(
            projectId: project.id,
            title: String(
                format: String(localized: "construction_method_loop_quality_checklist_document_title_format"),
                stage.displayName,
                tradeName,
                dateText
            ),
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
            note: String(localized: "construction_method_loop_quality_checklist_note")
        )

        let handoverDocument = ProjectDocument(
            projectId: project.id,
            title: String(
                format: String(localized: "construction_method_loop_handover_document_title_format"),
                stage.displayName,
                tradeName,
                dateText
            ),
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
            note: String(localized: "construction_method_loop_handover_note")
        )

        return [checklistDocument, handoverDocument]
    }

    private static func qualityChecklistDocumentText(
        _ methods: [ConstructionMethod],
        generatedAt: String,
        stage: ProjectDocumentRecommendationStage,
        project: Project,
        tradeFilter: String,
        allTradesToken: String
    ) -> String {
        var lines: [String] = [
            String(localized: "construction_method_loop_quality_checklist_heading"),
            String(format: String(localized: "construction_method_loop_document_project_format"), project.name),
            String(format: String(localized: "construction_method_loop_document_stage_format"), stage.displayName),
            String(
                format: String(localized: "construction_method_loop_document_trade_format"),
                ProjectConstructionMethodLoopRecommendationSupport.tradeDisplayName(tradeFilter, allTradesToken: allTradesToken)
            ),
            String(format: String(localized: "construction_method_loop_document_generated_at_format"), generatedAt),
            ""
        ]
        for (index, method) in methods.enumerated() {
            lines.append("\(index + 1). \(methodDisplayTitle(method))")
            let checkItems = method.qualityChecklist.isEmpty
                ? [String(localized: "construction_method_loop_quality_checklist_default_item")]
                : method.qualityChecklist
            for item in checkItems {
                lines.append("   [ ] \(item)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func handoverDocumentText(
        _ methods: [ConstructionMethod],
        generatedAt: String,
        stage: ProjectDocumentRecommendationStage,
        project: Project,
        tradeFilter: String,
        allTradesToken: String
    ) -> String {
        var lines: [String] = [
            String(localized: "construction_method_loop_handover_heading"),
            String(format: String(localized: "construction_method_loop_document_project_format"), project.name),
            String(format: String(localized: "construction_method_loop_document_stage_format"), stage.displayName),
            String(
                format: String(localized: "construction_method_loop_document_trade_format"),
                ProjectConstructionMethodLoopRecommendationSupport.tradeDisplayName(tradeFilter, allTradesToken: allTradesToken)
            ),
            String(format: String(localized: "construction_method_loop_document_generated_at_format"), generatedAt),
            ""
        ]
        for (index, method) in methods.enumerated() {
            lines.append("\(index + 1). \(methodDisplayTitle(method))")
            let trade = ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.trade)
            if !trade.isEmpty {
                lines.append("   " + String(format: String(localized: "construction_method_loop_document_trade_format"), trade))
            }
            let version = ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.versionName)
            lines.append("   " + String(format: String(localized: "construction_method_loop_document_version_format"), version.isEmpty ? "V1" : version))
            if !method.procedureSteps.isEmpty {
                lines.append("   " + String(localized: "construction_method_loop_document_procedure_steps_label"))
                for item in method.procedureSteps {
                    lines.append("   - \(item)")
                }
            }
            if !method.qualityChecklist.isEmpty {
                lines.append("   " + String(localized: "construction_method_loop_document_quality_points_label"))
                for item in method.qualityChecklist {
                    lines.append("   - \(item)")
                }
            }
            if !method.safetyChecklist.isEmpty {
                lines.append("   " + String(localized: "construction_method_loop_document_safety_notes_label"))
                for item in method.safetyChecklist {
                    lines.append("   - \(item)")
                }
            }
            let tutorial = ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.tutorialBody)
            if !tutorial.isEmpty {
                lines.append("   " + String(format: String(localized: "construction_method_loop_document_tutorial_format"), tutorial))
            }
            let sourceURL = ProjectConstructionMethodLoopRecommendationSupport.normalizeText(method.sourceURL)
            if !sourceURL.isEmpty {
                lines.append("   " + String(format: String(localized: "construction_method_loop_document_source_format"), sourceURL))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
