import SwiftUI

enum ToolboxDestination: String, Hashable {
    case watermark
    case warehouse
    case files
    case calculators
    case globalCalc
    case bookkeeping
    case businessBoard
    case materialSheet
    case quotation
    case labor
    case contacts
    case methods
    case quoteTemplates
    case materialLibrary
    case export
    case template
    case dataHealth
    case supplierDatabase
}

struct QuickToolEntry: Identifiable {
    let id: String
    let icon: String
    let title: String
    let desc: String
    let color: Color
    let destination: ToolboxDestination

    init(id: String, icon: String, title: String, desc: String, color: Color, destination: ToolboxDestination) {
        self.id = id
        self.icon = icon
        self.title = title
        self.desc = desc
        self.color = color
        self.destination = destination
    }
}

enum ToolboxCatalog {
    static let defaultQuickToolIDs: [String] = [
        "watermark", "warehouse", "files", "calculators", "global-calc", "bookkeeping"
    ]

    static let practicalTools: [QuickToolEntry] = [
        QuickToolEntry(id: "watermark", icon: "camera.aperture", title: "水印相机", desc: "独立拍照，导出带工程水印的现场图片", color: .blue, destination: .watermark),
        QuickToolEntry(id: "warehouse", icon: "shippingbox.and.arrow.backward.fill", title: "项目仓库", desc: "查看所有项目材料库存和出入库流水", color: .brown, destination: .warehouse),
        QuickToolEntry(id: "files", icon: "folder.fill", title: "项目文件", desc: "按项目查看照片、图纸、票据与随手记附件", color: .indigo, destination: .files),
        QuickToolEntry(id: "calculators", icon: "bolt.square.fill", title: "快速计算", desc: "按电气、照明、土建、通用分类选择工具", color: .orange, destination: .calculators),
        QuickToolEntry(id: "global-calc", icon: "clock.arrow.circlepath", title: "全局计算", desc: "查看全部计算历史和结果", color: .gray, destination: .globalCalc),
        QuickToolEntry(id: "bookkeeping", icon: "receipt.fill", title: "记账", desc: "按项目快速进入收支记账", color: .pink, destination: .bookkeeping),
        QuickToolEntry(id: "business-board", icon: "chart.pie.fill", title: "经营看板", desc: "合同、收款、成本和利润概览", color: .orange, destination: .businessBoard),
        QuickToolEntry(id: "material-sheet", icon: "doc.richtext.fill", title: "材料单", desc: "材料选取、保存草稿、归属项目并统一管理已保存材料", color: .orange, destination: .materialSheet),
        QuickToolEntry(id: "quotation", icon: "doc.text.fill", title: "预结算信息", desc: "版本、状态和客户确认信息", color: .teal, destination: .quotation),
        QuickToolEntry(id: "labor", icon: "person.2.fill", title: "人工/辅材记录", desc: "工种、单价、金额和结算状态", color: .green, destination: .labor),
        QuickToolEntry(id: "contacts", icon: "person.crop.rectangle.stack.fill", title: "联系人", desc: "汇总所有项目联系人，按项目筛选", color: .cyan, destination: .contacts),
        QuickToolEntry(id: "methods", icon: "hammer.fill", title: "施工工艺库", desc: "标准做法、质量要求和安全注意", color: .green, destination: .methods),
        QuickToolEntry(id: "quote-templates", icon: "doc.text.fill", title: "报价模板库", desc: "常用报价项目和套价模板", color: .teal, destination: .quoteTemplates),
        QuickToolEntry(id: "material-library", icon: "books.vertical.fill", title: "常用材料库", desc: "预置材料、规格和单位", color: .indigo, destination: .materialLibrary)
    ]
}
