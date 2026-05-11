import SwiftUI

// MARK: - 工具箱主页

struct ChecklistTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let embedsNavigationStack: Bool
    @AppStorage(UserPreferenceKeys.showTemplates) private var showTemplates = AppFeatureFlags.showTemplates
    @AppStorage("checklistQuickToolOrder") private var quickToolOrderRaw = ""
    @AppStorage("checklistQuickToolCustomized") private var quickToolCustomized = false
    @State private var showQuickToolEditor = false
    @State private var mobileSelectedItem: ToolboxItem?
    @State private var showSortHint = false

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var usesPadIconLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var quickSelectedToolIDs: [String] {
        let rawIDs = quickToolOrderRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        let validRawIDs = rawIDs.filter { id in ToolboxCatalog.practicalTools.contains(where: { $0.id == id }) }
        if !quickToolCustomized && validRawIDs.isEmpty {
            return ToolboxCatalog.defaultQuickToolIDs.filter { id in ToolboxCatalog.practicalTools.contains(where: { $0.id == id }) }
        }
        return validRawIDs
    }

    private var selectedQuickToolIDSet: Set<String> {
        Set(quickSelectedToolIDs)
    }

    private var orderedVisibleTools: [QuickToolEntry] {
        quickSelectedToolIDs.compactMap { id in
            ToolboxCatalog.practicalTools.first(where: { $0.id == id })
        }
    }

    private var quickToolItems: [ToolboxItem] {
        orderedVisibleTools.map(toolboxItem(from:))
    }

    private var practicalUnselectedTools: [QuickToolEntry] {
        ToolboxCatalog.practicalTools.filter { !selectedQuickToolIDSet.contains($0.id) }
    }

    private var toolboxSections: [ToolboxSection] {
        var sections: [ToolboxSection] = []
        if !practicalUnselectedTools.isEmpty {
            sections.append(
                ToolboxSection(
                    title: "实用工具",
                    items: practicalUnselectedTools.map(toolboxItem(from:))
                )
            )
        }
        var otherItems: [ToolboxItem] = [
            ToolboxItem(icon: "stethoscope", title: "数据健康检查", desc: "缺失文件和无效关联检查", color: .orange, destination: .dataHealth),
            ToolboxItem(icon: "person.2.badge.gearshape.fill", title: "供应商库", desc: "联系人、电话、供货范围和备注", color: .blue, destination: .supplierDatabase)
        ]
        if showTemplates {
            otherItems.insert(
                ToolboxItem(
                    icon: "doc.text",
                    title: "模板管理",
                    desc: "常用日志、待办和项目模板（应用前先预览确认）",
                    color: .purple,
                    destination: .template
                ),
                at: 1
            )
        }
        sections.append(
                ToolboxSection(
                    title: "其他",
                    items: otherItems
                )
            )
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
                                Text("快捷工具")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showQuickToolEditor = true
                                } label: {
                                    Label("自定义", systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            if showSortHint {
                                Text("长按拖拽可排序，点击自定义可增删")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                                    .foregroundStyle(.green)
                                Text("已添加全部工具，长按拖拽可排序")
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
                            Text("快捷工具")
                            Spacer()
                            Button {
                                showQuickToolEditor = true
                            } label: {
                                Label("自定义", systemImage: "slider.horizontal.3")
                                    .font(.caption)
                            }
                        }
                    }
                    if showSortHint {
                        Section {
                            Text("长按拖拽可排序，点击自定义可增删")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.orange.opacity(0.08))
                        }
                    }
                    if practicalUnselectedTools.isEmpty {
                        Section {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("已添加全部工具，长按拖拽可排序")
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
        .navigationTitle("工程工具箱")
        .navigationDestination(item: $mobileSelectedItem) { item in
            destinationView(for: item.destination)
        }
        .onAppear {
            if !quickToolCustomized {
                showSortHint = true
            }
        }
        .task(id: quickToolCustomized) {
            await dismissSortHintIfNeeded()
        }
        .sheet(isPresented: $showQuickToolEditor) {
            QuickToolEditorView(
                currentOrderIDs: quickSelectedToolIDs,
                defaultOrderIDs: ToolboxCatalog.defaultQuickToolIDs,
                allTools: ToolboxCatalog.practicalTools,
                onSave: { newIDs in
                    quickToolCustomized = true
                    quickToolOrderRaw = newIDs.joined(separator: ",")
                }
            )
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
        case .warehouse:
            ProjectWarehouseOverviewView()
        case .files:
            ProjectFileBrowserView()
        case .calculators:
            QuickToolCategoryListView()
        case .globalCalc:
            HistoryView()
        case .bookkeeping:
            BookkeepingQuickEntryView()
        case .businessBoard:
            ProjectBusinessView()
        case .materialSheet:
            MaterialSheetView()
        case .quotation:
            QuotationView()
        case .labor:
            LaborRecordView()
        case .contacts:
            ProjectContactDatabaseView()
        case .methods:
            ConstructionMethodLibraryView()
        case .quoteTemplates:
            QuotationTemplateLibraryView()
        case .materialLibrary:
            MaterialLibraryView()
        case .export:
            DataManagementView(initialTab: "导出")
        case .template:
            TemplateView()
        case .dataHealth:
            DataHealthView()
        case .supplierDatabase:
            SupplierDatabaseView()
        }
    }

    @MainActor
    private func dismissSortHintIfNeeded() async {
        guard !quickToolCustomized else {
            showSortHint = false
            return
        }
        guard await DebouncedTask.wait(for: .seconds(4)) else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            showSortHint = false
        }
    }
}

struct BookkeepingQuickEntryView: View {
    @Environment(DataStore.self) private var store

    private var activeProjects: [Project] {
        store.projects.filter { $0.status == .active || $0.status == .paused }
    }

    var body: some View {
        BookkeepingProjectPickerView(projects: activeProjects)
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
