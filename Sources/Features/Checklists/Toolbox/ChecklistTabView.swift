import SwiftUI
import UIKit

// MARK: - 工具箱主页

struct ChecklistTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.expandedPhoneWorkspaceWidth) private var expandedPhoneWorkspaceWidth
    let embedsNavigationStack: Bool
    @AppStorage(UserPreferenceKeys.checklistQuickToolOrder) private var quickToolOrderRaw = ""
    @AppStorage(UserPreferenceKeys.checklistQuickToolCustomized) private var quickToolCustomized = false
    @State private var showQuickToolEditor = false
    @State private var mobileSelectedItem: ToolboxItem?
    @State private var phoneSelectedItem: ToolboxItem?
    @State private var phoneToolPath = NavigationPath()
    @State private var phoneShowsDetail = false
    @State private var phoneDetailExpanded = false
    @ScaledMetric(relativeTo: .body) private var expandedPhoneMinimumWidth: CGFloat = 820

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

    private var usesPadIconLayout: Bool {
        horizontalSizeClass == .regular
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
                    title: AppLocalization.string("实用工具"),
                    items: practicalUnselectedTools.map(toolboxItem(from:))
                )
            )
        }
        return sections
    }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone, embedsNavigationStack {
            phoneToolboxWorkspace
                .sheet(isPresented: $showQuickToolEditor) {
                    quickToolEditor
                }
                .onAppear(perform: sanitizeStoredQuickToolOrder)
        } else if embedsNavigationStack {
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
                                Text(AppLocalization.string("快捷工具"))
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showQuickToolEditor = true
                                } label: {
                                    Label(AppLocalization.string("自定义"), systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                                ForEach(orderedVisibleTools) { tool in
                                    Button { mobileSelectedItem = toolboxItem(from: tool) } label: {
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
                                Text(AppLocalization.string("已添加全部工具，长按拖拽可排序"))
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
                                        Button { mobileSelectedItem = item } label: {
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
                mobileToolList { mobileSelectedItem = $0 }
            }
        }
        .navigationTitle(AppLocalization.string("工程工具箱"))
        .navigationDestination(item: $mobileSelectedItem) { item in
            destinationView(for: item.destination)
        }
        .sheet(isPresented: $showQuickToolEditor) {
            quickToolEditor
        }
        .onAppear(perform: sanitizeStoredQuickToolOrder)
    }

    private var quickToolEditor: some View {
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

    // Keep both navigation owners mounted while the available width changes.
    // Expanding the selected tool changes frames, never its view identity or navigation path.
    private var phoneToolboxWorkspace: some View {
        GeometryReader { geometry in
            let workspaceWidth = expandedPhoneWorkspaceWidth > 0 ? expandedPhoneWorkspaceWidth : geometry.size.width
            let isWide = ExpandedPhoneWorkspaceLayout.isAvailable(
                width: workspaceWidth,
                minimumWidth: expandedPhoneMinimumWidth
            )
            let showsCatalog = isWide ? !phoneDetailExpanded : !phoneShowsDetail
            let sidebarWidth = isWide ? min(
                geometry.size.width,
                ExpandedPhoneWorkspaceLayout.sidebarWidth(containerWidth: workspaceWidth,
                                                         minimumWorkspaceWidth: expandedPhoneMinimumWidth)
            ) : geometry.size.width
            let catalogWidth = showsCatalog ? sidebarWidth : 0
            let spacing: CGFloat = isWide && showsCatalog ? AppSpacing.normal : 0
            let detailWidth = max(0, geometry.size.width - catalogWidth - spacing)

            HStack(spacing: spacing) {
                NavigationStack {
                    mobileToolList(
                        highlightedItemID: phoneSelectedItem?.id,
                        fillsExpandedPane: isWide,
                        onSelect: selectPhoneTool
                    )
                        .navigationTitle(AppLocalization.string("工程工具箱"))
                        .navigationBarTitleDisplayMode(isWide ? .inline : .automatic)
                        .toolbarBackground(
                            isWide ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.bar),
                            for: .navigationBar
                        )
                        .toolbarBackground(isWide ? .visible : .automatic, for: .navigationBar)
                }
                .frame(width: showsCatalog ? sidebarWidth : max(320, sidebarWidth))
                .frame(width: catalogWidth, alignment: .leading)
                .clipped()
                .opacity(showsCatalog ? 1 : 0)
                .allowsHitTesting(showsCatalog)
                .accessibilityHidden(!showsCatalog)
                .accessibilityIdentifier("toolbox-phone-catalog")

                VStack(spacing: 0) {
                    phoneDetailControls(isWide: isWide)
                    NavigationStack(path: $phoneToolPath) {
                        if let item = phoneSelectedItem {
                            destinationView(for: item.destination)
                                .id(item.id)
                        } else {
                            ContentUnavailableView(
                                AppLocalization.string("工程工具箱"),
                                systemImage: "wrench.and.screwdriver",
                                description: Text(AppLocalization.string("toolbox_select_tool_hint"))
                            )
                        }
                    }
                }
                .frame(width: detailWidth > 0 ? detailWidth : 320)
                .frame(width: detailWidth, alignment: .leading)
                .clipped()
                .opacity(detailWidth > 0 ? 1 : 0)
                .allowsHitTesting(detailWidth > 0)
                .accessibilityHidden(detailWidth <= 0)
                .accessibilityIdentifier("toolbox-phone-detail")
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .background(alignment: .leading) {
                if isWide && showsCatalog {
                    HStack(spacing: 0) {
                        Color(.secondarySystemGroupedBackground)
                            .frame(width: catalogWidth)
                        Color(.systemBackground)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .overlay(alignment: .leading) {
                if isWide && showsCatalog {
                    ExpandedPhoneColumnDivider()
                        .frame(width: 1)
                        .offset(x: catalogWidth - 0.5)
                }
            }
        }
    }

    private func phoneDetailControls(isWide: Bool) -> some View {
        HStack(spacing: AppSpacing.normal) {
            if !isWide {
                Button {
                    // Returning to the catalog is a visibility change, so reopening this tool keeps its inputs.
                    phoneShowsDetail = false
                } label: {
                    Label(AppLocalization.string("toolbox_show_catalog"), systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("toolbox-show-catalog")
            }
            Spacer(minLength: 0)
            if isWide {
                Button {
                    phoneDetailExpanded.toggle()
                } label: {
                    Label(
                        AppLocalization.string(phoneDetailExpanded ? "toolbox_restore_columns" : "toolbox_expand_detail"),
                        systemImage: phoneDetailExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                    )
                    .frame(minHeight: 44)
                }
                .disabled(phoneSelectedItem == nil)
                .accessibilityIdentifier("toolbox-toggle-detail-expanded")
            }
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, AppSpacing.normal)
        .padding(.vertical, AppSpacing.tight)
        .background(
            isWide ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.bar),
            ignoresSafeAreaEdges: isWide ? [] : .all
        )
    }

    private func selectPhoneTool(_ item: ToolboxItem) {
        if phoneSelectedItem?.id != item.id {
            phoneToolPath = NavigationPath()
        }
        phoneSelectedItem = item
        phoneShowsDetail = true
    }

    private func mobileToolList(
        highlightedItemID: String? = nil,
        fillsExpandedPane: Bool = false,
        onSelect: @escaping (ToolboxItem) -> Void
    ) -> some View {
        List {
            Section {
                if fillsExpandedPane {
                    catalogSectionHeader(fillsExpandedPane: true) { quickToolsHeader }
                }
                ForEach(quickToolItems) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        ToolRow(icon: item.icon, title: item.title, desc: item.desc, color: item.color, showsChevron: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: fillsExpandedPane ? .infinity : nil, alignment: .leading)
                    .contentShape(Rectangle())
                    .listRowInsets(fillsExpandedPane ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : nil)
                    .modifier(ToolboxCatalogRowBackgroundModifier(
                        isSelected: highlightedItemID == item.id,
                        fillsExpandedPane: fillsExpandedPane
                    ))
                    .accessibilityAddTraits(highlightedItemID == item.id ? .isSelected : [])
                }
            } header: {
                if !fillsExpandedPane {
                    catalogSectionHeader(fillsExpandedPane: false) { quickToolsHeader }
                }
            }
            if practicalUnselectedTools.isEmpty {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text(AppLocalization.string("已添加全部工具，长按拖拽可排序"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(toolboxSections) { section in
                Section {
                    if fillsExpandedPane {
                        catalogSectionHeader(fillsExpandedPane: true) { Text(section.title) }
                    }
                    ForEach(section.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            ToolRow(icon: item.icon, title: item.title, desc: item.desc, color: item.color, showsChevron: true)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: fillsExpandedPane ? .infinity : nil, alignment: .leading)
                        .contentShape(Rectangle())
                        .listRowInsets(fillsExpandedPane ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : nil)
                        .modifier(ToolboxCatalogRowBackgroundModifier(
                            isSelected: highlightedItemID == item.id,
                            fillsExpandedPane: fillsExpandedPane
                        ))
                        .accessibilityAddTraits(highlightedItemID == item.id ? .isSelected : [])
                    }
                } header: {
                    if !fillsExpandedPane {
                        catalogSectionHeader(fillsExpandedPane: false) { Text(section.title) }
                    }
                }
            }
        }
        .modifier(ToolboxCatalogListStyleModifier(isExpanded: fillsExpandedPane))
        .frame(maxWidth: fillsExpandedPane ? .infinity : nil, maxHeight: fillsExpandedPane ? .infinity : nil)
        // The outer workspace already stays within the screen's safe area. Its catalogue
        // is an interior pane, so it must not reserve the screen's trailing navigation rail again.
        .ignoresSafeArea(.container, edges: fillsExpandedPane ? .horizontal : [])
        .modifier(ExpandedPhoneSidebarScrollModifier(isExpanded: fillsExpandedPane))
    }

    private var quickToolsHeader: some View {
        HStack {
            Text(AppLocalization.string("快捷工具"))
            Spacer()
            Button {
                showQuickToolEditor = true
            } label: {
                Label(AppLocalization.string("自定义"), systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
    }

    private func catalogSectionHeader<Content: View>(
        fillsExpandedPane: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(fillsExpandedPane ? .subheadline : nil)
            .foregroundStyle(.secondary)
            .frame(maxWidth: fillsExpandedPane ? .infinity : nil, alignment: .leading)
            .listRowInsets(fillsExpandedPane ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12) : nil)
            .listRowBackground(fillsExpandedPane ? Color(.secondarySystemGroupedBackground) : nil)
            .listRowSeparator(fillsExpandedPane ? .hidden : .automatic)
            .accessibilityAddTraits(.isHeader)
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
        case .drawingLibrary:
            DrawingLibraryToolView()
        }
    }
}

private struct ToolboxCatalogListStyleModifier: ViewModifier {
    let isExpanded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isExpanded {
            // This is a bounded catalogue pane, not a full-screen grouped settings list.
            // Its headers and rows share the same list viewport and explicit surface.
            content.listStyle(.plain)
        } else {
            content
        }
    }
}

private struct ToolboxCatalogRowBackgroundModifier: ViewModifier {
    let isSelected: Bool
    let fillsExpandedPane: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if fillsExpandedPane {
            content.listRowBackground(
                Color(.secondarySystemGroupedBackground)
                    .overlay(isSelected ? Color.appSuccess.opacity(0.12) : Color.clear)
            )
        } else {
            content.listRowBackground(isSelected ? Color.appSuccess.opacity(0.12) : nil)
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
