import SwiftUI

enum ToolboxDestination: String, Hashable {
    case watermark
    case materialCenter
    case files
    case calculators
    case quotation
    case labor
    case contacts
    case methods
    case drawingLibrary
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
        "watermark", "material-center", "files", "calculators"
    ]

    static let practicalTools: [QuickToolEntry] = [
        QuickToolEntry(id: "watermark", icon: "camera.aperture", title: "水印相机", desc: "独立拍照，导出带工程水印的现场图片", color: .appDoc, destination: .watermark),
        QuickToolEntry(id: "material-center", icon: "shippingbox.fill", title: "材料中心", desc: "仓库、材料单和材料库统一入口", color: .appPrimaryAction, destination: .materialCenter),
        QuickToolEntry(id: "files", icon: "folder.fill", title: "项目资料", desc: "按项目查看照片、图纸、票据资料和随手记附件", color: .appDoc, destination: .files),
        QuickToolEntry(id: "calculators", icon: "bolt.square.fill", title: "快速计算", desc: "按电气、照明、土建、通用分类选择工具", color: .appPrimaryAction, destination: .calculators),
        QuickToolEntry(id: "quotation", icon: "doc.text.fill", title: "预结算信息", desc: "版本、状态和客户确认信息", color: .appQuotation, destination: .quotation),
        QuickToolEntry(id: "labor", icon: "person.2.fill", title: "人工记录", desc: "工种、人数、工价、金额和结算状态", color: .appSuccess, destination: .labor),
        QuickToolEntry(id: "contacts", icon: "person.crop.rectangle.stack.fill", title: "联系人", desc: "汇总所有项目联系人，按项目筛选", color: .appPeople, destination: .contacts),
        QuickToolEntry(id: "drawing-library", icon: "folder.badge.gearshape", title: "图纸管理", desc: "按项目管理 DWG / DXF / PDF 原件、版本和当前版", color: .appDoc, destination: .drawingLibrary),
        QuickToolEntry(id: "methods", icon: "hammer.fill", title: "施工工艺库", desc: "标准做法、质量要求和安全注意", color: .appSuccess, destination: .methods)
    ]
}
