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
        QuickToolEntry(id: "watermark", icon: "camera.aperture", title: String(localized: "toolbox.catalog.watermark.title"), desc: String(localized: "toolbox.catalog.watermark.desc"), color: .appDoc, destination: .watermark),
        QuickToolEntry(id: "material-center", icon: "shippingbox.fill", title: String(localized: "toolbox.catalog.materialCenter.title"), desc: String(localized: "toolbox.catalog.materialCenter.desc"), color: .appPrimaryAction, destination: .materialCenter),
        QuickToolEntry(id: "files", icon: "folder.fill", title: String(localized: "toolbox.catalog.files.title"), desc: String(localized: "toolbox.catalog.files.desc"), color: .appDoc, destination: .files),
        QuickToolEntry(id: "calculators", icon: "bolt.square.fill", title: String(localized: "toolbox.catalog.calculators.title"), desc: String(localized: "toolbox.catalog.calculators.desc"), color: .appPrimaryAction, destination: .calculators),
        QuickToolEntry(id: "quotation", icon: "doc.text.fill", title: String(localized: "toolbox.catalog.quotation.title"), desc: String(localized: "toolbox.catalog.quotation.desc"), color: .appQuotation, destination: .quotation),
        QuickToolEntry(id: "labor", icon: "person.2.fill", title: String(localized: "toolbox.catalog.labor.title"), desc: String(localized: "toolbox.catalog.labor.desc"), color: .appSuccess, destination: .labor),
        QuickToolEntry(id: "contacts", icon: "person.crop.rectangle.stack.fill", title: String(localized: "toolbox.catalog.contacts.title"), desc: String(localized: "toolbox.catalog.contacts.desc"), color: .appPeople, destination: .contacts),
        QuickToolEntry(id: "drawing-library", icon: "folder.badge.gearshape", title: String(localized: "图纸台账"), desc: String(localized: "按项目管理 DWG / DXF / PDF 原件、版本和当前版；DWG/DXF 通过外部专业看图软件打开。"), color: .appDoc, destination: .drawingLibrary),
        QuickToolEntry(id: "methods", icon: "hammer.fill", title: String(localized: "toolbox.catalog.methods.title"), desc: String(localized: "toolbox.catalog.methods.desc"), color: .appSuccess, destination: .methods)
    ]
}
