import Foundation

struct ConstructionMethodTutorialTextBlock: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
}

enum ConstructionMethodTutorialBlockCatalog {
    static let quickTools: [ConstructionMethodTutorialTextBlock] = [
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.heading1.title"), snippet: String(localized: "construction.tutorial.block.heading1.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.heading2.title"), snippet: String(localized: "construction.tutorial.block.heading2.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.emphasis.title"), snippet: String(localized: "construction.tutorial.block.emphasis.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.list.title"), snippet: String(localized: "construction.tutorial.block.list.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.quote.title"), snippet: String(localized: "construction.tutorial.block.quote.snippet"))
    ]

    static let structureTemplates: [ConstructionMethodTutorialTextBlock] = [
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.scenario.title"), snippet: String(localized: "construction.tutorial.block.scenario.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.preparation.title"), snippet: String(localized: "construction.tutorial.block.preparation.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.steps.title"), snippet: String(localized: "construction.tutorial.block.steps.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.quality.title"), snippet: String(localized: "construction.tutorial.block.quality.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.safety.title"), snippet: String(localized: "construction.tutorial.block.safety.snippet")),
        ConstructionMethodTutorialTextBlock(title: String(localized: "construction.tutorial.block.acceptance.title"), snippet: String(localized: "construction.tutorial.block.acceptance.snippet"))
    ]
}
