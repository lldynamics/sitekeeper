import SwiftUI

// MARK: - 工具箱主页

struct ChecklistTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let embedsNavigationStack: Bool
    @AppStorage("checklistQuickToolOrder") private var quickToolOrderRaw = ""
    @AppStorage("checklistQuickToolCustomized") private var quickToolCustomized = false
    @State private var showQuickToolEditor = false
    @State private var mobileSelectedItem: ToolboxItem?

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var usesPadIconLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var practicalTools: [QuickToolEntry] {
        ToolboxCatalog.practicalTools
    }

    private var storedQuickToolIDs: [String] {
        quickToolOrderRaw
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var quickSelectedToolIDs: [String] {
        var deduplicatedIDs: [String] = []
        var seen = Set<String>()
        for id in storedQuickToolIDs where seen.insert(id).inserted {
            deduplicatedIDs.append(id)
        }

        let validRawIDs = deduplicatedIDs.filter { id in
            practicalTools.contains(where: { $0.id == id })
        }
        if !quickToolCustomized && validRawIDs.isEmpty {
            return ToolboxCatalog.defaultQuickToolIDs.filter { id in practicalTools.contains(where: { $0.id == id }) }
        }
        return validRawIDs
    }

    private var selectedQuickToolIDSet: Set<String> {
        Set(quickSelectedToolIDs)
    }

    private var orderedVisibleTools: [QuickToolEntry] {
        quickSelectedToolIDs.compactMap { id in
            practicalTools.first(where: { $0.id == id })
        }
    }

    private var quickToolItems: [ToolboxItem] {
        orderedVisibleTools.map(toolboxItem(from:))
    }

    private var practicalUnselectedTools: [QuickToolEntry] {
        practicalTools.filter { !selectedQuickToolIDSet.contains($0.id) }
    }

    private var toolboxSections: [ToolboxSection] {
        var sections: [ToolboxSection] = []
        if !practicalUnselectedTools.isEmpty {
            sections.append(
                ToolboxSection(
                    title: String(localized: "实用工具"),
                    items: practicalUnselectedTools.map(toolboxItem(from:))
                )
            )
        }
        return sections
    }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                checklistSurface
            }
        } else {
            checklistSurface
        }
    }

    private var checklistSurface: some View {
        Group {
            if usesPadIconLayout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(String(localized: "快捷工具"))
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showQuickToolEditor = true
                                } label: {
                                    Label(String(localized: "自定义"), systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                                ForEach(orderedVisibleTools) { tool in
                                    NavigationLink { destinationView(for: tool.destination) } label: {
                                        ToolboxIconCard(
                                            icon: tool.icon,
                                            title: tool.title,
                                            desc: tool.desc,
                                            color: tool.color
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if practicalUnselectedTools.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess)
                                Text(String(localized: "已添加全部工具，长按拖拽可排序"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }

                        ForEach(toolboxSections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.headline)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                                    ForEach(section.items) { item in
                                        NavigationLink { destinationView(for: item.destination) } label: {
                                            ToolboxIconCard(
                                                icon: item.icon,
                                                title: item.title,
                                                desc: item.desc,
                                                color: item.color
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else {
                List {
                    Section {
                        ForEach(quickToolItems) { item in
                            Button {
                                mobileSelectedItem = item
                            } label: {
                                ToolRow(icon: item.icon, title: item.title, desc: item.desc, color: item.color)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    } header: {
                        HStack {
                            Text(String(localized: "快捷工具"))
                            Spacer()
                            Button {
                                showQuickToolEditor = true
                            } label: {
                                Label(String(localized: "自定义"), systemImage: "slider.horizontal.3")
                                    .font(.caption)
                            }
                        }
                    }
                    if practicalUnselectedTools.isEmpty {
                        Section {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess)
                                Text(String(localized: "已添加全部工具，长按拖拽可排序"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(toolboxSections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                Button {
                                    mobileSelectedItem = item
                                } label: {
                                    ToolRow(icon: item.icon, title: item.title, desc: item.desc, color: item.color)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "工程工具箱"))
        .navigationDestination(item: $mobileSelectedItem) { item in
            destinationView(for: item.destination)
        }
        .sheet(isPresented: $showQuickToolEditor) {
            QuickToolEditorView(
                currentOrderIDs: quickSelectedToolIDs,
                defaultOrderIDs: ToolboxCatalog.defaultQuickToolIDs,
                allTools: practicalTools,
                onSave: { newIDs in
                    quickToolCustomized = true
                    quickToolOrderRaw = newIDs.joined(separator: ",")
                }
            )
        }
        .onAppear(perform: sanitizeStoredQuickToolOrder)
    }

    private func sanitizeStoredQuickToolOrder() {
        guard !quickToolOrderRaw.isEmpty else { return }

        var seen = Set<String>()
        let validIDs = storedQuickToolIDs.filter { id in
            guard practicalTools.contains(where: { $0.id == id }) else { return false }
            return seen.insert(id).inserted
        }

        let sanitizedRaw = validIDs.joined(separator: ",")
        guard sanitizedRaw != quickToolOrderRaw else { return }

        quickToolOrderRaw = sanitizedRaw
        if validIDs.isEmpty {
            quickToolCustomized = false
        }
    }

    private func toolboxItem(from quickTool: QuickToolEntry) -> ToolboxItem {
        ToolboxItem(
            id: quickTool.id,
            icon: quickTool.icon,
            title: quickTool.title,
            desc: quickTool.desc,
            color: quickTool.color,
            destination: quickTool.destination
        )
    }

    @ViewBuilder
    private func destinationView(for destination: ToolboxDestination) -> some View {
        switch destination {
        case .watermark:
            WatermarkCameraToolView()
        case .materialCenter:
            MaterialCenterView()
        case .files:
            ProjectFileBrowserView()
        case .calculators:
            QuickToolCategoryListView()
        case .quotation:
            QuotationView()
        case .labor:
            LaborRecordView()
        case .contacts:
            ProjectContactDatabaseView()
        case .methods:
            ConstructionMethodLibraryView()
        case .cadViewer:
            CADViewerToolView()
        case .export:
            DataManagementView(initialRoute: .backup)
        case .template:
            TemplateView()
        }
    }
}

private struct ToolboxSection: Identifiable {
    let title: String
    let items: [ToolboxItem]

    var id: String { title }
}

private struct ToolboxItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let desc: String
    let color: Color
    let destination: ToolboxDestination

    init(icon: String, title: String, desc: String, color: Color, destination: ToolboxDestination) {
        self.id = title
        self.icon = icon
        self.title = title
        self.desc = desc
        self.color = color
        self.destination = destination
    }

    init(id: String, icon: String, title: String, desc: String, color: Color, destination: ToolboxDestination) {
        self.id = id
        self.icon = icon
        self.title = title
        self.desc = desc
        self.color = color
        self.destination = destination
    }
}

extension ToolboxItem: Hashable {
    static func == (lhs: ToolboxItem, rhs: ToolboxItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
