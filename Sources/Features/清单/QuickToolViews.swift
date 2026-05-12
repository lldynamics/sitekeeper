import SwiftUI

struct QuickToolCategoryListView: View {
    private let sections = ["电气", "照明", "土建", "通用"]
    @AppStorage("favoriteCalculators") private var favoriteRaw = ""
    @AppStorage("recentQuickTools") private var recentRaw = ""

    private var allTools: [QuickToolItem] {
        CalculatorDestination.allCases.map(QuickToolItem.init) + [watermarkCameraTool]
    }

    private var favoriteTitles: [String] {
        favoriteRaw.split(separator: ",").map(String.init)
    }

    private var recentTitles: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    private var favoriteTools: [QuickToolItem] {
        orderedTools(matching: favoriteTitles)
    }

    private var recentTools: [QuickToolItem] {
        orderedTools(matching: recentTitles).filter { tool in
            !favoriteTitles.contains(tool.title)
        }
    }

    var body: some View {
        List {
            if !favoriteTools.isEmpty {
                Section("常用工具") {
                    ForEach(favoriteTools) { tool in
                        QuickToolNavigationRow(tool: tool, color: quickToolColor(for: tool.section))
                    }
                }
            }

            if !recentTools.isEmpty {
                Section("最近使用") {
                    ForEach(recentTools.prefix(5)) { tool in
                        QuickToolNavigationRow(tool: tool, color: quickToolColor(for: tool.section))
                    }
                }
            }

            Section("选择专业") {
                ForEach(sections, id: \.self) { section in
                    NavigationLink { QuickToolSectionView(section: section) } label: {
                        ToolRow(
                            icon: quickToolIcon(for: section),
                            title: section,
                            desc: "\(allTools.filter { $0.section == section }.count) 个常用工具",
                            color: quickToolColor(for: section)
                        )
                    }
                }
            }
        }
        .navigationTitle("快捷工具")
    }

    private func orderedTools(matching titles: [String]) -> [QuickToolItem] {
        titles.compactMap { title in
            allTools.first { $0.title == title }
        }
    }

    private var watermarkCameraTool: QuickToolItem {
        QuickToolItem(
            icon: "camera.aperture",
            title: "水印相机",
            desc: "独立拍照并导出带工程水印的现场图片",
            section: "通用",
            destination: .watermarkCamera
        )
    }
}

struct QuickToolSectionView: View {
    let section: String
    @State private var searchText = ""

    private var tools: [QuickToolItem] {
        let items = CalculatorDestination.allCases.map(QuickToolItem.init).filter { $0.section == section }
        return SearchMatcher.filter(items, keyword: searchText)
    }

    var body: some View {
        List {
            if tools.isEmpty {
                ContentUnavailableView("没有匹配工具", systemImage: "magnifyingglass")
            } else {
                Section(section) {
                    ForEach(tools) { tool in
                        QuickToolNavigationRow(tool: tool, color: quickToolColor(for: section))
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索\(section)工具")
        .navigationTitle(section)
    }
}

private struct QuickToolNavigationRow: View {
    let tool: QuickToolItem
    let color: Color
    @AppStorage("favoriteCalculators") private var favoriteRaw = ""
    @AppStorage("recentQuickTools") private var recentRaw = ""

    private var isFavorite: Bool {
        favoriteTitles.contains(tool.title)
    }

    private var favoriteTitles: [String] {
        favoriteRaw.split(separator: ",").map(String.init)
    }

    var body: some View {
        NavigationLink {
            tool.destination.view
                .onAppear { rememberRecentTool() }
        } label: {
            ToolRow(
                icon: isFavorite ? "star.fill" : tool.icon,
                title: tool.title,
                desc: tool.desc,
                color: isFavorite ? .appWarning : color
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleFavorite()
            } label: {
                Label(isFavorite ? "取消常用" : "设为常用", systemImage: isFavorite ? "star.slash" : "star.fill")
            }
            .tint(isFavorite ? .appMuted : .appWarning)
        }
    }

    private func toggleFavorite() {
        var titles = favoriteTitles
        if let index = titles.firstIndex(of: tool.title) {
            titles.remove(at: index)
        } else {
            titles.insert(tool.title, at: 0)
        }
        favoriteRaw = titles.joined(separator: ",")
    }

    private func rememberRecentTool() {
        var titles = recentRaw.split(separator: "\n").map(String.init).filter { $0 != tool.title }
        titles.insert(tool.title, at: 0)
        recentRaw = titles.prefix(8).joined(separator: "\n")
    }
}

struct QuickToolItem: Identifiable {
    let icon: String
    let title: String
    let desc: String
    let section: String
    let destination: QuickToolDestination

    var id: String { title }

    init(_ def: CalculatorDestination) {
        icon = def.icon
        title = def.title
        desc = def.desc
        section = def.section
        destination = .calculator(def)
    }

    init(icon: String, title: String, desc: String, section: String, destination: QuickToolDestination) {
        self.icon = icon
        self.title = title
        self.desc = desc
        self.section = section
        self.destination = destination
    }
}

extension QuickToolItem: Searchable {
    var searchableFields: [String] {
        [title, desc]
    }
}

enum QuickToolDestination {
    case calculator(CalculatorDestination)
    case watermarkCamera

    @ViewBuilder
    var view: some View {
        switch self {
        case .calculator(let destination):
            destination.destination
        case .watermarkCamera:
            WatermarkCameraToolView()
        }
    }
}

private func quickToolIcon(for section: String) -> String {
    switch section {
    case "电气":
        return "bolt.fill"
    case "照明":
        return "lightbulb.fill"
    case "土建":
        return "cube.fill"
    default:
        return "arrow.left.arrow.right"
    }
}

private func quickToolColor(for section: String) -> Color {
    switch section {
    case "电气":
        return .appCalculations
    case "照明":
        return .appWarning
    case "土建":
        return .appInventory
    default:
        return .appDoc
    }
}
