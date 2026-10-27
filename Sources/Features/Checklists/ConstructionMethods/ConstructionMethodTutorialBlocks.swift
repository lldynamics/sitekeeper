import Foundation

struct ConstructionMethodTutorialTextBlock: Identifiable {
    let id: String
    let title: String
    let snippet: String
}

enum ConstructionMethodTutorialBlockCatalog {
    static var quickTools: [ConstructionMethodTutorialTextBlock] {
        [
            ConstructionMethodTutorialTextBlock(id: "heading1", title: AppLocalization.string("construction.tutorial.block.heading1.title"), snippet: AppLocalization.string("construction.tutorial.block.heading1.snippet")),
            ConstructionMethodTutorialTextBlock(id: "heading2", title: AppLocalization.string("construction.tutorial.block.heading2.title"), snippet: AppLocalization.string("construction.tutorial.block.heading2.snippet")),
            ConstructionMethodTutorialTextBlock(id: "emphasis", title: AppLocalization.string("construction.tutorial.block.emphasis.title"), snippet: AppLocalization.string("construction.tutorial.block.emphasis.snippet")),
            ConstructionMethodTutorialTextBlock(id: "list", title: AppLocalization.string("construction.tutorial.block.list.title"), snippet: AppLocalization.string("construction.tutorial.block.list.snippet")),
            ConstructionMethodTutorialTextBlock(id: "quote", title: AppLocalization.string("construction.tutorial.block.quote.title"), snippet: AppLocalization.string("construction.tutorial.block.quote.snippet"))
        ]
    }

    static var structureTemplates: [ConstructionMethodTutorialTextBlock] {
        [
            ConstructionMethodTutorialTextBlock(id: "scenario", title: AppLocalization.string("construction.tutorial.block.scenario.title"), snippet: AppLocalization.string("construction.tutorial.block.scenario.snippet")),
            ConstructionMethodTutorialTextBlock(id: "preparation", title: AppLocalization.string("construction.tutorial.block.preparation.title"), snippet: AppLocalization.string("construction.tutorial.block.preparation.snippet")),
            ConstructionMethodTutorialTextBlock(id: "steps", title: AppLocalization.string("construction.tutorial.block.steps.title"), snippet: AppLocalization.string("construction.tutorial.block.steps.snippet")),
            ConstructionMethodTutorialTextBlock(id: "quality", title: AppLocalization.string("construction.tutorial.block.quality.title"), snippet: AppLocalization.string("construction.tutorial.block.quality.snippet")),
            ConstructionMethodTutorialTextBlock(id: "safety", title: AppLocalization.string("construction.tutorial.block.safety.title"), snippet: AppLocalization.string("construction.tutorial.block.safety.snippet")),
            ConstructionMethodTutorialTextBlock(id: "acceptance", title: AppLocalization.string("construction.tutorial.block.acceptance.title"), snippet: AppLocalization.string("construction.tutorial.block.acceptance.snippet"))
        ]
    }
}
