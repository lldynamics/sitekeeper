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

    static var practicalTools: [QuickToolEntry] {
        [
            QuickToolEntry(id: "watermark", icon: "camera.aperture", title: AppLocalization.string("toolbox.catalog.watermark.title"), desc: AppLocalization.string("toolbox.catalog.watermark.desc"), color: .appDoc, destination: .watermark),
            QuickToolEntry(id: "material-center", icon: "shippingbox.fill", title: AppLocalization.string("toolbox.catalog.materialCenter.title"), desc: AppLocalization.string("toolbox.catalog.materialCenter.desc"), color: .appPrimaryAction, destination: .materialCenter),
            QuickToolEntry(id: "files", icon: "folder.fill", title: AppLocalization.string("toolbox.catalog.files.title"), desc: AppLocalization.string("toolbox.catalog.files.desc"), color: .appDoc, destination: .files),
            QuickToolEntry(id: "calculators", icon: "bolt.square.fill", title: AppLocalization.string("toolbox.catalog.calculators.title"), desc: AppLocalization.string("toolbox.catalog.calculators.desc"), color: .appPrimaryAction, destination: .calculators),
            QuickToolEntry(id: "quotation", icon: "doc.text.fill", title: AppLocalization.string("toolbox.catalog.quotation.title"), desc: AppLocalization.string("toolbox.catalog.quotation.desc"), color: .appQuotation, destination: .quotation),
            QuickToolEntry(id: "labor", icon: "person.2.fill", title: AppLocalization.string("toolbox.catalog.labor.title"), desc: AppLocalization.string("toolbox.catalog.labor.desc"), color: .appSuccess, destination: .labor),
            QuickToolEntry(id: "contacts", icon: "person.crop.rectangle.stack.fill", title: AppLocalization.string("toolbox.catalog.contacts.title"), desc: AppLocalization.string("toolbox.catalog.contacts.desc"), color: .appPeople, destination: .contacts),
            QuickToolEntry(id: "drawing-library", icon: "folder.badge.gearshape", title: AppLocalization.string("图纸台账"), desc: AppLocalization.string("按项目管理 DWG / DXF / PDF 原件、版本和当前版；DWG/DXF 通过外部专业看图软件打开。"), color: .appDoc, destination: .drawingLibrary),
            QuickToolEntry(id: "methods", icon: "hammer.fill", title: AppLocalization.string("toolbox.catalog.methods.title"), desc: AppLocalization.string("toolbox.catalog.methods.desc"), color: .appSuccess, destination: .methods)
        ]
    }
}
