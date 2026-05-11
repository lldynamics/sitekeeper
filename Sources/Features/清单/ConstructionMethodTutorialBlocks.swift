import Foundation

struct ConstructionMethodTutorialTextBlock: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
}

enum ConstructionMethodTutorialBlockCatalog {
    static let quickTools: [ConstructionMethodTutorialTextBlock] = [
        ConstructionMethodTutorialTextBlock(title: "标题1", snippet: "# "),
        ConstructionMethodTutorialTextBlock(title: "标题2", snippet: "## "),
        ConstructionMethodTutorialTextBlock(title: "重点", snippet: "**重点内容**"),
        ConstructionMethodTutorialTextBlock(title: "列表", snippet: "- "),
        ConstructionMethodTutorialTextBlock(title: "引用", snippet: "> ")
    ]

    static let structureTemplates: [ConstructionMethodTutorialTextBlock] = [
        ConstructionMethodTutorialTextBlock(title: "适用场景", snippet: "## 适用场景\n- "),
        ConstructionMethodTutorialTextBlock(title: "施工准备", snippet: "## 施工准备\n- 材料\n- 机具\n- 人员\n"),
        ConstructionMethodTutorialTextBlock(title: "工序步骤", snippet: "## 工序步骤\n1. \n2. \n3. \n"),
        ConstructionMethodTutorialTextBlock(title: "质量检查", snippet: "## 质检要点\n- "),
        ConstructionMethodTutorialTextBlock(title: "安全注意", snippet: "## 安全注意\n- "),
        ConstructionMethodTutorialTextBlock(title: "验收标准", snippet: "## 验收标准\n- ")
    ]
}
